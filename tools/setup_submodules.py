#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Initialize recorded upstream gitlinks, using a focused checkout for the large JAM vector repository.

Exposes initialize_vectors, prefetch_blobs and a setup CLI that restores pinned submodules,
including a focused vector checkout and batched provisioning of consumed pinned blobs.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT=Path(__file__).resolve().parents[1]


# Execute structured Git arguments without shell interpolation or upstream scripts.
def git(*args,cwd=ROOT,output=False):
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


# Initialize only recorded gitlinks and stop rather than overwrite local dependency edits.
def main():
    listing=git('config','--file',str(ROOT/'.gitmodules'),'--get-regexp',r'^submodule\..*\.path$',output=True)
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--prefetch-blobs', action='store_true',
                        help='Provision consumed pinned vector blobs before Python verification')
    parser.add_argument('paths', nargs='*', help='Optional submodule paths to initialize')
    arguments = parser.parse_args()
    selected=set(arguments.paths)
    for line in listing.splitlines():
        key,relative=line.split(maxsplit=1)
        # Optional arguments restrict initialization to the source requested by a particular test runner.
        if selected and relative not in selected:
            continue
        assert relative.startswith('vendor/') and '..' not in Path(relative).parts
        record=git('ls-files','--stage','--',relative,output=True).split()
        assert record[0]=='160000', f'Missing staged/committed gitlink: {relative}'
        revision=record[1];path=ROOT/relative
        url=git('config','--file',str(ROOT/'.gitmodules'),'--get',key.removesuffix('.path')+'.url',output=True)
        assert url.startswith('https://github.com/')
        if (path/'.git').exists():
            # No reset/force is used, and even unrelated uncommitted dependency changes block initialization.
            assert not git('status','--porcelain','--untracked-files=normal',cwd=path,output=True), relative
            assert git('rev-parse','HEAD',cwd=path,output=True)==revision, f'Wrong checkout: {relative}'
        if relative=='vendor/jamtestvectors':
            initialize_vectors(path,revision,url)
            # Only Python provenance consumes the complete pinned blob set; native jobs keep focused setup.
            if arguments.prefetch_blobs:
                vectors = json.loads((ROOT/'spec/pins.json').read_text())['vectors']
                assert vectors['path'] == relative and vectors['commit'] == revision, 'Vector pin/gitlink mismatch'
                prefetch_blobs(path, revision, vectors.get('git_blobs', {}))
        else:
            # Native submodule children keep the revisions already recorded by their parent repository.
            git('submodule','update','--init','--recursive','--depth=1','--filter=blob:none','--',relative)
    print('Pinned source submodules ready.')


# Importing this module never starts downloads or modifies any Git checkout.
if __name__=='__main__':
    main()
