#!/usr/bin/env bash

# "${test}" invokes test_ functions
# shellcheck disable=SC2329

set -u

readonly THIS_DIR="$(dirname "$(readlink -f "$0")")"
readonly TEST_DIR="${THIS_DIR}/test-dir"
readonly TEST_FILE_1="${TEST_DIR}/03 - Back Burner.opus"
readonly TEST_FILE_2="${TEST_DIR}/subdir/05 - Composure.opus"
readonly PROG="${THIS_DIR}/add-synced-lyrics.sh"

test_bad_input() {
    # incomplete args
    "${PROG}" && return 1
    "${PROG}" --file && return 1
    "${PROG}" --dir && return 1
    "${PROG}" --recurse && return 1

    # incorrect mixmatch
    "${PROG}" --file "${PROG}" --recurse && return 1
    "${PROG}" --file "${PROG}" --dir "${THIS_DIR}" && return 1
    "${PROG}" --file "${PROG}" --dir "${THIS_DIR}" --recurse && return 1

    return 0
}

test_determine_inputs() (
    eval "$("${PROG}" --eval)"
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
        <(printf '%s\n' "${fdInputs[@]}") || return 1

    echo "comparing fd vs find"
    diff \
        <(printf '%s\n' "${fdInputs[@]}") \
        <(printf '%s\n' "${findInputs[@]}") || return 1

    return 0
)

test_determine_inputs_recurse() {
    RECURSE=true test_determine_inputs
}

test_file_dry() {
    "${PROG}" --file "${TEST_FILE_1}" --dry-run || return 1

    return 0
}

test_directory_dry() {
    "${PROG}" --dir "${TEST_DIR}" --dry-run || return 1

    return 0
}

test_directory_recurse_dry() {
    "${PROG}" --dir "${TEST_DIR}" --recurse --dry-run || return 1

    return 0
}

test_file() {
    "${PROG}" --file "${TEST_FILE_1}" || return 1
    test -f "${TEST_FILE_1//.opus/.lrc}"
}

test_directory_recurse() {
    "${PROG}" --dir "${TEST_DIR}" --recurse || return 1
    test -f "${TEST_FILE_2//.opus/.lrc}"
}

setup_test_data() {
    test -d "${TEST_DIR}" && rm -rf "${TEST_DIR}"
    mkdir -p "${TEST_DIR}/subdir" || return 1
    ffmpegCmd=(
        ffmpeg
        -hide_banner
        -f lavfi
        -i anullsrc=channel_layout=stereo:sample_rate=48000
        -c:a libopus
        -t 5
        -metadata ALBUM="Messengers"
        -metadata ARTIST="August Burns Red"
    )
    "${ffmpegCmd[@]}" \
        -metadata TITLE="Back Burner" \
        "${TEST_FILE_1}" || return 1
    "${ffmpegCmd[@]}" \
        -metadata TITLE="Composure" \
        "${TEST_FILE_2}" || return 1
}

TESTS=(
    setup_test_data
    test_determine_inputs
    test_determine_inputs_recurse
    test_bad_input
    test_directory_dry
    test_directory_recurse_dry
    test_file_dry
    test_file
    test_directory_recurse
)

# make sure no test is accidentally missed
while read -r line; do
    IFS=' ' read -r _ _ test <<<"${line}"
    if [[ "${TESTS[*]}" != *"${test}"* ]]; then
        echo "missing ${test} from \$TESTS"
        exit 1
    fi
done <<<"$(declare -F)"

for test in "${TESTS[@]}"; do
    if ! testOutput="$(
        (
            set -x
            "${test}"
        ) 2>&1
    )"; then
        echo "!! ${test} failed !!"
        echo "${testOutput}"
        exit 1
    else
        echo "${test} passed"
    fi
done

exit 0
