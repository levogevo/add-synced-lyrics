#!/usr/bin/env bash

FLARESOLVERR_PORT="${FLARESOLVERR_PORT:-8191}"
validate_flaresolverr() {
    local checkMsg="$(curl --connect-timeout 1 -s localhost:${FLARESOLVERR_PORT} | jq -r .msg)"

    if [[ "${checkMsg}" == 'FlareSolverr is ready!' ]]; then
        return 0
    fi

    debug echo_debug 'flaresolverr not running, attempting to start with docker'
    local containerName='flaresolverr'
    docker inspect ${containerName} &>/dev/null && docker container rm ${containerName}

    echo_if_fail docker run -d \
        --name=flaresolverr \
        -p ${FLARESOLVERR_PORT}:${FLARESOLVERR_PORT} \
        -e LOG_LEVEL=info \
        --restart unless-stopped \
        ghcr.io/flaresolverr/flaresolverr:latest
    local startupRet=$?

    [[ ${startupRet} -ne 0 ]] && return ${startupRet}

    #  wait a little to make sure the container is ready
    sleep 3
    return ${startupRet}
}

get_lyricsify_response() {
    local isrc="$1"

    validate_flaresolverr || return 1

    local deezerResponse=''
    deezerResponse="$(get_deezer_isrc_response "${isrc}")" || return 1

    # lyricsify uses artist - song name for URL
    # so obtain data from deezer
    local deezerMetadata=(
        "track .title"
        "artist .artist.name"
    )
    for data in "${deezerMetadata[@]}"; do
        IFS=' ' read -r env jqFilter <<<"${data}"
        jqResult="$(jq -r "${jqFilter}" <<<"${deezerResponse}")"
        if ! jq_result_valid "${jqResult}"; then
            echo_fail "could not determine lyricsify ${env} for ${isrc}"
            return 1
        fi
        declare "${env}=${jqResult}"
        debug echo_debug "${env}=${jqResult}"
    done

    # variables assigned above
    # shellcheck disable=SC2154
    artist="${artist,,}"
    track="${track,,}"
    artist="${artist// /-}"
    track="${track// /-}"
    local lyricsifyUrl="https://www.lyricsify.com/lyrics/${artist}/${track}"
    debug echo_debug "using ${lyricsifyUrl}"

    local jsonPayload
    jsonPayload="$(
        jq -n \
            --arg cmd 'request.get' \
            --arg url "${lyricsifyUrl}" \
            --argjson timeout 60000 \
            '{cmd: $cmd, url: $url, maxTimeout: $timeout}'
    )" || return 1

    cache_command \
        curl \
        -L \
        -X POST \
        "http://localhost:${FLARESOLVERR_PORT}/v1" \
        -H 'Content-Type: application/json' \
        --data-raw "${jsonPayload}"
}

process_lyricsify_response() {
    local response="$1"

    local responseMessage="$(jq -r '.message' <<<"${response}")"
    if [[ "${responseMessage}" != 'Challenge solved!' ]]; then
        debug echo_fail "could not solve challenge"
        return 1
    fi

    local solution="$(jq -r '.solution.response' <<<"${response}")"

    local variableSearch='lrcText'
    while read -r line; do
        if [[ "${line}" == *"var ${variableSearch} = "* ]]; then
            node -e "${line} ; console.log(${variableSearch})"
            return $?
        fi
    done <<<"${solution}"

    return 1
}

DOWNLOAD_FUNCTIONS+=(download_with_lyricsify)
download_with_lyricsify() {
    local isrc="$1"
    local output="$2"

    local lyricsifyResponse syncedLyrics
    lyricsifyResponse="$(get_lyricsify_response "${isrc}")" || return 1
    syncedLyrics="$(process_lyricsify_response "${lyricsifyResponse}")" || return 1

    echo "${syncedLyrics}" >"${output}"
}
