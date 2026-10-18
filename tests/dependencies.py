"""Check exact Git submodule revisions and pristine source trees before native builds."""
from pathlib import Path
import sys

sys.path.insert(0, str(Path(__file__).resolve().parents[1]/'tools'))
from native_dependencies import ROOT, require_submodule


# Verify the official codec source checkout before any fixture is accepted by a native test.
def codec_sources():
    import json
    pins=json.loads((ROOT/'spec/pins.json').read_text())
    entry=pins['vectors']
    require_submodule({'path':entry['path'],'repository':entry['repository'].removeprefix('https://github.com/'),'commit':entry['commit']})
