#!/usr/bin/env python3
"""Verify checked native Boolean/bitstring APIs against independent framing, bit order and failure observations."""
import hashlib
import json
import subprocess
from bits_oracle import requests
from test_support import ROOT, nim_command, reject_types
from dependencies import codec_sources


# Compile native checks, compare deterministic requests and ensure nominal/privacy misuse is rejected.
def main():
    codec_sources()
    folder = ROOT/'build/bits'
    folder.mkdir(parents=True, exist_ok=True)
    builds = []
    # Public tests, private-wire probes and the batch adapter all retain the selected checked LTO configuration.
    for source, name in (('test_bits', 'selftest'), ('test_bits_private', 'private'), ('bits_driver', 'driver')):
        command = nim_command(ROOT/f'tests/native/{source}.nim', folder/name, folder/f'{name}-cache')
        builds.append(command)
        with (folder/f'{name}-build.log').open('w') as log:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    subprocess.run([str(folder/'selftest')], cwd=ROOT, check=True)
    subprocess.run([str(folder/'private')], cwd=ROOT, check=True)
    lines, expected = requests()
    path = folder/'requests.txt'; path.write_text('\n'.join(lines)+'\n')
    result = subprocess.run([str(folder/'driver'), str(path)], cwd=ROOT, capture_output=True, text=True, timeout=180, check=True)
    (folder/'stderr.log').write_text(result.stderr)
    actual = result.stdout.splitlines()
    assert len(actual) == len(expected), (len(actual), len(expected))
    # Expected wire, logical bits, prefix extent and error reasons were computed before running the native codec.
    for index, (got, wanted) in enumerate(zip(actual, expected)):
        assert got == wanted, (index, lines[index][:200], got[:200], wanted[:200])
    cases = [('count', ROOT/'tests/native/compile_fail/raw_bit_count.nim', ('BitCount', 'uint64')),
             ('limit', ROOT/'tests/native/compile_fail/swapped_bit_limit.nim', ('BitLimit', 'ByteLimit'))]
    rejected = reject_types(cases, folder/'types')
    command = ['nim', 'check', '--mm:arc', '--skipParentCfg', '--skipUserCfg',
               str(ROOT/'tests/native/compile_fail/private_bits_snapshot.nim')]
    probe = subprocess.run(command, cwd=ROOT, capture_output=True, text=True, timeout=60)
    diagnostic = probe.stdout+probe.stderr
    (folder/'types/private.log').write_text(diagnostic)
    assert probe.returncode != 0 and 'undeclared field' in diagnostic and 'data' in diagnostic, diagnostic
    summary = dict(status='passed', requests=len(lines), nominal_rejections=len(rejected), private_owner_rejections=1,
                   request_sha256=hashlib.sha256(path.read_bytes()).hexdigest(), build_commands=builds)
    (folder/'results.json').write_text(json.dumps(summary, indent=2)+'\n')
    print(f'PASS Boolean/bitstrings: {len(lines)} independent requests, two nominal and one private-owner rejection')


# Importing test helpers never builds binaries or modifies pinned dependency sources.
if __name__ == '__main__':
    main()
