#!/usr/bin/env bash

# many functions are invoked via variables
# shellcheck disable=SC2329

get_lrclib_api_response() {
    local isrc="$1"
    local deezerResponse=''
    deezerResponse="$(get_deezer_isrc_response "${isrc}")" || return 1

    # get metadata from deezer
    local deezerMetadata=(
        "track .title"
        "artist .artist.name"
        "album .album.title"
        "duration .duration"
    )
    for data in "${deezerMetadata[@]}"; do
        IFS=' ' read -r env jqFilter <<<"${data}"
        jqResult="$(jq -r "${jqFilter}" <<<"${deezerResponse}")"
        if ! jq_result_valid "${jqResult}"; then
            echo_fail "could not determine lrclib ${env} for ${isrc}"
            return 1
        fi
        declare "${env}=${jqResult}"
        debug echo_debug "${env}=${jqResult}"
    done

    # variables assigned above
    # shellcheck disable=SC2154
    cache_command \
        curl \
        "https://lrclib.net/api/get" \
        --silent \
        --get \
        --data-urlencode "track_name=${track}" \
        --data-urlencode "artist_name=${artist}" \
        --data-urlencode "album_name=${album}" \
        --data-urlencode "duration=${duration}"
}

download_with_lrclib() {
    local isrc="$1"
    local output="$2"

    # get lrclib ID
    local lrclibResponse syncedLyrics
    lrclibResponse="$(get_lrclib_api_response "${isrc}")"
    syncedLyrics="$(jq -r .syncedLyrics <<<"${lrclibResponse}")"
    if ! jq_result_valid "${syncedLyrics}"; then
        debug echo_fail "could not find lyrics for ${isrc}"
        return 1
    fi

    echo "${syncedLyrics}" >"${output}"
}
