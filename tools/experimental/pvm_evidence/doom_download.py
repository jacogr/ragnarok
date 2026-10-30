#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Download API-sealed CI artifacts through authenticated gh; extract only bounded inert data."""
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
from pathlib import Path
import stat
import subprocess
import sys
import zipfile

ROOT=Path('/Users/jacogr/Projects/jacogr/ragnarok-pvm-jit')
run=int(sys.argv[1]);expected=sys.argv[2]
architecture=sys.argv[3] if len(sys.argv)>3 else None
assert architecture in (None,'arm64','x86_64')
assert len(expected)==40 and all(c in '0123456789abcdef' for c in expected)
api='repos/jacogr/ragnarok/actions/'


def metadata(endpoint):
    return json.loads(subprocess.check_output(['gh','api',api+endpoint],cwd=ROOT))


base=ROOT/'build/pvm-doom-e2e-evidence'/str(run);base.mkdir(parents=True,exist_ok=True)
info=metadata('runs/'+str(run));assert info['head_sha']==expected and info['event']=='workflow_dispatch'
assert info['status'] in (('in_progress','completed') if architecture else ('completed',)),info['status']
(base/'run.json').write_text(json.dumps(info,indent=2)+'\n')
jobs=metadata('runs/'+str(run)+'/jobs');(base/'jobs.json').write_text(json.dumps(jobs,indent=2)+'\n')
listing=metadata('runs/'+str(run)+'/artifacts');(base/'artifacts.json').write_text(json.dumps(listing,indent=2)+'\n')
names={f'pvm-doom-e2e-{a}-1' for a in ((architecture,) if architecture else ('arm64','x86_64'))}
artifacts=[a for a in listing['artifacts'] if a['name'] in names]
assert {a['name'] for a in artifacts}==names


def one(artifact):
    size=artifact['size_in_bytes'];assert 0<size<256*1024**2
    path=base/(artifact['name']+'.zip');endpoint=api+'artifacts/'+str(artifact['id'])+'/zip'
    (base/(artifact['name']+'.json')).write_text(json.dumps(artifact,indent=2)+'\n')
    if not path.exists():
        temporary=path.with_suffix('.partial')
        # A completed prior transfer can be resumed; final API size and digest bind every assembled byte.
        start=temporary.stat().st_size if temporary.exists() else 0
        assert 0<=start<=size
        if size>16*1024**2:
            ranges=[(left,min(size-1,left+8*1024**2-1)) for left in range(start,size,8*1024**2)]
            def part(bounds):
                left,right=bounds
                data=subprocess.run(['gh','api',endpoint,'-H',f'Range: bytes={left}-{right}'],
                    cwd=ROOT,stdout=subprocess.PIPE,stderr=subprocess.PIPE,check=True,timeout=300).stdout
                assert len(data)==right-left+1,'server ignored requested byte range'
                return data
            with ThreadPoolExecutor(max_workers=4) as pool,temporary.open('ab') as stream:
                for data in pool.map(part,ranges):stream.write(data)
        else:
            with temporary.open('wb') as stream:
                subprocess.run(['gh','api',endpoint],cwd=ROOT,stdout=stream,stderr=subprocess.PIPE,check=True,timeout=300)
        assert temporary.stat().st_size==size
        temporary.rename(path)
    assert path.stat().st_size==size
    wanted=artifact['digest'];observed='sha256:'+hashlib.sha256(path.read_bytes()).hexdigest();assert wanted==observed
    target=base/artifact['name'];target.mkdir(exist_ok=True)
    with zipfile.ZipFile(path) as z:
        assert z.testzip() is None
        members=z.infolist();assert len(members)<10000 and sum(m.file_size for m in members)<2048*1024**2
        seen=set()
        for member in members:
            assert member.filename not in seen;seen.add(member.filename)
            relative=Path(member.filename)
            assert not relative.is_absolute() and '..' not in relative.parts and member.file_size<64*1024**2
            assert relative.parts and relative.parts[0] in ('ci','tests')
            assert '\\' not in member.filename
            assert not stat.S_ISLNK(member.external_attr>>16)
            if member.is_dir():continue
            copied=target/relative;copied.parent.mkdir(parents=True,exist_ok=True)
            data=z.read(member)
            if copied.exists():assert copied.read_bytes()==data
            else:copied.write_bytes(data)
    return dict(name=artifact['name'],id=artifact['id'],bytes=size,digest=observed,payloads=len(members))


with ThreadPoolExecutor(max_workers=2) as pool:
    for result in pool.map(one,artifacts):print(json.dumps(result),flush=True)
