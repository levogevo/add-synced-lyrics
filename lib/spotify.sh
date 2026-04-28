#!/usr/bin/env bash

# many functions are invoked via variables
# shellcheck disable=SC2329

get_spotify_url() {
    local isrc="$1"
    if [[ -z "${isrc}" ]]; then
        echo_fail "missing isrc"
        return 1
    fi

    local search="isrc:${isrc}"
    local response
    response="$(
        cache_command \
            spotify \
            search \
            --track \
            "${search}" \
            --limit 1 \
            --raw
    )" || return 1

    local tags=(
        spotifyISRC
        spotifyURL
    )
    # unset tag values
    for tag in "${tags[@]}"; do
        declare "${tag}="
    done

    local jqFilter='.items[] | "\(.external_ids.isrc)|\(.external_urls.spotify)"'
    local jqOutput="$(jq -r "${jqFilter}" <<<"${response}")"

    # compare tags versus the reference for each line
    local foundMatching=false
    while read -r line; do
        IFS='|' read -r "${tags[@]}" <<<"${line}"

        for tag in "${tags[@]}"; do
            declare -n spotifyTagValue="${tag}"
            debug echo_debug "${tag}=${spotifyTagValue}"
        done

        # shellcheck disable=SC2154
        if [[ "${spotifyISRC,,}" == "${isrc,,}" ]]; then
            foundMatching=true
            break
        fi
    done <<<"${jqOutput}"

    if [[ "${foundMatching}" == false ]]; then
        debug echo_fail "could not find matching spotify track for ${isrc}"
        return 1
    fi

    # shellcheck disable=SC2154
    echo "${spotifyURL}"
    return 0
}

download_with_spotify() {
    local isrc="$1"
    local output="$2"
    download_with_librelyrics \
        "${isrc}" \
        "${output}" \
        spotify
}
