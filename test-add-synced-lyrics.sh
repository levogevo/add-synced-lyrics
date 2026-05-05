#!/usr/bin/env bash

# "${test}" invokes test_ functions
# shellcheck disable=SC2329

set -eu

bash_basename() {
    local tmp
    path="${1:-}"
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

PROGPATH="$(readlink -f "$0")" || exit 1
PROGDIR="$(bash_dirname "${PROGPATH}")" || exit 1
PROGNAME="$(bash_basename "${PROGPATH}")" || exit 1
readonly PROGPATH PROGDIR PROGNAME || exit 1

# to normalize paths
cd "${PROGDIR}"

readonly TEST_DIR="test-dir"
# lyrics exist for this song
readonly GOOD_SONG="${TEST_DIR}/the cold sun.opus"
readonly GOOD_LYRICS="${GOOD_SONG//.opus/.lrc}"
readonly GOOD_ISRC='TCJPF1733509'
# lyrics do not exist for this song
readonly BAD_SONG="${TEST_DIR}/subdir/avalanche.opus"
readonly BAD_LYRICS="${BAD_SONG//.opus/.lrc}"
readonly BAD_ISRC='US5261822978'
# program to test
readonly PROG="add-synced-lyrics.sh"
# coverage
readonly COVERAGE_DIR="coverage"
readonly COVERAGE_FILE="${COVERAGE_DIR}/coverage"

run_test_cmd() {
    local expectedRetval="${1:-}"

    shift 1
    local cmd=("$@")

    # check for empty args for setup tests to run
    [[ -z "${expectedRetval}" && -z "${cmd[*]}" ]] && return

    # check a value was given
    if [[ ! "${expectedRetval}" =~ [0-9] ]]; then
        echo "expectedRetval not given"
        exit 1
    fi

    local output
    output="$("${cmd[@]}" 2>&1)"
    local actualRetval=$?

    declare -g CMD_OUTPUT="${output}"
    declare -g CMD_RETURN="${actualRetval}"
    if [[ ${expectedRetval} -ne ${actualRetval} ]]; then
        echo "${expectedRetval} != ${actualRetval} for ${cmd[*]}"
        return 1
    else
        return 0
    fi

}

test_help_option() {
    add-synced-lyrics --help
}

test_bad_input() {
    # incomplete args
    run_test_cmd \
        1 \
        add-synced-lyrics
    run_test_cmd \
        1 \
        add-synced-lyrics --file
    run_test_cmd \
        1 \
        add-synced-lyrics --dir
    run_test_cmd \
        1 \
        add-synced-lyrics --recurse

    # incorrect mixmatch
    run_test_cmd \
        1 \
        add-synced-lyrics --file "${PROGPATH}" --recurse
    run_test_cmd \
        1 \
        add-synced-lyrics --file "${PROGPATH}" --dir "${PROGDIR}"
    run_test_cmd \
        1 \
        add-synced-lyrics --file "${PROGPATH}" --dir "${PROGDIR}" --recurse

    # non-existent flag
    run_test_cmd \
        1 \
        add-synced-lyrics --this-flag-does-not-exist

    return 0
}

test_determine_inputs() (
    eval "$(add-synced-lyrics --eval)"
    set_default_options

    DIR="${TEST_DIR}"

    _determine_inputs_bash
    bashInputs=("${INPUTS[@]}")

    _determine_inputs_fd
    fdInputs=("${INPUTS[@]}")

    _determine_inputs_find
    findInputs=("${INPUTS[@]}")

    echo "comparing bash vs fd"
    diff \
        <(printf '%s\n' "${bashInputs[@]}") \
        <(printf '%s\n' "${fdInputs[@]}")

    echo "comparing fd vs find"
    diff \
        <(printf '%s\n' "${fdInputs[@]}") \
        <(printf '%s\n' "${findInputs[@]}")

    return 0
)

test_determine_inputs_recurse() {
    RECURSE=true test_determine_inputs
}

test_determine_inputs_bash() {
    # TEST_ADD_BIN guaranteed to be single word
    # shellcheck disable=SC2206
    local utils=(
        mktemp
        sort
        base64
        cat
        ffprobe
        jq
        librelyrics
        spotify
        docker
        node
        readlink
        bash
        ${TEST_ADD_BIN:-}
    )

    for util in "${utils[@]}"; do
        test -f "${TEST_DIR}/${util}" && rm "${TEST_DIR}/${util}"
        ln -s "$(command -v "${util}")" "${TEST_DIR}/${util}"
    done

    PATH="${TEST_DIR}" \
        add-synced-lyrics \
        --dir "${TEST_DIR}" \
        --dry-run "$@"
}

test_determine_inputs_bash_recurse() {
    test_determine_inputs_bash --recurse
}

test_determine_inputs_find() {
    TEST_ADD_BIN='find' test_determine_inputs_bash
}

test_determine_inputs_find_recurse() {
    TEST_ADD_BIN='find' test_determine_inputs_bash_recurse
}

test_file_dry() {
    setup_test_data
    add-synced-lyrics --file "${GOOD_SONG}" --dry-run
}

test_directory_dry() {
    setup_test_data
    add-synced-lyrics --dir "${TEST_DIR}" --dry-run
}

test_directory_recurse_dry() {
    setup_test_data
    add-synced-lyrics --dir "${TEST_DIR}" --recurse --dry-run
}

test_good_file() {
    setup_test_data
    add-synced-lyrics --file "${GOOD_SONG}" --debug
    test -f "${GOOD_LYRICS}"
}

test_good_file_embed() {
    test_good_file
    # rm "${GOOD_LYRICS}"
    add-synced-lyrics --file "${GOOD_SONG}" --embed
    run_test_cmd \
        1 \
        test -f "${GOOD_LYRICS}"

    # do it again to test that embedded is picked up and valid
    run_test_cmd \
        0 \
        add-synced-lyrics --file "${GOOD_SONG}" --embed
    [[ "${CMD_OUTPUT}" == *'already has lyrics, skipping'* ]]
}

test_bad_file() {
    setup_test_data
    run_test_cmd \
        1 \
        add-synced-lyrics \
        --file "${BAD_SONG}" \
        --debug
    run_test_cmd \
        1 \
        test -f "${BAD_LYRICS}"
}

test_directory_recurse() {
    setup_test_data
    # this test should fail since it includes the bad file
    run_test_cmd \
        1 \
        add-synced-lyrics --dir "${TEST_DIR}" --recurse
}

test_directory_recurse_ignore() {
    setup_test_data
    run_test_cmd \
        1 \
        add-synced-lyrics --dir "${TEST_DIR}" --recurse --ignore
    test -f "${GOOD_LYRICS}"
    run_test_cmd \
        1 \
        test -f "${BAD_LYRICS}"

    return 0
}

test_not_music_file() {
    local notMusicFile="${TEST_DIR}/dummy.txt"
    test -f "${notMusicFile}" || touch "${notMusicFile}"

    run_test_cmd \
        1 \
        add-synced-lyrics --file "${notMusicFile}"

    [[ "${CMD_OUTPUT}" == *'is not a music file'* ]]
}

test_missing_utils() {
    test -d "${TEST_DIR}" || setup_test_data

    for bin in bash readlink; do
        test -f "${TEST_DIR}/${bin}" && rm "${TEST_DIR}/${bin}"
        ln -s "$(command -v ${bin})" "${TEST_DIR}/${bin}"
    done

    # chmod +x "${TEST_DIR}/bash"
    PATH="${TEST_DIR}" run_test_cmd \
        1 \
        add-synced-lyrics

    [[ "${CMD_OUTPUT}" == *'missing node'* ]]
}

setup_test_data() {
    test -d "${TEST_DIR}" && rm -rf "${TEST_DIR}"
    mkdir -p "${TEST_DIR}/subdir"
    ffmpegCmd=(
        ffmpeg
        -hide_banner
        -f lavfi
        -i anullsrc=channel_layout=stereo:sample_rate=48000
        -c:a libopus
        -t 5
    )
    "${ffmpegCmd[@]}" \
        -metadata ISRC=${GOOD_ISRC} \
        "${GOOD_SONG}"
    "${ffmpegCmd[@]}" \
        -metadata ISRC=${BAD_ISRC} \
        "${BAD_SONG}"
}

TESTS=(
    test_help_option
    test_determine_inputs
    test_determine_inputs_recurse
    test_determine_inputs_bash
    test_determine_inputs_bash_recurse
    test_determine_inputs_find
    test_determine_inputs_find_recurse
    test_not_music_file
    test_bad_input
    test_directory_dry
    test_directory_recurse_dry
    test_file_dry
    test_good_file
    test_good_file_embed
    test_bad_file
    test_directory_recurse
    test_directory_recurse_ignore
    test_missing_utils
)

# make sure no test is accidentally missed
while read -r line; do
    IFS=' ' read -r _ _ function <<<"${line}"
    if [[ "${TESTS[*]}" != *"${function}"* &&
        "${function}" == 'test_'* ]]; then
        echo "missing ${function} from \$TESTS"
        exit 1
    fi
done <<<"$(declare -F)"

# generate the coverage function for use with eval
# to not redefine constants
gen_coverage_function() {
    # shellcheck disable=SC2016
    echo 'coverage_function () {
    local source line
    source="${BASH_SOURCE[1]}" '"
    source=\"\${source//'${PROGDIR}/'/}\" "'
    line="${BASH_LINENO[0]}"
    if [[ "${source}" == *".sh" &&
        "${source}" != *"'"${PROGNAME}"'" ]]; then
        {
            # minus one because shebang is not included
            echo "${source} $((line - 1))"' ">>${COVERAGE_FILE}" '
        }
    fi
}'
}

