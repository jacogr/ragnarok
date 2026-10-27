#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Qualify and compare the isolated interpreter, exact current master and pinned interpreted reference.

Make owns provisioning. Fresh canonical builds, complete state assertions, negative controls and
unchanged input seals precede publication. Every sample is retained; no outlier filtering is used.
"""
import argparse
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import sys
import tarfile

ROOT = Path(__file__).resolve().parents[2]
LAB = Path(__file__).resolve().parent
BUILD = ROOT/'build/tests/pvm-interpreter-linux'
sys.path.insert(0, str(ROOT/'tools'))
from native_checks import NativeChecks
from pvm_guest_inputs import prepare_inputs, digest
from pvm_guest_compare import revision, unchanged
from pvm_sieve_report import parse_process_output
from pvm_doom_attribution import run as prepare_doom, BUILD as DOOM, timing_samples
from pvm_benchmark import cpu_model
from setup_nimony import installed, cache_directory

ROLES = ('master', 'candidate', 'reference')
CASES = (('pinky', 1), ('sieve', 100000), ('minimal', 100000), ('memset', 100000))


def integers(fields):
    """Refuse signed, oversized or noncanonical numeric protocol fields before aggregation."""
    if any(not x.isascii() or not x.isdecimal() or len(x) > 19 for x in fields):
        raise ValueError('Invalid phase integer')
    if any(len(x)>1 and x.startswith('0') for x in fields):
        raise ValueError('Noncanonical phase integer')
    values = list(map(int, fields))
    if any(x >= 1 << 63 for x in values):
        raise ValueError('Oversized phase integer')
    return values


def candidate_samples(output, case, doom=False):
    """Require complete ordered lifecycle records and only the declared diagnostic records."""
    preparation = None
    rows = []
    terminal = 0
    residents = 0
    caches = []
    for line in output.splitlines():
        fields = line.split(',')
        kind = fields[0]
        if fields[1:2] != [case]:
            raise ValueError('Foreign phase case')
        if kind == ('DOOM_PREPARE' if doom else 'PHASE_PREPARE'):
            if preparation is not None or len(fields) != (6 if doom else 4):
                raise ValueError('Duplicate/malformed constructor')
            values = integers(fields[2:])
            preparation = values[:2]
        elif kind == ('DOOM_PHASE' if doom else 'PHASE'):
            if len(fields) != (11 if doom else 7):
                raise ValueError('Malformed phase row')
            values = integers(fields[2:])
            if values[0] != len(rows):
                raise ValueError('Unordered phase')
            if doom:
                # Outer call time is separate from subclocks; do not sum nested host clocks into it.
                sample, reset, execution, host, resume, publication, hosts, attempts, nodes = values
                rows.append(dict(sample=sample, reset_ns=reset, publication_ns=publication,
                    execution_ns=execution, host_ns=host, resume_ns=resume,
                    host_calls=hosts, attempts=attempts, nodes=nodes))
            else:
                sample, reset, call, publication, lifecycle = values
                if lifecycle != reset+call+publication or call <= 0:
                    raise ValueError('Inconsistent lifecycle')
                rows.append(dict(sample=sample, reset_ns=reset, cpu_ns=call,
                    publication_ns=publication, lifecycle_ns=lifecycle))
        elif kind == 'PHASE_CACHE' and not doom:
            values = integers(fields[2:])
            if len(values) != 4 or values[0] != len(caches):
                raise ValueError('Unordered cache evidence')
            caches.append(values)
        elif doom and kind == 'DOOM_SAMPLE':
            # This record has engine before case, unlike the phase protocol.
            raise ValueError('Unexpected sample routing')
        elif doom and kind == 'DOOM_RESIDENT':
            values = integers(fields[2:])
            if len(values) != 4 or values[0] != residents:
                raise ValueError('Unordered resident counters')
            residents += 1
        elif doom and kind == 'DOOM_OK':
            terminal += 1
        else:
            raise ValueError('Unexpected phase record')
    if preparation is None or len(rows) != 13 or (doom and (residents != 13 or terminal != 1)):
        raise ValueError('Incomplete phases')
    if not doom:
        if len(caches) != 13:
            raise ValueError('Incomplete cache evidence')
        for row, values in zip(rows,caches):
            row.update(nodes=values[1],preparation_units=values[2],attempts=values[3])
    return dict(preparation_ns=preparation, samples=rows)


def parse_candidate(output, case, doom=False, event_bytes=0):
    """Validate outer-call framing independently from fine-grained lifecycle observations."""
    if not doom:
        return candidate_samples(output, case)
    lines = output.splitlines()
    call_lines = [line.replace('DOOM_SAMPLE,prepared,', 'DOOM_SAMPLE,reference,', 1)
                  for line in lines if line.startswith('DOOM_SAMPLE,')]
    terminal = f'DOOM_OK,prepared,{case},{event_bytes}'
    if lines.count(terminal) != 1:
        raise ValueError('Foreign terminal event count')
    calls = timing_samples('\n'.join(call_lines)+f'\nDOOM_OK,reference,{case},{event_bytes}\n',
                           'reference', case, event_bytes)
    phases = [line for line in lines if not line.startswith(('DOOM_SAMPLE,', 'DOOM_OK,'))]
    # The phase parser checks every remaining line, including sparse publication diagnostics.
    result = candidate_samples('\n'.join(phases)+f'\nDOOM_OK,{case},{event_bytes}\n', case, True)
    for row, call in zip(result['samples'], calls):
        row.update(call)
        row['lifecycle_ns'] = row['reset_ns']+row['cpu_ns']+row['publication_ns']
    return result


def summary(report):
    """Publish complete same-runner CPU tables; cold is sample zero, reused is samples three to twelve."""
    if report['status'] != 'passed':
        return 'Interpreter comparison incomplete: '+report['status']+'\n'
    lines = ['Exact master: `'+report['master']+'`; candidate: `'+report['candidate']+'`.', '',
        'CPU milliseconds. Master uses its existing planned interpreter. Forward/reverse orders; reused medians exclude the first three calls.', '',
        '| Workload | Order | Master call | Ours call | PolkaVM call | Ours / master | Ours / PolkaVM | Ours lifecycle |',
        '|---|---|---:|---:|---:|---:|---:|---:|']
    for case in [x[0] for x in CASES]+['init', 'tick']:
        for order in range(2):
            rows = {r['role']: r for r in report['runs'] if r['case'] == case and r['order'] == order}
            if set(rows) != set(ROLES):
                raise ValueError('Incomplete timing matrix')
            ns = {role: statistics.median(s['cpu_ns'] for s in row['parsed']['samples'][3:])
                  for role, row in rows.items()}
            life = statistics.median(s['lifecycle_ns'] for s in rows['candidate']['parsed']['samples'][3:])
            lines.append(f"| {case} | {order} | {ns['master']/1e6:.3f} | {ns['candidate']/1e6:.3f} | {ns['reference']/1e6:.3f} | {ns['candidate']/ns['master']:.3f} | {ns['candidate']/ns['reference']:.3f} | {life/1e6:.3f} |")
    lines += ['', 'Constructors and first execution (CPU ms). Master calls include their immutable final publication;',
              'ours publishes separately. PolkaVM has call-only timing; no equivalent constructor claim.', '',
              '| Workload | Order | Ours plan / frame | Ours cold call | Ours cold lifecycle + constructors | Master cold call |',
              '|---|---|---:|---:|---:|---:|']
    for row in report['runs']:
        if row['role'] != 'candidate':
            continue  # Only the new engine exposes the detailed constructor/reset/publication boundary.
        parsed = row['parsed']; sample = parsed['samples'][0]; prep = parsed['preparation_ns']
        master = next(r for r in report['runs'] if (r['case'],r['order'],r['role']) == (row['case'],row['order'],'master'))
        lines.append(f"| {row['case']} | {row['order']} | {prep[0]/1e6:.3f} / {prep[1]/1e6:.3f} | {sample['cpu_ns']/1e6:.3f} | {(sum(prep)+sample['lifecycle_ns'])/1e6:.3f} | {master['parsed']['samples'][0]['cpu_ns']/1e6:.3f} |")
    lines += ['', 'Fixtures, decoding and complete-state validation are outside these scopes. All samples,',
              'master gas-plan constructors, image/source hashes and controls remain in results.json.',
              'These are adapted checked workloads, not upstream stock benchmark scores. No hardware-counter claim.']
    lines += ['', '| Workload | Order | Source attempts | Cold / reused nodes |',
              '|---|---|---:|---:|']
    for row in report['runs']:
        if row['role']=='candidate':
            samples = row['parsed']['samples']
            lines.append(f"| {row['case']} | {row['order']} | {samples[-1]['attempts']} | {samples[0]['nodes']} / {samples[-1]['nodes']} |")
    return '\n'.join(lines)+'\n'


class Comparison:
    """Own one private canonical build coordinate and strict complete comparison report."""
    def __init__(self, master):
        BUILD.mkdir(parents=True, exist_ok=True)
        self.checks = NativeChecks(BUILD)
        self.report = dict(status='running', master=revision(master), candidate=revision('HEAD'),
            cpu=cpu_model(), platform=platform.platform(), builds=[], controls=[], runs=[])
        self.identities = {p:digest(p) for p in [
            *sorted(LAB.rglob('*.nim')), *sorted(LAB.glob('*.py')),
            ROOT/'tests/performance/pvm_sieve.nim',ROOT/'tests/performance/pvm_doom.nim',
            ROOT/'tests/performance/pvm_sieve_clock.h',ROOT/'tools/native_checks.py',
            ROOT/'tools/setup_nimony.py',ROOT/'spec/toolchain.json']}
        self.report['compiler_version'] = subprocess.check_output([str(installed()[0]),'--version'],text=True).strip()
        self.report['clang_version'] = subprocess.check_output(['clang','--version'],text=True).splitlines()[0]
        (BUILD/'summary.md').unlink(missing_ok=True)
        self.save()

    def save(self):
        """Persist partial evidence immediately; failed reruns never inherit a successful table."""
        (BUILD/'results.json').write_text(json.dumps(self.report, indent=2)+'\n')

    def command(self, args, name, environment=None):
        """Strict child exits precede parsing; full logs retain the originating diagnostic."""
        before = os.getloadavg()
        row = self.checks.command(args, name, environment=environment, timeout=900)
        row['load_average_before'] = before
        row['load_average_after'] = os.getloadavg()
        output = row.pop('output')
        if row['exit_code']:
            raise RuntimeError('Comparison child failed: '+row['log'])
        return row, output

    def build(self):
        """Repeat each image from fresh private caches at identical paths; library bytes follow exact roles."""
        compiler = installed()[0]
        self.identities[compiler] = digest(compiler)
        self.report['toolchain'] = json.loads((ROOT/'spec/toolchain.json').read_text())
        canonical = BUILD/'snapshot'
        self.images = {}
        # Candidate uses its committed source, then applies only the two tracked runtime overlays.
        for role, commit in (('master', self.report['master']), ('candidate', self.report['candidate'])):
            if canonical.exists():
                shutil.rmtree(canonical)
            raw = subprocess.check_output(['git', 'archive', commit, 'src'], cwd=ROOT)
            canonical.mkdir()
            with tarfile.open(fileobj=io.BytesIO(raw)) as archive:
                archive.extractall(canonical, filter='data')
            drivers = canonical/'benchmarks'; drivers.mkdir()
            if role == 'candidate':
                for path in sorted((LAB/'overlay').rglob('*.nim')):
                    shutil.copy2(path, canonical/path.relative_to(LAB/'overlay'))
                for driver, source in (('kernel', LAB/'benchmarks/lifecycle.nim'), ('doom', LAB/'benchmarks/doom.nim')):
                    shutil.copy2(source, drivers/(driver+'.nim'))
            else:
                for driver, source in (('kernel', ROOT/'tests/performance/pvm_sieve.nim'), ('doom', ROOT/'tests/performance/pvm_doom.nim')):
                    # The same checked public driver is imported from one-level-up source coordinates.
                    text = source.read_text().replace('../../src/', '../src/')
                    if driver == 'doom':
                        # Expose additional master preparation without changing its measured host loop.
                        needle = 'let created = newGasPlan(owner,'
                        assert text.count(needle) == 1
                        text = text.replace(needle, 'let masterPrepare = cpuNanoseconds()\n'+needle)
                        needle = 'let requestedTiming = getEnv('
                        assert text.count(needle) == 1
                        text = text.replace(needle, 'echo "MASTER_PREPARE,", cpuNanoseconds()-masterPrepare\n'+needle)
                    (drivers/(driver+'.nim')).write_text(text)
            self.report.setdefault('sources', {})[role] = {str(p.relative_to(canonical)):digest(p) for p in sorted(canonical.rglob('*.nim'))}
            for driver in ('kernel','doom'):
                images = []
                for repeat in range(2):
                    name = 'canonical-'+driver
                    cache = cache_directory(compiler, BUILD, name)
                    if cache.exists():
                        shutil.rmtree(cache)
                    row, binary = self.checks.build(compiler, drivers/(driver+'.nim'), name,
                        cflags=['-I'+str(ROOT/'tests/performance')])
                    if row['exit_code']:
                        raise RuntimeError('Build failed: '+row['log'])
                    row.pop('output');self.report['builds'].append(dict(role=role,driver=driver,repeat=repeat,build=row))
                    image = BUILD/(role+'-'+driver+('-repeat' if repeat else ''))
                    shutil.copy2(binary,image);images.append(image);self.save()
                if any(digest(canonical/name)!=sha for name,sha in self.report['sources'][role].items()):
                    raise ValueError('Source changed during canonical builds')
                if images[0].read_bytes() != images[1].read_bytes():
                    raise ValueError('Fresh same-source images differ: '+role+' '+driver)
                self.images[role,driver] = images[0]
                self.identities.update({p:digest(p) for p in images})
                print('PASS fresh equal images',role,driver,flush=True)

    def execute(self, role, case, order, prepared, doom=False):
        """Validate both CPU/memory/source state and exact host events before accepting each timing."""
        env = dict(os.environ, RAGNAROK_PVM_PRICING='planned', RAGNAROK_PVM_GUEST=case,
            RAGNAROK_PVM_SIEVE_SAMPLES='13', RAGNAROK_PVM_SIEVE_ASSERT_PROBE='0',
            RAGNAROK_PVM_SIEVE_CLOCK='1', RAGNAROK_PVM_DOOM_TIMING='1',
            RAGNAROK_PVM_DOOM_ASSERT='0', RAGNAROK_PVM_LOCAL_ONECALL='0')
        if doom:
            rom = ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'
            env.update(RAGNAROK_PVM_DOOM_INPUT=str(DOOM/'prepared'), RAGNAROK_PVM_DOOM_PHASE=case,
                       RAGNAROK_PVM_DOOM_ROM=str(rom))
            args = [self.images[role,'doom']] if role != 'reference' else [
                ROOT/'build/pvm-doom-rust-target/release/ragnarok-pvm-doom','run',DOOM/'doom.polkavm',rom,DOOM/'prepared',case]
        else:
            guest,limit,data,expected = prepared
            env.update(RAGNAROK_PVM_SIEVE_INPUT=str(data),RAGNAROK_PVM_SIEVE_EXPECTED=str(expected))
            fixture = ROOT/'tests/fixtures'/({'sieve':'pvm-sieve','pinky':'pvm-pinky'}.get(case,'pvm-guests'))/(case+'.polkavm')
            args = [self.images[role,'kernel']] if role != 'reference' else [
                ROOT/'build/pvm-benchmark-rust-target/release/ragnarok-pvm-benchmark','--sieve',fixture,data.parent,limit,13]
        unchanged(self.identities)
        if order == 0:
            # A positive execution precedes each assertion/state refusal; corrupt fixtures are restored exactly.
            positive, _ = self.command(args,f'{case}-{role}-positive',env)
            self.report['controls'].append(dict(case=case,role=role,kind='positive',run=positive))
            expected_path = DOOM/'prepared'/(case+'.expected') if doom else expected
            original = expected_path.read_bytes()
            for control in ('assertions','state'):
                probe = dict(env)
                if control == 'assertions':
                    probe['RAGNAROK_PVM_DOOM_ASSERT' if doom else 'RAGNAROK_PVM_SIEVE_ASSERT_PROBE'] = '1'
                else:
                    changed = bytearray(original);changed[16] ^= 1;expected_path.write_bytes(changed)
                try:
                    refusal = self.checks.command(args,f'{case}-{role}-{control}',environment=probe,timeout=900)
                    diagnostic = refusal.pop('output')
                    needle = 'assertion control' if control == 'assertions' else ''
                    if refusal['exit_code'] == 0 or needle not in diagnostic:
                        raise ValueError('Negative control did not refuse: '+refusal['log'])
                    self.report['controls'].append(dict(case=case,role=role,kind=control,run=refusal))
                    self.save()
                finally:
                    expected_path.write_bytes(original)
        row, output = self.command(args,f'{case}-{order}-{role}',env)
        raw_output = output
        event_bytes = len((DOOM/'prepared'/(case+'.events')).read_bytes()) if doom else 0
        if role == 'candidate':
            parsed = parse_candidate(output,case,doom,event_bytes)
        elif doom:
            preparation = None
            if role == 'master':
                lines = output.splitlines()
                if not lines or not lines[0].startswith('MASTER_PREPARE,'):
                    raise ValueError('Missing master constructor')
                preparation = integers(lines.pop(0).split(',')[1:])
                if len(preparation) != 1:
                    raise ValueError('Malformed master constructor')
                output = '\n'.join(lines)+'\n'
            parsed = dict(samples=timing_samples(output,'reference' if role=='reference' else 'native',case,event_bytes), preparation_ns=preparation)
        else:
            parsed = parse_process_output(output,'polkavm_interpreter' if role=='reference' else 'ragnarok_planned',limit,guest=case)
        unchanged(self.identities)
        self.report['runs'].append(dict(case=case,order=order,role=role,run=row,stdout=raw_output,parsed=parsed));self.save()
        print('PASS complete state',case,order,role,flush=True)

    def run(self):
        """Use public pinned preparation, qualify every image, then retain both complete process orders."""
        try:
            guests = prepare_inputs(self.checks,BUILD/'inputs')
            self.identities.update(guests['identities'])
            self.report['preparations'] = guests['preparations']
            # Shared admission validates the upstream frame 1320 and all six assertion/state/event controls.
            prepare_doom(check_only=True,warmup=1320)
            admission = json.loads((DOOM/'results.json').read_text())
            if (admission['status'] != 'checks-passed' or len(admission['controls']) != 6
                    or not all(x['passed'] for x in admission['controls'])
                    or admission['warmup_ticks'] != 1320 or not admission.get('golden_rgba_sha256')):
                raise ValueError('Incomplete DOOM admission')
            self.report['doom_admission'] = admission
            self.identities.update({DOOM/'prepared'/name:sha for name,sha in admission['inputs'].items()})
            for path in (ROOT/'build/pvm-doom-rust-target/release/ragnarok-pvm-doom',DOOM/'doom.polkavm',ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'):
                self.identities[path] = digest(path)
            self.build()
            self.report['inputs'] = {str(p.relative_to(ROOT)):sha for p,sha in self.identities.items()}
            for order in range(2):
                for case,limit in CASES:
                    prepared = next(x for x in guests['inputs'] if x[:2]==(case,limit))
                    for role in (ROLES if order==0 else ROLES[::-1]):
                        self.execute(role,case,order,prepared)
                for phase in ('init','tick'):
                    for role in (ROLES if order==0 else ROLES[::-1]):
                        self.execute(role,phase,order,None,True)
            self.report['status'] = 'passed'
            unchanged(self.identities)
            (BUILD/'summary.md').write_text(summary(self.report))
        except Exception as error:
            self.report.update(status='failed',error=str(error))
            raise
        finally:
            self.save()


def main():
    """Resolve master once before building; timing is restricted to the explicitly requested Linux CI job."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--master', default=os.environ.get('PVM_COMPARE_BASE','origin/master'))
    args = parser.parse_args()
    if (platform.system(),platform.machine()) != ('Linux','x86_64') or os.environ.get('GITHUB_ACTIONS') != 'true':
        raise RuntimeError('Linux timing comparison requires its isolated CI runner')
    Comparison(args.master).run()


if __name__ == '__main__':
    main()
