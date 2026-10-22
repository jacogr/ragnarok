#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Observe one native child's lifetime resources in a fresh Python process, excluding the observer."""
import json
from pathlib import Path
import platform
import resource
import subprocess
import sys


def observe(arguments, target):
    """Run one child; failure leaves no resource artifact that could be mistaken for success."""
    target = Path(target)
    target.unlink(missing_ok=True)
    system = platform.system()
    # ru_maxrss is bytes on Darwin and KiB on Linux; other hosts have no admitted unit contract.
    if system not in ('Darwin', 'Linux'):
        raise RuntimeError('Unsupported resource observation host')
    if resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss != 0:
        raise RuntimeError('Resource observer already has child usage')
    completed = subprocess.run(arguments, check=False)
    # The native fixture owns its assertions and diagnostics; a failure cannot publish counters.
    if completed.returncode != 0:
        raise RuntimeError('Native resource workload failed: '+str(completed.returncode))
    usage = resource.getrusage(resource.RUSAGE_CHILDREN)
    counters = dict(peak_rss_bytes=int(usage.ru_maxrss)*(1024 if system == 'Linux' else 1),
                    minor_faults=int(usage.ru_minflt), major_faults=int(usage.ru_majflt))
    target.write_text(json.dumps(counters)+'\n')


# The parent owns the command plan, timeout, process group, private output path and all validation.
if __name__ == '__main__':
    observe(sys.argv[2:], sys.argv[1])
