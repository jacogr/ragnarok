#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Profile and compare owned versus borrowed lookups with matched complete pricing."""
import argparse
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess

from prepare_full import generate_full
from run import ROOT, BUILD, digest
import run_full

OUT = BUILD / 'profile'


def environment(engine, limit):
    """Reuse the frozen, fully checked real guest and request three warmups plus ten samples."""
    fixture = BUILD / 'sieve'
    return {**os.environ, 'PVM_SIEVE_INPUT': str(fixture / f'input-{limit}.bin'),
            'PVM_SIEVE_EXPECTED': str(fixture / f'expected-{limit}.bin'),
            'PVM_SIEVE_ENGINE': engine, 'PVM_SIEVE_SAMPLES': '13'}


def main():
    """Require matching correctness evidence; preserve raw samples, symbols and input identities."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--sample', action='store_true', help='Also capture macOS CPU call-stack samples')
    args = parser.parse_args()
    OUT.mkdir(parents=True, exist_ok=True)
    (OUT / 'results.json').unlink(missing_ok=True)
    control_path = run_full.OUT / 'controls.json'
    controls = json.loads(control_path.read_text())
    assert controls['status'] == 'passed'
    for name, checksum in controls['sources'].items():
        assert digest(ROOT / name) == checksum, 'Recheck changed controls: ' + name
    comparison = json.loads((run_full.OUT / 'results.json').read_text())
    assert comparison['status'] == 'passed'
    for name, checksum in comparison['sources'].items():
        assert digest(ROOT / name) == checksum, 'Refresh changed full comparison: ' + name
    binaries = {'master-complete': run_full.OUT / 'master-complete'}
    generated = {}
    try:
        # Generate each representation sequentially under one module identity and identical build flags.
        for name, owned in [('owned-complete', True), ('borrowed-complete', False)]:
            source = generate_full(ROOT, BUILD, owned_lookup=owned)
            snapshot = OUT / (name + '.nim')
            snapshot.write_bytes(source.read_bytes())
            generated[name] = digest(snapshot)
            binary = run_full.compile_probe(BUILD / 'full_sieve.nim', 'profile-' + name, ['FullComplete'])
            binaries[name] = OUT / name
            shutil.copy2(binary, binaries[name])
            command = run_full.OUT / ('profile-' + name + '-compile.command.json')
            shutil.copy2(command, OUT / command.name)
    finally:
        # Correctness and subsequent ordinary runs always see the accepted borrowed implementation.
        generate_full(ROOT, BUILD)
    baseline = json.loads((BUILD / 'sieve/build-identity.json').read_text())
    identities = {str(p.relative_to(ROOT)): digest(p) for p in binaries.values()}
    fixtures = [BUILD / 'sieve' / f'{kind}-{limit}.bin'
                for limit in [100000, 10000000] for kind in ['input', 'expected']]
    identities.update({str(p.relative_to(ROOT)): digest(p) for p in fixtures})
    identities[str(control_path.relative_to(ROOT))] = digest(control_path)
    identities[str(Path(__file__).resolve().relative_to(ROOT))] = digest(Path(__file__))
    load_before = os.getloadavg()
    samples = []
    for run in range(2):
        # Reverse the full engine order to expose drift; samples retain wall and process CPU clocks.
        order = list(binaries) if run == 0 else list(reversed(binaries))
        for limit in [100000, 10000000]:
            for engine in order:
                label = f'matched-{run}-{limit}-{engine}'
                result = subprocess.run([str(binaries[engine])], cwd=ROOT,
                    env=environment(engine, limit), capture_output=True, text=True, check=True)
                (OUT / (label + '.log')).write_text(result.stdout)
                rows = [line.split(',') for line in result.stdout.splitlines() if line.startswith('SIEVE,')]
                assert len(rows) == 13
                for index, fields in enumerate(rows):
                    assert fields[1] == engine and int(fields[2]) == limit and int(fields[3]) == index
                    wall, cpu = map(int, fields[4:])
                    assert wall > 0 and cpu > 0
                    samples.append(dict(run=run, limit=limit, engine=engine, sample=index,
                        warmup=index < 3, cpu_ns=cpu, wall_ns=wall))
                print(label, f'{statistics.median(int(r[-1]) for r in rows[3:])/1e6:.3f} ms CPU', flush=True)
    if args.sample:
        # Sampling is separate from all accepted timing runs and retains each complete state cross-check.
        sampler = shutil.which('sample')
        assert sampler, 'macOS sample is required only for --sample'
        for engine, binary in binaries.items():
            with (OUT / (engine + '-sample-run.log')).open('w') as log:
                process = subprocess.Popen([str(binary)], cwd=ROOT,
                    env=environment(engine, 10000000), stdout=log, stderr=subprocess.STDOUT)
                sampled = subprocess.run([sampler, str(process.pid), '4', '1', '-file',
                    str(OUT / (engine + '-sample.txt'))], capture_output=True, text=True)
                (OUT / (engine + '-sample.log')).write_text(sampled.stdout + sampled.stderr)
                execution_status = process.wait()
                assert sampled.returncode == 0 and execution_status == 0
            print('Captured sample:', engine, flush=True)
    for name, checksum in identities.items():
        assert digest(ROOT / name) == checksum, name
    rows = []
    for limit in [100000, 10000000]:
        for engine in binaries:
            measured = [s for s in samples if s['limit'] == limit and s['engine'] == engine and not s['warmup']]
            cpu = [s['cpu_ns'] for s in measured]
            assert len(cpu) == 20
            rows.append(dict(limit=limit, engine=engine, median=statistics.median(cpu), minimum=min(cpu),
                maximum=max(cpu), passes=[statistics.median(s['cpu_ns'] for s in measured if s['run'] == run)
                                         for run in range(2)]))
    report = dict(status='passed', rows=rows, raw=samples, sources=identities, generated=generated,
        controls_sha256=digest(control_path), baseline=baseline,
        load_before=load_before, load_after=os.getloadavg(), sampled=args.sample)
    (OUT / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Matched profile comparison passed.', flush=True)


if __name__ == '__main__':
    main()
