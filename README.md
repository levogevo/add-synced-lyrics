# add-synced-lyrics
A script that automates adding lyrics to your songs.
```
add-synced-lyrics.sh [options]

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
                  by eval for use with testing this script.
```

# Requirements
- CLI tools:
    - coreutils: `mktemp cat sort base64 readlink`
    - `ffmpeg ffprobe` 
    - `jq`
    - `node` (any version)
    - [`librelyrics`](https://github.com/libre-lyrics/librelyrics):
        - uses the [deezer](https://github.com/libre-lyrics/librelyrics-deezer) and [spotify](https://github.com/libre-lyrics/librelyrics-spotify) plugins
    - [`spotify`](https://github.com/ledesmablt/spotify-cli) most easily installed with `uv tool install --python 3.8 spotify-cli`
- Music that has the appropriate ISRC tag.

## Features
- Uses the ISRC tag to search for synced lyrics across the download providers: lrclib, spotify, and deezer (in that order).
- Caches all networked-calls to the download providers.
- Supports separate (dedicated .lrc file) or adding the lyrics directly to the song file with the LYRICS tag.