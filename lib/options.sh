#!/usr/bin/env bash

# many functions are invoked via variables
# shellcheck disable=SC2329

usage() {
    echo "${PROGNAME} [options]

OPTIONS:
  -d, --dir       process files in directory
  -r, --recurse   recursively process directory
  -f, --file      process one file
  -e, --embed     embed lyrics directly into the song file
  -n, --dry-run   do not add synced lyrics,
                  just show the files that would be processed
  -i, --ignore    ignore errors, and continue attempting to find lyrics
                  even in the case of errors
  -h, --help      show this output
  --debug         extra information useful for debugging
  --eval          output bash functions that can be directly processed
                  by eval for use with testing this script."
    exit "${EXIT_CODE:-1}"
}

set_default_options() {
    DIR=${DIR:-}
    FILE=${FILE:-}
    RECURSE=${RECURSE:-false}
    DRY_RUN=${DRY_RUN:-false}
    IGNORE=${IGNORE:-false}
    EMBED=${EMBED:-false}
    DEBUG=${DEBUG:-false}

    # cache
    CACHE_HOME="${XDG_CACHE_HOME:-"${HOME}/.cache"}"
    CACHE_DIR="${CACHE_HOME}/add-synced-lyrics"
    if [[ ! -d "${CACHE_DIR}" ]]; then
        mkdir "${CACHE_DIR}" || return 1
    fi

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
        -e | --embed)
            readonly EMBED=true
            shift 1
            ;;
        -f | --file)
            if [[ ! -f "${value}" ]]; then
                echo "file ${value} does not exist"
                usage
            fi
            readonly FILE="${value}"
            shift 2
            ;;
        --debug)
            readonly DEBUG=true
            shift 1
            ;;
        --eval)
            output_eval_functions
            exit 0
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
    local pattern="${DIR}/*"
    shopt -s nullglob globstar || return 1

    [[ "${RECURSE}" == true ]] && pattern="${DIR}/**/*"
    mapfile -t unsortedInputs < <(printf '%s\n' ${pattern})

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
