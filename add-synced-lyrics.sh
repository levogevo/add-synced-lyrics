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

    local numInputs="${#INPUTS[@]}"
    for ((i = 0; i < numInputs; i++)); do
        if [[ ${IGNORE} == false && ${ret} -ne 0 ]]; then
            return 1
        fi

        local input="${INPUTS[${i}]}"
        echo_info "processing $((i + 1))/${numInputs}: ${input}"

        if [[ "${input,,}" == *'instrumental'* ||
            "${input,,}" == *'acoustic'* ]]; then
            echo_pass "${input} is instrumental, skipping"
            continue
        fi

        output=''
        output="$(set_lyric_file_name "${input}")"

        if validate_lrc "${output}"; then
            echo_pass "${input} already has lyrics, skipping"
            continue
        fi

        isrc=''
        if ! isrc="$(get_file_isrc "${input}")"; then
            ret=1
            continue
        fi

        local tmpOutput="${TMPDIR}/tmp.lrc"
        for func in "${downloadFuncs[@]}"; do
            # try to download
            if ! "${func}" "${isrc}" "${tmpOutput}"; then
                continue
            fi

            # validate
            if validate_lrc "${tmpOutput}"; then
                # passed download and validation, stop processing
                break
            fi
        done

        # skip processing since no files should be modified
        [[ ${DRY_RUN} == true ]] && continue

        if [[ -f "${tmpOutput}" ]]; then
            mv "${tmpOutput}" "${output}" &>/dev/null || return 1
            echo_pass "added lyrics for ${input}"
        else
            echo_fail "could not find lyrics for ${input}"
            ret=1
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
