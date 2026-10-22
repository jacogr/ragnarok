# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Disposable exec launcher: record one child-local cap, suppress core files and replace this process."""
import json
from pathlib import Path
import os
import resource
import sys
from storage_limit_apply import apply_cap
from storage_limit_budget import natural


def launch(target,cap,arguments):
    """The observer remains uncapped; the exec'ed native process inherits only this launcher's soft ceiling."""
    target=Path(target);target.unlink(missing_ok=True)
    if not arguments or not Path(arguments[0]).is_absolute():
        raise ValueError('Expected absolute native executable')
    receipt=apply_cap(cap)
    target.write_text(json.dumps(receipt,sort_keys=True)+'\n')
    if receipt['status'] not in ('unchanged','applied'):
        raise SystemExit(77)
    # Refused/crashed measurement children must not create unbounded core artifacts.
    resource.setrlimit(resource.RLIMIT_CORE,(0,0))
    os.execv(arguments[0],arguments)


# CLI argument zero means unchanged; every nonzero request passes the finite budget validator.
if __name__=='__main__':
    if len(sys.argv)<5 or sys.argv[3]!='--':
        raise SystemExit('Expected receipt, cap and native command')
    value=natural(sys.argv[2]);launch(sys.argv[1],None if value==0 else value,sys.argv[4:])
