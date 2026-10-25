# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Materialize portable independent operator bundles and compare bounded public-command invocations without input mutation."""
import hashlib
import json
from pathlib import Path
from corpus_checks import compare_corpus


def digest(data):
    """Hash exact supplied bytes; pathnames and platform-specific command transport are separate metadata."""
    return hashlib.sha256(data).hexdigest()


def materialize(folder,jobs,expected):
    """Write only authored files, preserving exact bytes and spaces in actual paths; return a portable content manifest."""
    assert len(jobs)==len(expected)>0
    folder.mkdir(parents=True,exist_ok=True);commands=[];files={};paths=[]
    for ordinal,job in enumerate(jobs):
        name='case-'+str(ordinal).zfill(4);local=folder/name;local.mkdir(exist_ok=True)
        data=[('chain.json',job['config'].encode()),('genesis.bin',job['genesis'])]
        data.extend(('step-'+str(index).zfill(4)+'.bin',wire) for index,wire in enumerate(job['steps']))
        current=[]
        for basename,wire in data:
            path=local/basename;path.write_bytes(wire);current.append(path)
            relative=(Path(name)/basename).as_posix();files[relative]=digest(wire);paths.append((path,files[relative]))
        request=folder/('invoke-'+str(ordinal).zfill(4)+'.txt')
        request.write_text(' '.join(str(path.resolve()).encode().hex() for path in current)+'\n')
        commands.append(request) # The native argument parser receives real files; hex transports pathnames without a shell.
    manifest=dict(files=files,expected=expected)
    (folder/'manifest.json').write_text(json.dumps(manifest,indent=2,sort_keys=True)+'\n')
    return commands,manifest,paths


def compare_jobs(result,command,binary,policy,commands,expected,paths):
    """Every complete command gets its unchanged runtime budget; exact rows, exit codes, policy and immutable inputs all gate success."""
    assert len(commands)==len(expected)>0
    if result['build']['exit_code']!=0:return
    outputs=[];runs=[];policies=[]
    for ordinal,source in enumerate(commands):
        child=dict(build=result['build'],passed=False)
        def capture(arguments,name):
            """Retain complete stdout before the shared strict comparator consumes the process payload."""
            run=command(arguments,name);outputs.append(run['output']);return run
        compare_corpus(child,capture,[binary,source,policy,'population'],source.stem+'-command',[expected[ordinal]])
        child['inputs_unchanged']=all(path.is_file() and digest(path.read_bytes())==sha for path,sha in paths)
        child['passed']=child['passed'] and child['inputs_unchanged']
        policies.append(digest(policy.read_bytes()) if policy.is_file() else None)
        runs.append({k:v for k,v in child.items() if k!='build'})
    output=''.join(outputs);actual=output.splitlines()
    consistent=bool(policies) and None not in policies and len(set(policies))==1
    result.update(passed=len(runs)==len(expected) and all(run['passed'] for run in runs) and actual==expected and consistent,
        runs=runs,actual_sha256=digest(output.encode()),expected_sha256=digest(('\n'.join(expected)+'\n').encode()),
        policy_sha256=policies[0] if consistent else None)
    if not result['passed']:
        result['first_mismatch']=next((i for i,(a,e) in enumerate(zip(actual,expected)) if a!=e),min(len(actual),len(expected)))
