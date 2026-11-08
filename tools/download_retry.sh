#!/bin/sh
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# Bootstrap package downloads before Python is installed, using the shared five-attempt policy.
# Keep these waits aligned with RETRY_DELAYS in toolchain_archives.py.
if [ "$#" -eq 0 ]; then
    printf 'Usage: download_retry.sh COMMAND [ARG ...]\n' >&2
    exit 2
fi
for delay in 0 5 15 45 90; do
    if [ "$delay" -ne 0 ]; then
        printf 'Download command failed; retrying in %ss\n' "$delay" >&2
        sleep "$delay" || exit "$?"
    fi
    "$@" && exit 0
    result=$?
done
exit "$result"
