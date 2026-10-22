# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Use the maintained process-group timeout runner for isolated child-limit observations."""
import json
from pathlib import Path
import sys
from pvm_reference import command
from storage_limit_outcomes import classify
from storage_resource_validation import validate_checks

CHILD=Path(__file__).with_name('storage_limit_child.py')


def execute(arguments,cap,owned,folder,name,timeout=300):
    """A timed-out observer cannot publish a completed receipt; its entire process group is killed."""
    target=Path(owned)/(name+'.json')
    target.unlink(missing_ok=True)
    argv=[sys.executable,str(CHILD),str(target),str(cap or 0),'--',*[str(a) for a in arguments]]
    check=command(argv,name,Path(folder),timeout=timeout)
    if check['exit_code']!=0:
        raise RuntimeError('Memory experiment supervision failed: '+check['log'])
    raw=target.read_text();value=json.loads(raw)
    return dict(check=check,receipt_path=str(target),receipt_raw=raw,observation=value,
                outcome=classify(value,cap),raw=Path(check['log']).read_text())


def validate_execution(value,arguments,cap,interpreter):
    """Reconstruct the exact observer/native argv and reparse the original exit/resource receipt."""
    if type(value) is not dict or set(value)!= {'check','receipt_path','receipt_raw','observation','outcome','raw'}:
        raise ValueError('Invalid supervised memory execution')
    validate_checks([value['check']],1)
    if type(value['receipt_path']) is not str or type(value['receipt_raw']) is not str or type(value['raw']) is not str:
        raise ValueError('Invalid supervised memory raw evidence')
    parsed=json.loads(value['receipt_raw'])
    if json.dumps(parsed,sort_keys=True)!=json.dumps(value['observation'],sort_keys=True) or classify(parsed,cap)!=value['outcome']:
        raise ValueError('Substituted supervised memory outcome')
    expected=[interpreter,str(CHILD),value['receipt_path'],str(cap or 0),'--',*[str(a) for a in arguments]]
    if value['check']['command']!=expected:
        raise ValueError('Substituted supervised memory command')
    return value
