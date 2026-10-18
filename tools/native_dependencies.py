"""Shared pristine source checks and logged native build commands, independent of test harnesses."""
from pathlib import Path
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[1]


# Run structured commands without shell interpolation; append diagnostics to a retained reproducible build log.
def run(args, log=None):
    print('+ ' + ' '.join(map(str, args)), flush=True)
    return subprocess.run(list(map(str, args)), check=True, stdout=log, stderr=log)



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

