"""Check exact Git submodule revisions and pristine source trees before native builds."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


# Check one pinned source checkout, optionally initializing its recorded Git submodule with no upstream scripts.
def require_submodule(entry, fetch=False):
    relative = entry['path']
    path = ROOT / relative
    assert relative.startswith('vendor/') and '..' not in Path(relative).parts
    # Only explicit fetch mode can initialize missing source checkouts; existing work is never reset.
    if not (path / '.git').exists() and fetch:
        parent = '/'.join(Path(relative).parts[:2])
        subprocess.run([sys.executable,str(ROOT/'tools/setup_submodules.py'),parent],check=True)
    assert (path / '.git').exists(), f'Initialize submodules: git submodule update --init --recursive ({relative})'
    actual = subprocess.check_output(['git','-C',str(path),'rev-parse','HEAD'],text=True).strip()
    assert actual == entry['commit'], f'Wrong source revision: {relative}'
    url = subprocess.check_output(['git','-C',str(path),'remote','get-url','origin'],text=True).strip().removesuffix('.git')
    assert url == 'https://github.com/' + entry['repository'], relative
    dirty = subprocess.check_output(['git','-C',str(path),'status','--porcelain','--untracked-files=normal'],text=True)
    assert not dirty, f'Modified dependency source: {relative}\n{dirty}'
    return path


# Verify the official codec source checkout before any fixture is accepted by a native test.
def codec_sources():
    import json
    pins=json.loads((ROOT/'spec/pins.json').read_text())
    entry=pins['vectors']
    require_submodule({'path':entry['path'],'repository':entry['repository'].removeprefix('https://github.com/'),'commit':entry['commit']})
