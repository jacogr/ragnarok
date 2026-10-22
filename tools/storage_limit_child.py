# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Uncapped fresh observer retaining child resources and nonzero exits without asserting native success."""
import json
from pathlib import Path
import platform
import resource
import subprocess
import sys
from storage_limit_budget import natural
from storage_limit_receipts import validate_limit

EXEC=Path(__file__).with_name('storage_limit_exec.py')


def observe(target,cap,arguments):
    """One launcher execs one native process; child RSS excludes this Python observer and the producer."""
    target=Path(target);limit_path=target.with_suffix('.limit.json')
    target.unlink(missing_ok=True);limit_path.unlink(missing_ok=True)
    system=platform.system()
    if system not in ('Linux','Darwin') or resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss!=0:
        raise ValueError('Unsupported or reused child resource observer')
    completed=subprocess.run([sys.executable,str(EXEC),str(limit_path),str(cap or 0),'--',*arguments],check=False)
    receipt=validate_limit(json.loads(limit_path.read_text()),cap)
    usage=resource.getrusage(resource.RUSAGE_CHILDREN)
    counters=dict(peak_rss_bytes=int(usage.ru_maxrss)*(1024 if system=='Linux' else 1),minor_faults=int(usage.ru_minflt),major_faults=int(usage.ru_majflt))
    target.write_text(json.dumps(dict(exit_code=completed.returncode,limit=receipt,resources=counters),sort_keys=True)+'\n')


# Outer command supervision owns group timeout cleanup; a receipt cannot turn native failure into success.
if __name__=='__main__':
    if len(sys.argv)<5 or sys.argv[3]!='--':
        raise SystemExit('Expected observation, cap and native command')
    value=natural(sys.argv[2]);observe(sys.argv[1],None if value==0 else value,sys.argv[4:])
