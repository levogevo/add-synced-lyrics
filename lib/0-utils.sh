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

# ANSI colors
readonly RED='\e[0;31m'
readonly GREEN='\e[0;32m'
readonly PURPLE='\e[0;35m'
readonly YELLOW='\e[0;33m'
readonly CYAN='\e[0;36m'
readonly NC='\e[0m'

stderr() {
    local word="${WORD:-}"
    local color="${COLOR:-}"
    local function="${FUNCNAME[2]}"
    if [[ "${function}" =~ void ]]; then
        function="${FUNCNAME[3]}"
    fi
    echo \
        -e \
        "${color}${word}${NC}" \
        "[${function}]" \
        "$@" 1>&2
}
echo_info() { WORD=INFO COLOR="${CYAN}" stderr "$@"; }
echo_fail() { WORD=FAIL COLOR="${RED}" stderr "$@"; }
echo_pass() { WORD=PASS COLOR="${GREEN}" stderr "$@"; }
echo_dbug() { WORD=DBUG COLOR="${PURPLE}" stderr "$@"; }

# only perform the command given if ${DEBUG} is enabled
debug() {
    if [[ ${DEBUG} == false ]]; then
        return 0
    fi

    "$@"
}

# only perform the command given if ${DRY_RUN} is enabled
void() {
    if [[ ${DRY_RUN} == true ]]; then
        return 0
    fi

    "$@"
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
            echo_fail "missing ${util}!"
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
            echo_fail "tempdir ${TMPDIR} is not empty!"
            echo_fail "aborting operation"
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
        echo_fail "failed to download file for ${url} despite no librelyrics error"
        return 1
    fi

    local fileContents=''
    if [[ -n "${downloadedFile}" ]]; then
        fileContents="$(<"${downloadedFile}")"
        rm "${downloadedFile}" || return 1
    fi

    if [[ ${librelyricsRet} -eq 0 && -z ${fileContents} ]]; then
        echo_fail "failed to read file for ${url} despite no librelyrics error"
        return 1
    fi

    echo "${fileContents}"
}

download_with_librelyrics() {
    local isrc="$1"
    local output="$2"
    local urlType="$3"

    if [[ ! "${urlType}" =~ spotify|deezer ]]; then
        echo_fail "only spotify|deezer are supported"
        return 1
    fi

    local url=''
    url="$(get_"${urlType}"_url "${isrc}")" || return 1

    local lyrics=''
    lyrics="$(cache_command \
        librelyrics_dl \
        "${url}")"

    if [[ -z "${lyrics}" ]]; then
        debug echo_fail "could not find lyrics for ${isrc} using ${urlType}"
        return 1
    fi

    debug echo_info "found lyrics for ${isrc} with ${urlType}"
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
        echo_fail "could not find ISRC for ${file}"
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
