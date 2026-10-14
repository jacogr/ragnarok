#!/usr/bin/env python3
"""Initialize recorded upstream gitlinks, using a focused checkout for the large JAM vector repository."""
from pathlib import Path
import subprocess
import sys

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


# Initialize only recorded gitlinks and stop rather than overwrite local dependency edits.
def main():
    listing=git('config','--file',str(ROOT/'.gitmodules'),'--get-regexp',r'^submodule\..*\.path$',output=True)
    selected=set(sys.argv[1:])
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
        else:
            # Native submodule children keep the revisions already recorded by their parent repository.
            git('submodule','update','--init','--recursive','--depth=1','--filter=blob:none','--',relative)
    print('Pinned source submodules ready.')


# Importing this module never starts downloads or modifies any Git checkout.
if __name__=='__main__':
    main()
