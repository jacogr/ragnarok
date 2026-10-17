#!/usr/bin/env python3
"""Run the supported pinned Nimony verification path; no global Nim 2 compiler is consulted."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
from setup_nimony import ROOT, installed, host_pins, verify_identity, verify_version
from native_tests import unit_command, unit_environment, unit_evidence, ARC_SUITES, UNIT_LINKS, unit_runtime_fixtures


# Keep CI's independent runtime/module jobs and the complete local run on one explicit command plan.
def plan(suite, compiler, libraries=None):
    common = [sys.executable]
    runtime = [common+['tools/format.py', '--check'], common+['tests/test_nimony_ci.py'],
               common+['tests/test_spec.py'], common+['tools/test_nimony.py', '--compiler', str(compiler)],
               common+['-m', 'unittest', 'discover', '-s', 'tests', '-p', 'test_*harness.py']]
    modules = [common+['tools/audit_nimony_modules.py', '--compiler', str(compiler)]]
    if suite == 'unit':
        # Keep dependency-free codec discovery separate from each explicit native linking profile.
        return [unit_command(compiler)]+[unit_command(compiler, name, libraries) for name in UNIT_LINKS]
    if suite == 'runtime':
        # Runtime includes the independent Python orchestration/reference safeguards after native fixture preparation.
        return runtime
    if suite == 'modules':
        # The module-only CI job needs no native libraries, source submodules or test fixtures.
        return modules
    if suite == 'all':
        # Compile the full inventory first, then exercise linked/negative/native lifecycle coverage.
        return modules+runtime
    raise ValueError('Unknown verification suite: '+suite)


# Resolve only an installed, identity-checked compiler; explicit CI paths undergo the same pin checks.
def environment(compiler=None):
    pins = host_pins(json.loads((ROOT/'spec/toolchain.json').read_text()))
    if compiler is None:
        # Local setup records exact compiler/formatter paths without requiring shell activation.
        compiler, formatter = installed()
    else:
        # CI setup exports a verified formatter path and a compiler belonging to the same selected nightly.
        compiler = Path(compiler).resolve()
        verify_identity(compiler.parent.parent, pins)
        verify_version(compiler, pins['version'])
        formatter = Path(os.environ['NIMPRETTY']).resolve()
    banner = subprocess.check_output([str(formatter), '--version'], text=True).strip()
    if banner != pins['formatter_banner']:
        raise ValueError('Unexpected formatter banner')
    return compiler, {**os.environ, 'NIMPRETTY': str(formatter), 'PYTHONDONTWRITEBYTECODE': '1',
                      'PYTHONUNBUFFERED': '1'}


# Run every selected gate in order and preserve the first failed status instead of publishing partial success.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--suite', choices=('all', 'runtime', 'modules', 'unit'), default='all')
    parser.add_argument('--compiler', type=Path)
    args = parser.parse_args()
    compiler, selected = environment(args.compiler)
    libraries = None
    if args.suite == 'unit':
        # Reuse the same pristine pinned crypto, Rust and QUIC preparations as CI.
        sys.path.insert(0, str(ROOT/'tests'))
        from nimony_crypto import prepare
        folder = ROOT/'build/nim-tests/native'
        folder.mkdir(parents=True, exist_ok=True)
        crypto, observer, evidence = prepare(folder)
        (folder/'preparation.json').write_text(json.dumps(evidence, indent=2)+'\n')
        libraries = dict(crypto=crypto, observer=observer)
        from bandersnatch_native import prepare as prepare_bandersnatch
        bs, bs_observer, bs_evidence = prepare_bandersnatch(folder)
        libraries.update(bandersnatch=bs, bandersnatch_observer=bs_observer)
        (folder/'bandersnatch-preparation.json').write_text(json.dumps(bs_evidence, indent=2)+'\n')
        from nimony_quic import prepare as prepare_quic
        quic, certificates, quic_evidence = prepare_quic()
        libraries['quic'] = quic
        (folder/'quic-preparation.json').write_text(json.dumps(quic_evidence, indent=2)+'\n')
        import test_integration as integration_fixture
        integration_fixture.BUILD.mkdir(parents=True, exist_ok=True)
        wires, _ = integration_fixture.corpus()
        reload = folder/'integration-reload'
        reload.mkdir(exist_ok=True)
        for index in range(8):
            # Different candidate bytes expose a refused bank reload that accidentally publishes partial data.
            wire = bytearray((wires/(str(index)+'.bin')).read_bytes())
            wire[0] ^= 128
            (reload/(str(index)+'.bin')).write_bytes(wire)
        fixtures = unit_runtime_fixtures(certificates, wires, reload)
        # All fixture hashes are verified and old observations retired before any native suite runs.
        selected = unit_environment(compiler, base=selected, fixtures=fixtures)
    for arguments in plan(args.suite, compiler, libraries):
        # Structured arguments avoid shell interpretation; output remains visible in the normal local/CI transcript.
        print('+ '+' '.join(arguments), flush=True)
        subprocess.run(arguments, cwd=ROOT, env=selected, check=True)
    if args.suite == 'unit':
        # Record/report live occupancy without baking platform-specific heap sizes into goldens.
        for name in ARC_SUITES:
            print('ARC '+name+': '+json.dumps(unit_evidence(compiler, name), sort_keys=True), flush=True)
    print('PASS supported Nimony verification: '+args.suite, flush=True)


# Importing the command plan performs no setup, build or network operation.
if __name__ == '__main__':
    main()
