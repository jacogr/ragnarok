#!/usr/bin/env python3
"""Reproduce width alternatives and verify migrated exact-capture verdicts against unchanged evidence."""
import hashlib
import json
import platform
import subprocess
from dependencies import codec_sources
from state_composition_oracle import chapters, capture, PROFILE, POLICY
from state_widths_oracle import privilege_binaries, trace_values
from state_layout_oracle import token
from test_support import ROOT, nim_command


# Pinned originals supply expectations before compilation; complete matches still retain the explicit gas-policy gate.
def main():
    codec_sources()
    binaries, traces = privilege_binaries(), trace_values()
    lines = ['B '+' '.join(map(str, PROFILE))+' '+' '.join(token(v) for v in chapters())]
    expected = ['selftest']
    records = []
    # Each exact-capture request records its identity and current decoder's complete-entry verdict.
    def add(chapter, raw, profile, identity):
        wanted = capture(chapter, raw, profile)
        lines.append('C '+' '.join(map(str, (*profile, *POLICY, chapter)))+' '+token(raw))
        expected.append(wanted)
        records.append(dict(**identity, chapter=chapter, current_expected=wanted))
    # Nonempty binaries are explicitly STF fields, not original Merkle-trie T12 values.
    for raw, evidence in binaries:
        profile = (2, 6, 6, 12) if '/tiny/' in evidence['path'] else (341, 1023, 1023, 600)
        add(12, raw, profile, dict(path=evidence['path']+'.bin', phase='pre_state'))
    # Both chapters are observed at exact original value extents, without replacing any wire field.
    for privilege, activity, evidence in traces:
        for chapter, raw in ((12, privilege), (13, activity)):
            add(chapter, raw, (2, 6, 6, 12), dict(path=evidence['path'], phase=evidence['phase']))
    folder = ROOT/'build/state-widths'
    folder.mkdir(parents=True, exist_ok=True)
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
    # Every original fixed-width privilege/statistics value must capture completely after migration.
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (index, got, wanted)
    assert actual[1:] == ['ok']*36, 'Migrated published values must consume completely'
    for observation, verdict in zip(records, actual[1:]):
        observation['current_actual'] = verdict
    pin = json.loads((ROOT/'spec/pins.json').read_text())
    summary = dict(status='passed', scope='migrated C12 E4/E8 and C13 E4 keys; C13 gas remains gated',
        graypaper_commit=pin['graypaper']['commit'], vectors_commit=pin['vectors']['commit'],
        binary_privilege_fields=[e for _, e in binaries], raw_trace_observations=[e for _, _, e in traces],
        native_requests=len(lines), current_captures=records, build_command=command,
        width_candidates=sum(len(e['candidates']) for _, e in binaries)+sum(len(e['candidates']) for _, _, e in traces),
        metadata_associations=sum(len(e['matching_metadata_keys']) for _, _, e in traces),
        current_exact_rejections=sum(e['current_actual'] != 'ok' for e in records),
        request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(),
        environment=dict(system=platform.system(), machine=platform.machine(), python=platform.python_version(),
            nim=subprocess.check_output(['nim', '--version'], text=True).strip()),
        migration='complete: C12 E4 service/E8 gas; C13 E4 service keys',
        remaining_gate='C13 natural gas still conflicts with the general T fixed-width note')
    (folder/'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(f'PASS width investigation: {len(binaries)} nonempty binary privilege fields, '
          f'{len(traces)} raw trace observations, {len(lines)} checked native requests')
    print('MIGRATION VERIFIED: all 36 published-value captures consume completely; C13 gas remains gated')


# Importing the runner never compiles code or executes upstream libraries/generators.
if __name__ == '__main__':
    main()
