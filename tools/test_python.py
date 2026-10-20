#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run Python reference, tooling and provenance unittests once as an independent verification group.

Exposes python_tests and a CLI that discovers Python tests once and writes fresh results.
"""
import json
from pathlib import Path
import re
import sys
import subprocess
import time
from native_checks import NativeChecks, ROOT, announce

BUILD = ROOT/'build/tests/python'


# Allow five minutes for the full Python suite on busy CI hosts; native command limits stay unchanged.
def python_tests():
    arguments = [sys.executable, '-m', 'unittest', 'discover', '-v', '-s', 'tests', '-p', 'test_*.py']
    started = time.monotonic()
    try:
        # Per-test progress identifies the stalled reference if discovery hits the unchanged deadline.
        return NativeChecks(BUILD).command(arguments, 'python-tests', timeout=300)
    except subprocess.TimeoutExpired as error:
        # subprocess.run has killed/reaped discovery; retain its partial output and a failed report.
        fragments = [error.stdout or '', error.stderr or '']
        output = ''.join(part.decode(errors='replace') if isinstance(part, bytes) else part
                         for part in fragments)
        output += '\n'+str(error)+'\n'
        log = BUILD/'python-tests.log'
        log.write_text(output)
        return dict(command=arguments, exit_code=124,
                    elapsed_seconds=round(time.monotonic()-started, 6),
                    log=str(log), output=output)



# A fresh failed or empty discovery cannot reuse an earlier green report.
def main():
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True)
    result = python_tests()
    output = result.pop('output')
    observed = re.search(r'Ran (\d+) tests? in ', output)
    skipped = re.search(r'skipped=(\d+)', output)
    total = int(observed.group(1)) if observed else 0
    passed = result['exit_code'] == 0 and total > 0
    report = dict(status='checks-passed' if passed else 'failed', tests=total,
                  skipped=int(skipped.group(1)) if skipped else 0, check=result)
    (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    announce('Python verification', passed)
    print(output, flush=True)
    raise SystemExit(0 if passed else 1)


# Importing this command never launches discovery or provisions a compiler.
if __name__ == '__main__':
    main()
