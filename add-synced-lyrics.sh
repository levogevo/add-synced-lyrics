#!/usr/bin/env bash

# many functions are invoked via variables
# shellcheck disable=SC2329

set -u

bash_basename() {
    local tmp
    path="$1"
    suffix="${2:-''}"

    tmp=${path%"${path##*[!/]}"}
    tmp=${tmp##*/}
    tmp=${tmp%"${suffix/"$tmp"/}"}

    printf '%s\n' "${tmp:-/}"
}

bash_dirname() {
    # Usage: dirname "path"
    local tmp=${1:-.}

    [[ $tmp != *[!/]* ]] && {
        printf '/\n'
        return
    }

    tmp=${tmp%%"${tmp##*[!/]}"}

    [[ $tmp != */* ]] && {
        printf '.\n'
        return
    }

    tmp=${tmp%/*}
    tmp=${tmp%%"${tmp##*[!/]}"}

    printf '%s\n' "${tmp:-/}"
}

PROGPATH="$(readlink -f "$0")"
PROGDIR="$(bash_dirname "${PROGPATH}")"
PROGNAME="$(bash_basename "${PROGPATH}")"
# shellcheck disable=SC2034
readonly PROGPATH PROGDIR PROGNAME || exit 1

for lib in "${PROGDIR}/lib/"*; do
    # shellcheck disable=SC1090
    source "${lib}" || exit 1
done

process_inputs() {
    local isrc output ret=0
    local downloadFuncs=(
        download_with_lrclib
        download_with_spotify
        download_with_deezer
    )

    for input in "${INPUTS[@]}"; do
        if [[ ${IGNORE} == false && ${ret} -ne 0 ]]; then
            return 1
        fi

        if [[ "${input,,}" == *'instrumental'* ||
            "${input,,}" == *'acoustic'* ]]; then
            echo "${input} is instrumental, skipping"
            continue
        fi

        output=''
        output="$(set_lyric_file_name "${input}")"

        if [[ -f "${output}" ]]; then
            if is_valid_lrc "${output}"; then
                continue
            else
                rm "${output}" || return 1
            fi
        fi

        echo "processing ${input}"
        isrc=''
        if ! isrc="$(get_file_isrc "${input}")"; then
            ret=1
            continue
        fi

        local tmpOutput="${TMPDIR}/tmp.lrc"
        for func in "${downloadFuncs[@]}"; do
            "${func}" "${isrc}" "${tmpOutput}" && break
        done

        if [[ -f "${tmpOutput}" ]]; then
            if is_valid_lrc "${tmpOutput}"; then
                mv "${tmpOutput}" "${output}" &>/dev/null || return 1
            else
                rm "${tmpOutput}" || return 1
            fi
        fi

        if ! void test -f "${output}"; then
            echo "failed to get lyrics for ${input}"
            ret=1
            continue
        else
            void echo "added lyrics for ${input}"
        fi
    done

    return ${ret}
}

check_required_utils || exit 1
set_default_options || exit 1
process_options "$@" || exit 1
determine_inputs || exit 1
create_tmp_dir || exit 1
process_inputs || exit 1

exit 0