setup_coverage() {
    test -d "${COVERAGE_DIR}" && rm -rf "${COVERAGE_DIR}"
    mkdir "${COVERAGE_DIR}"
    : >"${COVERAGE_FILE}"
    eval "$(gen_coverage_function)"
}

add-synced-lyrics() {
    export -f coverage_function
    PS4='$(coverage_function)' bash -x "${PROG}" "$@"
}

line_is_covered() {
    local line="$1"
    local lineNum="$2"

    # empty lines are covered
    [[ "${#line}" -eq 0 ]] && return 0

    # commented lines are covered
    read -r firstToken _ <<<"${line}"
    [[ "${firstToken}" == '#'* ]] && return 0

    # line is explicitly in coverage file is covered
    grep -q "${coverageFile} ${lineNum}" "${COVERAGE_FILE}" && return 0

    return 1
}

analyze_coverage() {
    sort -u "${COVERAGE_FILE}" >"${COVERAGE_FILE}.tmp"
    mv "${COVERAGE_FILE}.tmp" "${COVERAGE_FILE}"

    mapfile -t coverageFiles < <(cut -d ' ' -f1 "${COVERAGE_FILE}" | sort -u)

    local RED='\e[0;31m' GREEN='\e[0;32m' NC='\e[0m'

    local fileDir fileLen color line linesCovered
    for coverageFile in "${coverageFiles[@]}"; do
        fileDir="${COVERAGE_DIR}/$(bash_dirname "${coverageFile}")"
        test -d "${fileDir}" || mkdir -p "${fileDir}"
        mapfile -t fileContents <"${coverageFile}"
        fileLen="${#fileContents[@]}"
        linesCovered=0
        {
            for ((line = 0; line < fileLen; line++)); do
                if line_is_covered "${fileContents[${line}]}" "${line}"; then
                    color="${GREEN}"
                    linesCovered=$((linesCovered + 1))
                else
                    color="${RED}"
                fi
                printf '%b%s%b\n' \
                    "${color}" \
                    "${fileContents[${line}]}" \
                    "${NC}"
            done
        } >"${COVERAGE_DIR}/${coverageFile}"
        echo "${coverageFile} lines covered: $((linesCovered * 100 / fileLen))%"
    done
}

if [[ $# -eq 0 ]]; then
    setup_coverage

    for test in "${TESTS[@]}"; do
        if ! testOutput="$(
            (
                set -x
                "${test}"
            ) 2>&1
        )"; then
            echo
            echo "!! ${test} failed !!"
            echo "${testOutput}"
            exit 1
        else
            echo "${test} passed"
        fi
    done

    echo
    analyze_coverage
else
    setup_coverage
    "$@"
    exit $?
fi
