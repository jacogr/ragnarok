#!/bin/sh
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# Select only the explicitly bundled issue215 profile; exec preserves native signal/exit ownership.
set -eu
if [ "${JAM_FUZZ+x}" != x ]; then
    echo 'JAM_FUZZ is required' >&2
    exit 2
fi
: "${JAM_FUZZ_SPEC:?JAM_FUZZ_SPEC is required}"
: "${JAM_FUZZ_DATA_PATH:?JAM_FUZZ_DATA_PATH is required}"
: "${JAM_FUZZ_SOCK_PATH:?JAM_FUZZ_SOCK_PATH is required}"
if [ "$JAM_FUZZ_SPEC" != fuzz ]; then
    echo 'This dedicated image requires JAM_FUZZ_SPEC=fuzz' >&2
    exit 2
fi
if [ "$#" -ne 0 ]; then
    echo 'The dedicated fuzz image accepts environment configuration only' >&2
    exit 2
fi
# Upstream creates shared runtime directories with0777; tighten only the explicit runtime-owned directories.
umask 077
mkdir -p "$JAM_FUZZ_DATA_PATH" "$(dirname "$JAM_FUZZ_SOCK_PATH")"
for directory in "$JAM_FUZZ_DATA_PATH" "$(dirname "$JAM_FUZZ_SOCK_PATH")"; do
    # Both supported /bin/sh implementations provide -O; an unrelated owner's path grants no authority.
    if [ ! -O "$directory" ]; then
        echo 'Fuzz runtime directories must belong to the runtime user' >&2
        exit 2
    fi
    chmod 700 "$directory"
done
exec "${RAGNAROK_FUZZ_BINARY:-/usr/local/bin/ragnarok}" serve-fuzz-preset \
    "${RAGNAROK_FUZZ_CONFIG_DIR:-/usr/share/ragnarok/fuzz}/jam-fuzz-policy.conf" \
    1000 4194304
