#!/usr/bin/env bash

# many functions are invoked via variables
# shellcheck disable=SC2329

get_deezer_isrc_response() {
    local isrc="$1"
    if [[ -z "${isrc}" ]]; then
        error "missing isrc"
        return 1
    fi

    cache_command \
        curl \
        --silent \
        --retry 3 \
        "https://api.deezer.com/track/isrc:${isrc}"
}

get_deezer_url() {
    local isrc="$1"
    if [[ -z "${isrc}" ]]; then
        error "missing isrc"
        return 1
    fi

    local deezerResponse=''
    deezerResponse="$(get_deezer_isrc_response "${isrc}")" || return 1

    local jqResult=''
    jqResult="$(jq -r .link <<<"${deezerResponse}")"

    if ! jq_result_valid "${jqResult}"; then
        error "could not get link from deezer for ${isrc}"
        return 1
    fi

    echo "${jqResult}"
}

download_with_deezer() {
    local isrc="$1"
    local output="$2"
    download_with_librelyrics \
        "${isrc}" \
        "${output}" \
        deezer
}
