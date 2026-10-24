#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Initialize recorded upstream gitlinks, using a focused checkout for the large JAM vector repository.

Exposes initialize_vectors, prefetch_blobs and a setup CLI that checks out recorded submodule pins,
including a focused vector checkout and batched provisioning of consumed pinned blobs.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]


# Execute structured Git arguments without shell interpolation or upstream scripts.
def git(*args,cwd=None,output=False):
    if cwd is None:
        cwd=ROOT # Resolve the owning checkout when called, including isolated local fixtures.
    command=['git','-C',str(cwd),*args]
    if output:
        return subprocess.check_output(command,text=True).strip()
    subprocess.run(command,check=True)


# Keep the large trace/STF corpus out of the working tree while retaining its exact upstream Git revision.
def initialize_vectors(path,revision,url):
    if not (path/'.git').exists():
        # Partial/no-checkout clone fetches metadata first; only selected blobs are materialized below.
        git('clone','--depth=1','--filter=blob:none','--no-checkout',url,str(path))
        git('fetch','--depth=1','origin',revision,cwd=path)
        metadata=Path(git('rev-parse','--absolute-git-dir',cwd=path,output=True))
        (metadata/'info/sparse-checkout').write_text('/*\n!/*/\n/codec/\n/stf/\n!/stf/*/\n/stf/safrole/\n')
        git('config','core.sparseCheckout','true',cwd=path)
        git('checkout','--detach',revision,cwd=path)
        git('submodule','absorbgitdirs','--',str(path.relative_to(ROOT)))
    else:
        # Existing clean checkouts can be narrowed without changing their pinned commit or local data.
        git('sparse-checkout','set','--cone','codec','stf/safrole',cwd=path)


# Fetch only consumed pinned blobs together; individual lazy Git reads otherwise incur one network round trip each.
def prefetch_blobs(path, revision, names):
    names = set(names)
    if not names:
        return
    listing = subprocess.check_output(
        ['git', '-C', str(path), 'ls-tree', '-rz', revision, '--', *sorted(names)])
    objects = {}
    # Resolve paths against the immutable tree, and reject absent paths or directories before fetching anything.
    for record in listing.split(b'\0'):
        if record:
            metadata, name = record.split(b'\t', 1)
            _, kind, oid = metadata.decode().split()
            if kind != 'blob':
                raise ValueError(f'Expected pinned blob: {name!r}')
            objects[name.decode()] = oid
    if objects.keys() != names:
        raise ValueError(f'Missing pinned blobs: {sorted(names - objects.keys())}')
    # Query local availability without triggering lazy fetches; complete/warm clones require no network.
    identities = sorted(set(objects.values()))
    status = subprocess.check_output(
        ['git', '-C', str(path), 'cat-file', '--batch-check'],
        input='\n'.join(identities)+'\n', text=True,
        env={**os.environ, 'GIT_NO_LAZY_FETCH': '1'})
    missing = [line.split()[0] for line in status.splitlines() if line.endswith(' missing')]
    if missing:
        # Explicit blob wants retain the pinned commit, sparse checkout and all existing refs unchanged.
        subprocess.run(['git', '-C', str(path), '-c', 'fetch.negotiationAlgorithm=noop',
                        'fetch', 'origin', '--no-tags', '--no-write-fetch-head',
                        '--recurse-submodules=no', '--filter=blob:none', '--stdin'],
                       input='\n'.join(missing)+'\n', text=True, check=True)


# Distinguish real source edits from a clean nested checkout left at its previous recorded pin.
def require_pristine(path, label):
    staged=git('diff','--cached','--name-only','--ignore-submodules=none',cwd=path,output=True)
    changes=git('status','--porcelain','--untracked-files=normal',
                '--ignore-submodules=all',cwd=path,output=True)
    assert not staged and not changes, f'Modified source checkout: {label}'
    if (path/'.gitmodules').exists():
        # Inspect indexed nested gitlinks independently, so ignore preferences cannot conceal real child edits.
        for record in git('ls-files','--stage','-z',cwd=path,output=True).split('\0'):
            if not record:
                continue # Git's final NUL is not another entry.
            header,name=record.split('\t',1)
            if header.split()[0]=='160000' and (path/name/'.git').exists():
                require_pristine(path/name, label+'/'+name)


# Preflight the complete selected batch before moving any clean source checkout.
def source_records(selected):
    records=[]
    listing=git('config','--file',str(ROOT/'.gitmodules'),'--get-regexp',r'^submodule\..*\.path$',output=True)
    known=set()
    for line in listing.splitlines():
        key,relative=line.split(maxsplit=1)
        known.add(relative)
        if selected and relative not in selected:
            continue # Focused Make consumers must not provision unrelated source families.
        assert relative.startswith('vendor/') and '..' not in Path(relative).parts
        record=git('ls-files','--stage','--',relative,output=True).split(maxsplit=3)
        assert len(record)==4 and record[0]=='160000' and record[2]=='0', f'Missing/resolved gitlink required: {relative}'
        revision=record[1]
        url=git('config','--file',str(ROOT/'.gitmodules'),'--get',key.removesuffix('.path')+'.url',output=True)
        assert url.startswith('https://github.com/')
        path=ROOT/relative
        if (path/'.git').exists():
            # A clean old revision is expected after a parent update; real edits, including nested edits, remain a refusal.
            require_pristine(path, relative)
        records.append((relative,revision,url))
    assert selected <= known, f'Unknown source paths: {sorted(selected-known)}'
    return records


# Align static read-only sources to indexed pins; no remote branch, merge, reset, force or push is used.
def main(arguments=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefetch-blobs', action='store_true',
                        help='Provision consumed pinned vector blobs before Python verification')
    parser.add_argument('paths', nargs='*', help='Optional submodule paths to check out at recorded pins')
    arguments = parser.parse_args(arguments)
    records=source_records(set(arguments.paths))
    for relative,revision,url in records:
        path=ROOT/relative
        if relative=='vendor/jamtestvectors':
            initialize_vectors(path,revision,url) # Preserve focused sparse/partial checkout during initial and later pin updates.
        # Explicit checkout overrides configured merge/rebase/custom update strategies, including nested sources.
        git('submodule','update','--init','--recursive','--checkout','--depth=1',
            '--filter=blob:none','--',relative)
        assert git('rev-parse','HEAD',cwd=path,output=True)==revision, f'Wrong checkout: {relative}'
        if relative=='vendor/jamtestvectors' and arguments.prefetch_blobs:
            # Only Python provenance consumes the complete pinned blob set; native jobs keep focused setup.
            vectors = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
            assert vectors['path'] == relative and vectors['commit'] == revision, 'Vector pin/gitlink mismatch'
            prefetch_blobs(path, revision, vectors.get('git_blobs', {}))
    print('Pinned source submodules ready.')


# Importing this module never starts downloads or modifies any Git checkout.
if __name__=='__main__':
    main()
