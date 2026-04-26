#!/usr/bin/env bash

# "${test}" invokes test_ functions
# shellcheck disable=SC2329

set -u

readonly THIS_DIR="$(dirname "$(readlink -f "$0")")"
readonly TEST_DIR="${THIS_DIR}/test-dir"
# lyrics exist for this song
readonly GOOD_SONG="${TEST_DIR}/back burner.opus"
readonly GOOD_LYRICS="${GOOD_SONG//.opus/.lrc}"
# lyrics do not exist for this song
readonly BAD_SONG="${TEST_DIR}/subdir/avalanche.opus"
readonly BAD_LYRICS="${BAD_SONG//.opus/.lrc}"
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
    "${PROG}" --file "${GOOD_SONG}" --dry-run
}

test_directory_dry() {
    "${PROG}" --dir "${TEST_DIR}" --dry-run
}

test_directory_recurse_dry() {
    "${PROG}" --dir "${TEST_DIR}" --recurse --dry-run
}

test_good_file() {
    "${PROG}" --file "${GOOD_SONG}" || return 1
    test -f "${GOOD_LYRICS}"
}

test_bad_file() {
    "${PROG}" --file "${BAD_SONG}" && return 1
    ! test -f "${BAD_LYRICS}"
}

test_directory_recurse() {
    setup_test_data || return 1
    # this test should fail since it includes the bad file
    "${PROG}" --dir "${TEST_DIR}" --recurse && return 1

    return 0
}

test_directory_recurse_ignore() {
    setup_test_data || return 1
    "${PROG}" --dir "${TEST_DIR}" --recurse --ignore && return 1
    test -f "${GOOD_LYRICS}" || return 1
    test -f "${BAD_LYRICS}" && return 1

    return 0
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
    )
    "${ffmpegCmd[@]}" \
        -metadata ISRC=USTN10700139 \
        "${GOOD_SONG}" || return 1
    "${ffmpegCmd[@]}" \
        -metadata ISRC=US5261822978 \
        "${BAD_SONG}" || return 1
}

TESTS=(
    setup_test_data
    test_determine_inputs
    test_determine_inputs_recurse
    test_bad_input
    test_directory_dry
    test_directory_recurse_dry
    test_file_dry
    test_good_file
    test_bad_file
    test_directory_recurse
    test_directory_recurse_ignore
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
        echo
        echo "!! ${test} failed !!"
        echo "${testOutput}"
        exit 1
    else
        echo "${test} passed"
    fi
done

exit 0
