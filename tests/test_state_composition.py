#!/usr/bin/env python3
"""Build checked Nim composition and compare exact independent chapter and whole-map observations."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_composition_oracle import requests
from test_support import ROOT, nim_command, reject_types


# Expected bytes and roots are computed before compilation; no native round trip supplies an answer.
def main():
    codec_sources()
    folder = ROOT/'build/state-composition'
    folder.mkdir(parents=True, exist_ok=True)
    library = ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system() == 'Darwin'
                    else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(), 'Run python3 tests/test_crypto.py first'
    lines, expected, evidence, whole_evidence = requests()
    path = folder/'requests.txt'
    path.write_text('\n'.join(lines)+'\n')
    command = nim_command(ROOT/'tests/native/state_composition_driver.nim', folder/'driver',
                          folder/'cache', [library])
    with (folder/'build.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    result = subprocess.run([str(folder/'driver'), str(path)], cwd=ROOT,
                            capture_output=True, text=True, timeout=180, check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual = result.stdout.splitlines()
    assert len(actual) == len(expected), (len(actual), len(expected))
    # Compare complete map bytes as well as roots, and failure reasons without application values.
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (index, got[:180], wanted[:180], lines[index][:160])
    nominal = reject_types([
        ('index', ROOT/'tests/native/compile_fail/composition_service_as_entry.nim',
         ('ServiceIndex', 'StateEntryIndex')),
        ('owner', ROOT/'tests/native/compile_fail/composition_entry_as_chapter.nim',
         ('StateEntry', 'StateChapterSnapshot'))], folder/'types')
    # Both immutable owner types must prevent direct access to their retained bytes and validation identity.
    for name in ('snapshot', 'chapter'):
        privacy = ['nim', 'check', '--mm:arc', '--skipParentCfg', '--skipUserCfg',
                   str(ROOT/f'tests/native/compile_fail/composition_{name}_private.nim')]
        checked = subprocess.run(privacy, cwd=ROOT, capture_output=True, text=True, timeout=60)
        diagnostics = checked.stdout+checked.stderr
        (folder/f'types/{name}-private.log').write_text(diagnostics)
        assert checked.returncode != 0 and 'data' in diagnostics and 'undeclared field' in diagnostics, diagnostics
    pins = json.loads((ROOT/'spec/pins.json').read_text())
    summary = dict(status='passed', requests=len(lines), nominal_rejections=len(nominal),
        privacy_rejections=2, build_command=command, published_component_observations=evidence,
        graypaper_commit=pins["graypaper"]["commit"], vectors_commit=pins["vectors"]["commit"],
        environment=dict(system=platform.system(), machine=platform.machine(),
            python=platform.python_version(), nim=subprocess.check_output(["nim", "--version"], text=True).strip()),
        published_composed_states=whole_evidence,
        published_exact_captures=sum(x['verdict'] == 'ok' for x in evidence),
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        scope='exact typed chapter capture plus whole-map composition; migrated dictionary widths; compact C13 gas follows maintainer policy; no transitions')
    (folder/'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(f'PASS typed state composition: {len(lines)} requests, two nominal/two privacy rejections, '
          f'{summary["published_exact_captures"]}/{len(evidence)} exact published component captures, '
          f'{len(whole_evidence)} published complete mappings composed')
    print('M1 PARITY OPEN: parked request-length namespace policy; no full T(state) conformance claim')


# Importing the runner never starts a compiler or executes upstream generators.
if __name__ == '__main__':
    main()
