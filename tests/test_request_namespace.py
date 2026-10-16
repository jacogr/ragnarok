#!/usr/bin/env python3
"""Check small, funded local-rule namespace witnesses through checked Nim whole-state composition."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from request_namespace_oracle import requests
from test_support import ROOT, nim_command


# Independent local account predicates and expected roots are computed before compiling native composition.
def main():
    codec_sources()
    folder = ROOT/'build/request-namespace'
    folder.mkdir(parents=True, exist_ok=True)
    pin = json.loads((ROOT/'spec/pins.json').read_text())
    sources = ('text/accounts.tex', 'text/definitions.tex', 'text/pvm_invocations.tex',
               'text/accumulation.tex', 'text/merklization.tex')
    # Verify each normative source used by the local equations before evaluating either witness.
    for name in sources:
        raw = (ROOT/pin['graypaper']['path']/name).read_bytes()
        assert hashlib.sha256(raw).hexdigest() == pin['graypaper']['source_sha256'][name], name
    lines, expected, evidence = requests()
    path = folder/'requests.txt'
    path.write_text('\n'.join(lines)+'\n')
    library = ROOT/('build/crypto/libragnarok_crypto.dylib' if platform.system() == 'Darwin'
                    else 'build/crypto/libragnarok_crypto.so')
    assert library.is_file(), 'Run python3 tests/test_crypto.py first'
    command = nim_command(ROOT/'tests/native/state_composition_driver.nim', folder/'driver', folder/'cache', [library])
    with (folder/'build.log').open('w') as log:
        subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    result = subprocess.run([str(folder/'driver'), str(path)], cwd=ROOT,
                            capture_output=True, text=True, timeout=180, check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual = result.stdout.splitlines()
    assert len(actual) == len(expected), (len(actual), len(expected))
    # Every predecessor/control matches its exact root and entries; marker post-states return only DuplicateKey.
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (index, got[:160], wanted[:160])
    summary = dict(status='passed', native_requests=len(lines), witnesses=evidence,
        graypaper_commit=pin['graypaper']['commit'], build_command=command,
        normative_sources={name: pin['graypaper']['source_sha256'][name] for name in sources},
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        environment=dict(system=platform.system(), machine=platform.machine(), python=platform.python_version(),
            nim=subprocess.check_output(['nim', '--version'], text=True).strip()),
        scope='local fresh-solicit/account/deposit counterexamples plus native composition; no PVM execution or genesis reachability',
        namespace_policy='pending normative clarification; full request-length domain retained; duplicate entries rejected')
    (folder/'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(f'PASS namespace review: {len(evidence)} funded tiny-payload local witnesses; '
          f'{len(lines)} checked native requests (four successful mappings, two DuplicateKey verdicts, ownership selftest)')
    print('M1 PARITY OPEN: cited local predicates do not exclude overlapping lengths; no new restriction inferred')


# Importing the runner never builds code or executes upstream scripts.
if __name__ == '__main__':
    main()
