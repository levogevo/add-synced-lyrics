#!/usr/bin/env bash

set -u

have_cmd() {
    for cmd in "$@"; do
        command -v "${cmd}" &>/dev/null || return 1
    done
}

# shellcheck disable=SC2329
void() {
    echo "$@" &>/dev/null
}

# shellcheck disable=SC2329
dry() {
    local args=("$@")
    local numArgs="${#args[@]}"
    test "${numArgs}" -eq 0 && return 0
    echo "'${args[0]}'"
    local earlyStop=$((numArgs - 1))
    for ((i = 1; i < earlyStop; i++)); do
        echo "  '${args[${i}]}' \\"
    done
    echo "  '${args[${i}]}'"
}

check_required_utils() {
    local utils=(
        ffmpeg
        jq
        syncedlyrics
        librelyrics
        spotify # uv tool install --python 3.8 spotify-cli
    )
    local missing=false
    for util in "${utils[@]}"; do
        if ! have_cmd "${util}"; then
            echo "missing ${util}!"
            missing=true
        fi
    done

    if [[ ${missing} == true ]]; then
        return 1
    else
        return 0
    fi
}

# shellcheck disable=SC2329
get_spotify_url() {
    local search="$1"
    local response artistAlbumTitle url
    response="$(
        spotify \
            search \
            --track "${search}" \
            --limit 1 \
            --raw
    )"

    artistAlbumTitle="$(
        jq -r '.items[0] | "\(.artists[0].name) - \(.album.name) - \(.name)"' \
            <<<"${response}"
    )"

    if [[ "${artistAlbumTitle}" != "${search}" ]]; then
        echo "${search} could not be found"
        return 1
    fi

    url="$(
        jq -r '.items[0] | "\(.external_urls.spotify)"' <<<"${response}"
    )"

    if [[ -z "${url}" ]]; then
        echo "could not determine url for ${search}"
        return 1
    fi

    echo "${url}"
}

output_eval_functions() {
    while read -r line; do
        IFS=' ' read -r _ _ function <<<"${line}"
        [[ "${function}" == '_determine_inputs_'* ||
            "${function}" == set_default_options ]] || continue
        ${line}
    done <<<"$(declare -F)"
}

get_artist_album_title() {
    local file="$1"
    local jqFilter='.streams[] | select(.codec_type == "audio") | .tags | "\(.ARTIST) - \(.ALBUM) - \(.TITLE)"'
    ffprobe \
        -v error \
        -show_entries stream \
        -of json \
        "${file}" | jq \
        -r "${jqFilter}"
}

set_lyric_file_name() {
    local file="$1"
    if [[ ! "${file}" =~ ${MUSIC_EXTENSION_REGEX} ]]; then
        echo "${file} is not a music file"
        return 1
    fi

    echo "${file%.opus}.lrc"
}

bash_basename() {
    local tmp
    path="$1"
    suffix="${2:-''}"

    tmp=${path%"${path##*[!/]}"}
    tmp=${tmp##*/}
    tmp=${tmp%"${suffix/"$tmp"/}"}

    printf '%s\n' "${tmp:-/}"
}

readonly PROGNAME="$(bash_basename "$0")"

usage() {
    echo "${PROGNAME} [options]

OPTIONS:
  -d, --dir       process files in directory
  -r, --recurse   recursively process directory
  -f, --file      process one file
  -n, --dry-run   do not actually add synced lyrics,
                  just show the files that would be processed
  -e, --eval      output bash functions that can be directly processed
                  by eval for use with testing this script.
  -i, --ignore    ignore errors, and continue attempting to find lyrics
                  even in the case of errors
  -h, --help      show this output"
    exit ${EXIT_CODE:-1}
}

set_default_options() {
    DIR=${DIR:-}
    FILE=${FILE:-}
    RECURSE=${RECURSE:-false}
    DRY_RUN=${DRY_RUN:-false}
    IGNORE=${IGNORE:-false}
    readonly MUSIC_EXTENSION_REGEX='.*\.(opus)$'
}

process_options() {
    while [[ $# -gt 0 ]]; do
        option="$1"
        value="${2:-}"
        case "${option}" in
        -d | --dir)
            if [[ ! -d "${value}" ]]; then
                echo "directory ${value} does not exist"
                usage
            fi
            readonly DIR="${value}"
            shift 2
            ;;
        -r | --recurse)
            readonly RECURSE=true
            shift 1
            ;;
        -n | --dry-run)
            readonly DRY_RUN=true
            shift 1
            ;;
        -i | --ignore)
            readonly IGNORE=true
            shift 1
            ;;
        -e | --eval)
            output_eval_functions
            exit 0
            ;;
        -f | --file)
            if [[ ! -f "${value}" ]]; then
                echo "file ${value} does not exist"
                usage
            fi
            readonly FILE="${value}"
            shift 2
            ;;
        -h | --help)
            EXIT_CODE=0 usage
            ;;
        *)
            echo "bad option"
            usage
            ;;
        esac
    done

    if [[ "${DIR:-}${FILE:-}" == '' ]]; then
        echo "either --dir or --file must be used"
        usage
    fi

    if [[ -n "${DIR}" && -n "${FILE}" ]]; then
        echo "cannot process both directory and file"
        usage
    fi

    if [[ "${RECURSE}" == true && -n "${FILE}" ]]; then
        echo "--recurse can only be used with --dir"
        usage
    fi
}

