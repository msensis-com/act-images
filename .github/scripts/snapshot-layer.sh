#!/usr/bin/env bash
# Snapshot one layer of the runner's filesystem: snapshot-layer.sh NAME TAR_ARGS...
# Streams `tar -c TAR_ARGS` through ghcr-stream.mjs into the registry and, only when both tar and
# the upload succeeded, appends the layer descriptor to $RUNNER_TEMP/snapshot/layers.jsonl.
set -uo pipefail

name="$1"
shift
dir="${RUNNER_TEMP:?}/snapshot"
mkdir -p "$dir"
out="$dir/layer-$name.json"
uploader="$(dirname "$0")/ghcr-stream.mjs"

for attempt in 1 2; do
    rm -f "$out"
    sudo tar --ignore-failed-read -C / -c "$@" | node "$uploader" layer "$name" "$out"
    rc=("${PIPESTATUS[@]}")
    # GNU tar exits 1 when files changed while being read (normal on a live system), 2 on fatal errors
    if (( rc[0] <= 1 && rc[1] == 0 )) && [[ -s "$out" ]]; then
        cat "$out" >> "$dir/layers.jsonl"
        exit 0
    fi
    echo "::warning::layer $name attempt $attempt failed (tar=${rc[0]} upload=${rc[1]})"
done
echo "::error::layer $name failed"
exit 1
