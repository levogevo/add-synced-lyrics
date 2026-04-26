#!/usr/bin/env bash

# many functions are invoked via variables
# shellcheck disable=SC2329

# check commands exist
# "$@" commands to check
have_cmd() {
    for cmd in "$@"; do
        command -v "${cmd}" &>/dev/null || return 1
    done
}

# validate results from `jq -r`
jq_result_valid() {
    local result="$1"
    if [[ -z "${result}" || "${result}" == 'null' ]]; then
        return 1
    fi
    return 0
}

stderr() { echo "$*" 1>&2; }
info() { stderr "INFO [${FUNCNAME[1]}]: $*"; }
error() { stderr "ERROR [${FUNCNAME[1]}]: $*"; }

# only echo "$@" if ${DEBUG} is true
debug() {
    if [[ ${DEBUG} == false ]]; then
        return 0
    fi

    stderr "$@"
}

# do not do anything
# if ${DRY_RUN} is enabled
void() {
    local cmd=("$@")
    if [[ ${DRY_RUN} == true ]]; then
        return 0
    else
        "${cmd[@]}"
        return $?
    fi
}

# print out "$@" formatted for bash
# if ${DRY_RUN} is enabled
# otherwise, execute the actual command
dry() {
    local cmd=("$@")
    if [[ ${DRY_RUN} == true ]]; then
        local numCmd="${#cmd[@]}"
        test "${numCmd}" -eq 0 && return 0
        local firstLine="'${cmd[0]}'"
        test "${numCmd}" -gt 1 && firstLine+=' \'
        stderr "${firstLine}"
        local earlyStop=$((numCmd - 1))
        for ((i = 1; i < earlyStop; i++)); do
            stderr "  '${cmd[${i}]}' \\"
        done
        stderr "  '${cmd[${i}]}'"
    else
        "${cmd[@]}"
        return $?
    fi
}

# check required utilities for this project
check_required_utils() {
    local utils=(
        base64
        cat
        ffprobe
        jq
        librelyrics
        spotify # uv tool install --python 3.8 spotify-cli
    )
    local missing=false
    for util in "${utils[@]}"; do
        if ! have_cmd "${util}"; then
            error "missing ${util}!"
            missing=true
        fi
    done

    if [[ ${missing} == true ]]; then
        return 1
    else
        return 0
    fi
}

cache_command() {
    local cmd=("$@")
    local hash cacheFile cmdOut contents ret
    hash="$(sha256sum <<<"${cmd[*]}")" || return 1
    read -r cacheFile _ <<<"${hash}"
    cacheFilePath="${CACHE_DIR}/${cacheFile}"
    if [[ -f "${cacheFilePath}" && ${DRY_RUN} == false ]]; then
        mapfile -t contents <"${cacheFilePath}"
        ret=$?
        # skip first line since it is the command
        printf '%s\n' "${contents[@]:1}"
    else
        cmdOut="$(dry "${cmd[@]}")"
        ret=$?
        if [[ ${ret} -eq 0 && ${DRY_RUN} == false ]]; then
            {
                echo "${cmd[*]}"
                echo "${cmdOut}"
            } >"${cacheFilePath}" || return 1
            echo "${cmdOut}"
        fi
    fi

    return "${ret}"
}

create_tmp_dir() {
    TMPDIR="$(mktemp -d)" || return 1
    readonly TMPDIR
    trap 'rm -rf ${TMPDIR}' EXIT
}

check_tmp_dir_empty() {
    for f in "${TMPDIR}"/*; do
        if [[ -f "${f}" ]]; then
            error "tempdir ${TMPDIR} is not empty!"
            error "aborting operation"
            return 1
        fi
    done

    return 0
}

# librelyrics only exposes a directory to download to
# so this wrapper function downloads to a directory
# and then outputs the contents of the downloaded file
# to stdout so it can effectively be cached
librelyrics_dl() {
    local url="$1"
    check_tmp_dir_empty || return 1
    librelyrics \
        --directory "${TMPDIR}" \
        "${url}" 1>&2
    local librelyricsRet=$?

    local downloadedFile=''
    for f in "${TMPDIR}/"*; do
        if [[ -f "${f}" ]]; then
            downloadedFile="${f}"
            break
        fi
    done

    if [[ ${librelyricsRet} -eq 0 && -z ${downloadedFile} ]]; then
        error "failed to download file for ${url} despite no librelyrics error"
        return 1
    fi

    local fileContents=''
    if [[ -n "${downloadedFile}" ]]; then
        fileContents="$(<"${downloadedFile}")"
        rm "${downloadedFile}" || return 1
    fi

    if [[ ${librelyricsRet} -eq 0 && -z ${fileContents} ]]; then
        error "failed to read file for ${url} despite no librelyrics error"
        return 1
    fi

    echo "${fileContents}"
}

download_with_librelyrics() {
    local isrc="$1"
    local output="$2"
    local urlType="$3"

    if [[ ! "${urlType}" =~ spotify|deezer ]]; then
        error "only spotify|deezer are supported"
        return 1
    fi

    local url=''
    url="$(get_"${urlType}"_url "${isrc}")" || return 1

    local lyrics=''
    lyrics="$(cache_command \
        librelyrics_dl \
        "${url}")"

    if [[ -z "${lyrics}" ]]; then
        error "could not get lyrics for ${isrc} using ${urlType}"
        return 1
    fi

    info "found lyrics for ${isrc} with ${urlType}"
    echo "${lyrics}" >"${output}"
}

output_eval_functions() {
    while read -r line; do
        IFS=' ' read -r _ _ function <<<"${line}"
        [[ "${function}" == '_determine_inputs_'* ||
            "${function}" == set_default_options ]] || continue
        ${line}
    done <<<"$(declare -F)"
}

get_file_isrc() {
    local file="$1"
    local probe='' jqResult=''

    local probe=''
    probe="$(
        ffprobe \
            -v error \
            -show_entries stream \
            -of json \
            "${file}"
    )" || return 1

    local jqFilter='.streams[] | select(.codec_type == "audio") | .tags | with_entries(.key |= ascii_downcase) | .isrc'
    jqResult="$(jq -r "${jqFilter}" <<<"${probe}")"

    if [[ "${jqResult}" == 'null' ]]; then
        error "failed to find ISRC for ${file}"
        return 1
    fi
    echo "${jqResult}"
}

set_lyric_file_name() {
    local file="$1"
    if [[ ! "${file}" =~ ${MUSIC_EXTENSION_REGEX} ]]; then
        echo "${file} is not a music file"
        return 1
    fi

    echo "${file%.opus}.lrc"
}

is_valid_lrc() {
    local file="$1"

    local valid=1
    while read -r line; do
        [[ "${#line}" -eq 0 ]] && continue
        if [[ "${line}" != '['* ]]; then
            valid=1
            break
        fi
        valid=0
    done <"${file}"

    return ${valid}
}
