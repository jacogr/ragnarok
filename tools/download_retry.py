#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Apply the shared download backoff to package-manager and source-fetch commands.

Only provisioning callers opt in. Compiler, build and test failures retain their normal behavior.
"""
import subprocess
import sys
import time
from toolchain_archives import RETRY_DELAYS


def run(arguments, before_retry=None, **options):
    """Retry an idempotent acquisition command, preserving output and final failure status."""
    options['check'] = True
    for attempt in range(len(RETRY_DELAYS)+1):
        try:
            return subprocess.run([str(argument) for argument in arguments], **options)
        except (subprocess.CalledProcessError, subprocess.TimeoutExpired):
            if attempt == len(RETRY_DELAYS):
                raise # A failed final acquisition cannot become a successful setup step.
            if before_retry is not None:
                # Artifact callers discard partial extraction before repeating the acquisition.
                before_retry()
            delay = RETRY_DELAYS[attempt]
            print(f'Download command failed (attempt {attempt+1}/{len(RETRY_DELAYS)+1}); '
                  f'retrying in {delay}s', file=sys.stderr, flush=True)
            time.sleep(delay)


if __name__ == '__main__':
    if not sys.argv[1:]:
        raise SystemExit('Usage: download_retry.py COMMAND [ARG ...]')
    try:
        run(sys.argv[1:])
    except subprocess.CalledProcessError as error:
        raise SystemExit(error.returncode if error.returncode >= 0 else 128-error.returncode)
