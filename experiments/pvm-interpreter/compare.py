#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare one qualified working-tree hypothesis against an exact committed experimental parent.

Fresh same-path builds, equal-image controls, full native assertions and both process orders
precede a recorded verdict. Durations retain constructor, cold, reused and publication scopes.
Frozen local fixture/reference paths are explicit dependencies, not silently regenerated inputs.
"""
import argparse
from datetime import datetime, timezone
import hashlib
import json
import os
from pathlib import Path
import shutil
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[2]
SOURCE = Path(__file__).resolve().parent
sys.path.insert(0, str(ROOT/'tools'))
from native_checks import NativeChecks
from setup_nimony import installed, cache_directory
from pvm_prepared_blocks import parse_output

CASES = [('minimal', 1000), ('sieve', 1000), ('memset', 1000), ('sieve', 100000),
         ('minimal', 100000), ('memset', 100000), ('pinky', 1)]
ATTEMPTS = {'pinky': 32055270, 'sieve': 1166742, 'minimal': 2000035, 'memset': 1200349}


def digest(path):
    """Bind every recorded source, fixture and image to actual bytes."""
    return hashlib.sha256(path.read_bytes()).hexdigest()


class DeadlineChecks(NativeChecks):
    """Bound compiler and execution children by the same absolute campaign deadline."""
    def __init__(self, folder, deadline):
        super().__init__(folder)
        self.deadline = deadline

    def command(self, arguments, name, environment=None, cwd=ROOT, timeout=180):
        """A compiler build cannot accidentally inherit a timeout extending beyond the ceiling."""
        remaining = self.deadline-time.time()
        if remaining < 5:
            raise RuntimeError('Autonomous work deadline reached')
        return super().command(arguments, name, environment, cwd, min(timeout, remaining))


class Comparison:
    """Own one serial comparison and its finite deadline; preserve partial evidence on failure."""
    def __init__(self, args):
        self.args = args
        self.folder = ROOT/'build/pvm-interpreter-experiment/comparisons'/args.name
        self.folder.mkdir(parents=True, exist_ok=True)
        self.deadline = datetime.fromisoformat(args.deadline.replace('Z', '+00:00')).timestamp()
        self.checks = DeadlineChecks(self.folder, self.deadline)
        self.report = dict(status='running', baseline=args.baseline, deadline=args.deadline,
                           builds=[], runs=[], controls=[], load_observations=[], source_sha256={})

    def save(self):
        """A partial/failing run never leaves an old passing report behind."""
        (self.folder/'results.json').write_text(json.dumps(self.report, indent=2)+'\n')

    def remaining(self, cap=180):
        """No child is allowed to run beyond the user's eight-hour ceiling."""
        remaining = self.deadline-time.time()
        if remaining < 5:
            raise RuntimeError('Autonomous work deadline reached')
        return min(cap, remaining)

    def seal(self, paths):
        """Add exact inputs without treating unmeasured source names as binary provenance."""
        for path in paths:
            self.report['source_sha256'][str(path.relative_to(ROOT))] = digest(path)
        self.save()

    def verify(self):
        """Any changed input invalidates a comparison rather than mixing revisions."""
        for name, expected in self.report['source_sha256'].items():
            if digest(ROOT/name) != expected:
                raise RuntimeError('Sealed input changed: '+name)

    def build(self):
        """Use one canonical source/output coordinate for every role and fresh-cache repeat."""
        compiler, _ = installed()
        baseline = subprocess.check_output(['git', 'rev-parse', self.args.baseline], cwd=ROOT, text=True).strip()
        self.report.update(baseline=baseline, head=subprocess.check_output(
            ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), compiler=str(compiler))
        canonical = self.folder/'canonical'
        if canonical.exists():
            # This comparison owns only its dedicated generated tree, never an earlier control.
            shutil.rmtree(canonical)
        shutil.copytree(ROOT/'src', canonical/'src')
        shutil.copytree(SOURCE/'benchmarks', canonical/'benchmarks')
        sources = sorted((ROOT/'src').rglob('*.nim'))+sorted(SOURCE.rglob('*.nim'))
        self.seal(sources+[ROOT/'tests/performance/pvm_sieve_clock.h'])
        for role in ('baseline', 'candidate'):
            for path in sorted((SOURCE/'overlay').rglob('*.nim')):
                relative = path.relative_to(SOURCE/'overlay')
                data = subprocess.check_output(['git', 'show', baseline+':'+str(path.relative_to(ROOT))], cwd=ROOT) if role == 'baseline' else path.read_bytes()
                (canonical/relative).write_bytes(data)
            for driver in ('kernel', 'lifecycle', 'doom'):
                images = []
                for repeat in range(2):
                    self.remaining()
                    name = 'canonical-'+driver
                    cache = cache_directory(compiler, self.folder, name)
                    if cache.exists():
                        # Fresh private caches prevent either role borrowing the other's compiled modules.
                        shutil.rmtree(cache)
                    row, binary = self.checks.build(compiler, canonical/'benchmarks'/(driver+'.nim'), name,
                        cflags=['-I'+str(ROOT/'tests/performance')])
                    if row['exit_code'] != 0:
                        raise RuntimeError('Build failed: '+row['log'])
                    image = self.folder/(role+'-'+driver+('-repeat' if repeat else ''))
                    shutil.copy2(binary, image)
                    images.append(image)
                    self.report['builds'].append(dict(role=role, driver=driver, repeat=repeat, build=row))
                    self.save()
                if images[0].read_bytes() != images[1].read_bytes():
                    raise RuntimeError('Fresh same-path images differ: '+role+' '+driver)
                self.seal(images)
                print('PASS fresh equal images '+role+' '+driver, flush=True)
        self.verify()
        self.report['status'] = 'built'
        self.save()

    def observe_load(self, name, position):
        """Record process snapshots without rejecting timings or inspecting other process arguments."""
        result = subprocess.run(['ps', '-A', '-o', 'pid=,ppid=,pcpu=,comm='],
                                capture_output=True, text=True, timeout=self.remaining(10))
        active = []
        for line in result.stdout.splitlines():
            fields = line.split(maxsplit=3)
            if len(fields) != 4:
                continue
            pid, parent, cpu = int(fields[0]), int(fields[1]), float(fields[2])
            if pid != os.getpid() and parent != os.getpid() and cpu >= 1:
                active.append(dict(pid=pid, cpu_percent=cpu, executable=fields[3]))
        self.report.setdefault('load_observations', []).append(dict(run=name, position=position,
            utc=datetime.now(timezone.utc).isoformat(), ps_exit=result.returncode,
            active=sorted(active, key=lambda item: -item['cpu_percent'])[:16]))

    def command(self, arguments, name, env):
        """Retain strict assertion exits and complete output; only validated samples become timings."""
        self.observe_load(name, 'before')
        row = self.checks.command(arguments, name, environment=env, timeout=self.remaining(900))
        self.observe_load(name, 'after')
        text = row.pop('output')
        return row, text

    def small(self, role, guest, limit, order, driver='kernel', negative=None):
        """Time existing complete-state drivers; use the same input/reference for both roles."""
        fixture = self.args.fixtures/guest/str(limit)
        inp, expected = fixture/f'input-{limit}.bin', fixture/f'expected-{limit}.bin'
        self.seal([inp, expected])
        env = dict(os.environ, RAGNAROK_PVM_GUEST=guest, RAGNAROK_PVM_SIEVE_INPUT=str(inp),
                   RAGNAROK_PVM_SIEVE_EXPECTED=str(negative or expected), RAGNAROK_PVM_SIEVE_SAMPLES='13',
                   RAGNAROK_PVM_SIEVE_CLOCK='1', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0', RAGNAROK_PVM_PRICING='prepared')
        if role == 'reference':
            family = {'sieve': 'pvm-sieve', 'pinky': 'pvm-pinky'}.get(guest, 'pvm-guests')
            artifact = ROOT/'tests/fixtures'/family/(guest+'.polkavm')
            self.seal([artifact])
            argv = [self.args.small_reference, '--sieve', artifact, fixture, str(limit), '13']
        elif role == 'master':
            argv = [self.args.master_small]
        else:
            argv = [self.folder/(role+'-'+driver)]
        name = f'{driver}-{order}-{guest}-{limit}-{role}'+('-negative' if negative else '')
        row, text = self.command(argv, name, env)
        if negative:
            if row['exit_code'] == 0 or '[Assertion Failure]' not in text:
                raise RuntimeError('Negative state witness did not reject: '+name)
            return dict(name=name, rejected=True, log=row['log'])
        if row['exit_code'] != 0:
            raise RuntimeError('Comparison failed: '+row['log'])
        samples, prepare = [], None
        if role in ('reference', 'master'):
            parsed = parse_output(text, 'polkavm_interpreter' if role == 'reference' else 'ragnarok_prepared', limit, 13, guest, True)
            samples = [[int(s['cpu_ns'])] for s in parsed['samples']]
        else:
            for line in text.splitlines():
                values = line.split(',')
                if values[0] in ('EXPERIMENTAL_PREPARE', 'PHASE_PREPARE'):
                    prepare = list(map(int, values[2:]))
                elif values[0] == 'EXPERIMENTAL':
                    if int(values[2]) != len(samples): raise RuntimeError('Nonconsecutive samples')
                    ns, nodes, payload, sites, attempts = map(int, values[3:])
                    if nodes*24 != payload or nodes*4 != sites: raise RuntimeError('Invalid cache accounting')
                    if limit == 100000 or guest == 'pinky':
                        if attempts != ATTEMPTS[guest]: raise RuntimeError('Changed source attempts')
                    samples.append([ns, nodes, payload, sites, attempts])
                elif values[0] == 'PHASE':
                    if int(values[2]) != len(samples): raise RuntimeError('Nonconsecutive phases')
                    samples.append(list(map(int, values[3:])))
            if prepare is None: raise RuntimeError('Missing constructor phases')
        if len(samples) != 13 or any(s[0] <= 0 for s in samples) and driver != 'lifecycle':
            raise RuntimeError('Missing validated samples: '+name)
        return dict(role=role, guest=guest, limit=limit, order=order, driver=driver,
                    samples=samples, prepare_ns=prepare, log=row['log'])

    def doom(self, role, phase, order, cold=False, negative=None):
        """Keep host work, reset/publication and full reference checks in their explicit scopes."""
        folder = negative or self.args.doom_fixtures
        env = dict(os.environ, RAGNAROK_PVM_DOOM_INPUT=str(folder),
                   RAGNAROK_PVM_DOOM_ROM=str(self.args.rom), RAGNAROK_PVM_DOOM_TIMING='1',
                   RAGNAROK_PVM_DOOM_PHASE=phase, RAGNAROK_PVM_LOCAL_ONECALL='1' if cold else '0')
        if role == 'reference':
            argv = [self.args.doom_reference, 'run', self.args.doom_program, self.args.rom, folder, phase]
        elif role == 'master':
            argv = [self.args.master_cold if cold and phase == 'init' else self.args.master_doom]
        else:
            argv = [self.folder/(role+'-doom')]
        name = f'doom-{phase}-{order}-{role}'+('-cold' if cold else '')+('-negative' if negative else '')
        row, text = self.command(argv, name, env)
        if negative:
            if row['exit_code'] == 0 or '[Assertion Failure]' not in text:
                raise RuntimeError('DOOM negative witness did not reject')
            return dict(name=name, rejected=True, log=row['log'])
        if row['exit_code'] != 0 or 'DOOM_OK,' not in text:
            raise RuntimeError('DOOM failed: '+row['log'])
        samples, phases, stats, prepare = [], [], [], None
        for line in text.splitlines():
            values = line.split(',')
            if values[0] == 'DOOM_SAMPLE': samples.append(list(map(int, values[3:])))
            elif values[0] == 'DOOM_PHASE': phases.append(list(map(int, values[2:])))
            elif values[0] == 'DOOM_RESIDENT': stats.append(list(map(int, values[2:])))
            elif values[0] == 'DOOM_PREPARE': prepare = list(map(int, values[2:]))
        count = 13 if role == 'reference' or not cold or role == 'master' and phase == 'tick' else 1
        if len(samples) != count or [s[0] for s in samples] != list(range(count)):
            raise RuntimeError('Missing DOOM checked samples')
        if role in ('baseline', 'candidate'):
            if len(phases) != count or len(stats) != count or prepare is None:
                raise RuntimeError('Missing DOOM lifecycle/cache evidence')
            for p, s in zip(phases, stats):
                if p[6] != (1621 if phase == 'init' else 1) or p[7] != (203298231 if phase == 'init' else 12180040):
                    raise RuntimeError('DOOM host/source count changed')
                if s[1] != p[6] or s[2] != 0: raise RuntimeError('Host cache reuse changed')
        return dict(role=role, phase=phase, order=order, cold=cold, driver='doom', samples=samples,
                    phases=phases, host_stats=stats, prepare_ns=prepare, log=row['log'])

    def record(self, row):
        """Resume by stable log identity without duplicating completed process timings."""
        if not any(previous['log'] == row['log'] for previous in self.report['runs']):
            self.report['runs'].append(row)
        self.save()

    def measure(self):
        """Run every declared pair; no timing outlier or busy sample is automatically discarded."""
        self.report = json.loads((self.folder/'results.json').read_text())
        if self.report['status'] != 'built':
            raise RuntimeError('Expected a fresh built comparison; preserve failed cohorts separately')
        self.verify()
        self.seal(sorted(SOURCE.glob('*.py')))
        inputs = [self.args.small_reference, self.args.doom_reference, self.args.doom_program,
                  self.args.rom, self.args.master_small, self.args.master_doom, self.args.master_cold]
        inputs += sorted(p for p in self.args.doom_fixtures.iterdir() if p.is_file())
        self.seal(inputs)
        for role in ('baseline', 'candidate'):
            # Negative fixtures prove active result assertions rather than only a successful happy path.
            fixture = self.args.fixtures/'pinky/1/expected-1.bin'
            wrong = bytearray(fixture.read_bytes()); wrong[8] ^= 1
            bad = self.folder/'wrong-gas.bin'; bad.write_bytes(wrong)
            self.report['controls'].append(self.small(role, 'pinky', 1, 0, negative=bad))
            negative = self.folder/'negative-doom'; negative.mkdir(exist_ok=True)
            for path in self.args.doom_fixtures.iterdir():
                if path.is_file(): shutil.copy2(path, negative/path.name)
            expected = negative/'tick.expected'
            if not expected.exists(): raise RuntimeError('Locate explicit DOOM expected fixture')
            wrong = bytearray(expected.read_bytes()); wrong[8] ^= 1; expected.write_bytes(wrong)
            self.report['controls'].append(self.doom(role, 'tick', 0, cold=True, negative=negative))
        for guest, limit in CASES:
            for order in range(2):
                roles = ['baseline', 'candidate', 'master', 'reference']
                for role in roles if order % 2 == 0 else reversed(roles):
                    self.record(self.small(role, guest, limit, order))
            print('PASS kernel matrix '+guest+' '+str(limit), flush=True)
        for guest, limit in CASES[-4:]:
            for driver in ('kernel', 'lifecycle'):
                for order in range(6):
                    roles = ['baseline', 'candidate']
                    for role in roles if order % 2 == 0 else reversed(roles):
                        self.record(self.small(role, guest, limit, order+2, driver))
            print('PASS six kernel/lifecycle pairs '+guest, flush=True)
        for phase in ('init', 'tick'):
            for cold in (True, False):
                for order in range(2 if cold else 6):
                    roles = ['baseline', 'candidate', 'master', 'reference'] if order < 2 else ['baseline', 'candidate']
                    for role in roles if order % 2 == 0 else reversed(roles):
                        self.record(self.doom(role, phase, order, cold))
                    print('PASS DOOM pair '+phase+' '+str(order)+' cold='+str(cold), flush=True)
        self.verify()
        self.report.update(status='passed', all_inputs_stable=True)
        self.save()


def main():
    """Require explicit baseline, experiment name and deadline before any timed comparison."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--name', required=True)
    parser.add_argument('--baseline', required=True)
    parser.add_argument('--deadline', required=True)
    parser.add_argument('--stage', choices=('build', 'measure'), required=True)
    parser.add_argument('--fixtures', type=Path, default=ROOT/'build/tests/pvm-prepared-blocks')
    old = ROOT/'build/pvm-port-lab'
    large = old/'large-app-qualification'
    parser.add_argument('--doom-fixtures', type=Path, default=large/'prepared')
    parser.add_argument('--rom', type=Path, default=ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad')
    parser.add_argument('--doom-program', type=Path, default=large/'doom.polkavm')
    parser.add_argument('--small-reference', type=Path, default=old/'rust-target/release/ragnarok-pvm-benchmark')
    parser.add_argument('--doom-reference', type=Path, default=large/'rust-target/release/ragnarok-pvm-doom')
    parser.add_argument('--master-small', type=Path, default=old/'contiguous-memory-native/baseline')
    parser.add_argument('--master-doom', type=Path, default=large/'master-doom')
    parser.add_argument('--master-cold', type=Path, default=large/'master-init')
    args = parser.parse_args()
    if not args.name or any(c not in 'abcdefghijklmnopqrstuvwxyz0123456789-' for c in args.name):
        parser.error('Experiment name must be a simple lowercase identifier')
    comparison = Comparison(args)
    try:
        if args.stage == 'build': comparison.build()
        else: comparison.measure()
    except (OSError, ValueError, RuntimeError, AssertionError, subprocess.SubprocessError) as error:
        comparison.report.update(status='failed', error=str(error)); comparison.save()
        print(str(error), file=sys.stderr); raise SystemExit(1)


if __name__ == '__main__':
    main()
