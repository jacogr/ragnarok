#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Apply upstream's AVX2 feature only to the generated simulator compilation unit.

The pinned compiler and all other units keep their original flags. Each invocation is
recorded under the build folder; only the maintained benchmark builder installs this wrapper.
"""
import fcntl
import json
import os
from pathlib import Path
import platform
import subprocess
import sys


def main():
    """Identify the primitive header in actual C input, log flags, then invoke real Clang."""
    compiler = Path(os.environ['FAITHFUL_REAL_CLANG']).resolve(strict=True)
    arguments = sys.argv[1:]
    sources = [Path(value) for value in arguments if value.endswith('.c') and Path(value).is_file()]
    simulator = [str(path) for path in sources if '#include "simulator_simd.h"' in path.read_text()]
    selected = platform.machine().lower() in ('x86_64', 'amd64') and bool(simulator)
    if selected:
        # Nimony compiles one source at a time; refuse to widen a mixed compilation command.
        assert '-c' in arguments and len(sources) == 1
        arguments = ['-mavx2', *arguments]
    record = dict(compiler=str(compiler), arguments=arguments, simulator=simulator, avx2=selected)
    with Path(os.environ['FAITHFUL_CLANG_LOG']).open('a') as output:
        # Independent compiler workers append complete records under one advisory lock.
        fcntl.flock(output, fcntl.LOCK_EX)
        output.write(json.dumps(record) + '\n')
    return subprocess.call([str(compiler), *arguments])


if __name__ == '__main__':
    sys.exit(main())