_determine_inputs_fd() {
    local fdCmd=(
        fd
        --type f
        "${MUSIC_EXTENSION_REGEX}"
        "${DIR}"
    )

    if [[ "${RECURSE}" == false ]]; then
        fdCmd+=(--max-depth 1)
    fi

    mapfile -t INPUTS < <("${fdCmd[@]}" | sort)
}

_determine_inputs_find() {
    local findCmd=(
        find
        "${DIR}"
    )

    if [[ "${RECURSE}" == false ]]; then
        findCmd+=(-maxdepth 1)
    fi

    findCmd+=(
        -regextype posix-extended
        -regex "${MUSIC_EXTENSION_REGEX}"
        -type f
    )

    mapfile -t INPUTS < <("${findCmd[@]}" | sort)
}

_determine_inputs_bash() {
    local unsortedInputs=()
    if [[ "${RECURSE}" == true ]]; then
        local preGlobstar="$(shopt -p globstar)"
        shopt -s globstar
        for f in "${DIR}"/**/*; do
            unsortedInputs+=("${f}")
        done
        ${preGlobstar}
    else
        for f in "${DIR}"/**; do
            unsortedInputs+=("${f}")
        done
    fi

    local filteredInputs=()
    for input in "${unsortedInputs[@]}"; do
        [[ "${input}" =~ ${MUSIC_EXTENSION_REGEX} ]] || continue
        filteredInputs+=("${input}")
    done

    mapfile -t INPUTS < <(printf '%s\n' "${filteredInputs[@]}" | sort)
}

determine_inputs() {
    INPUTS=()
    if [[ -n "${FILE}" ]]; then
        INPUTS=("${FILE}")
    elif have_cmd fd; then
        _determine_inputs_fd || return 1
    elif have_cmd find; then
        _determine_inputs_find || return 1
    else
        _determine_inputs_bash || return 1
    fi

    if [[ "${#INPUTS[@]}" -eq 0 ]]; then
        echo "no inputs found, something is wrong"
        exit 1
    fi

    readonly INPUTS
}

create_tmp_dir() {
    TMPDIR="$(mktemp -d)" || return 1
    readonly TMPDIR
    trap 'rm -rf ${TMPDIR}' EXIT
}

process_inputs() {
    local dry='' void=''
    if [[ "${DRY_RUN}" == true ]]; then
        dry=dry
        void=void
    fi

    local search='' output='' spotifyUrl='' ret=''
    for input in "${INPUTS[@]}"; do
        if [[ ${IGNORE} == false && ${ret} -ne 0 ]]; then
            return 1
        fi

        if [[ "${input,,}" == *'instrumental'* ]]; then
            echo "${input} is instrumental, skipping"
            continue
        fi

        output="$(set_lyric_file_name "${input}")"
        if [[ ! -f "${output}" ]]; then
            echo "processing ${input}"
            search="$(get_artist_album_title "${input}")"

            # try with syncedlyrics first
            ${dry} syncedlyrics \
                --synced-only \
                --output "${output}" \
                "${search}"

            if ! ${void} test -f "${output}"; then
                for f in "${TMPDIR}"/*; do
                    if [[ -f "${f}" ]]; then
                        echo "tempdir ${TMPDIR} is not empty!"
                        echo "aborting operation"
                        return 1
                    fi
                done

                # try with librelyrics-spotify next
                if ! spotifyUrl="$(${dry} get_spotify_url "${search}")"; then
                    ret=1
                    continue
                fi

                if ! ${dry} librelyrics \
                    --directory "${TMPDIR}" \
                    "${spotifyUrl}"; then
                    ret=1
                    continue
                fi

                if ! ${dry} mv "${TMPDIR}"/*.lrc "${output}"; then
                    ret=1
                    continue
                fi
            fi

            if ! ${void} test -f "${output}"; then
                echo "failed to get lyrics for ${input}"
                ret=1
                continue
            fi
        fi
    done
}

check_required_utils || exit 1
set_default_options || exit 1
process_options "$@" || exit 1
determine_inputs || exit 1
create_tmp_dir || exit 1
process_inputs || exit 1

exit 0
