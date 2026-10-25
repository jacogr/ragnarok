#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare two checked DOOM revisions and identical-source controls on one isolated CI runner.

Make prepares complete state/output goldens first. Source paths, compiler output paths and driver
bytes remain canonical across independent fresh builds. Local --check never reads guest clocks.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import platform
import shutil
import statistics

from native_checks import NativeChecks, ROOT
from pvm_benchmark import cpu_model
from pvm_doom_attribution import BUILD as PREPARED_BUILD, digest, timing_samples
from pvm_guest_compare import git, revision, source_path, unchanged
from pvm_opcode_census import build
from setup_nimony import cache_directory, installed

BUILD = ROOT/'build/tests/pvm-doom-compare'
DRIVER = ('tests/performance/pvm_doom.nim', 'tests/performance/pvm_sieve_clock.h')
GROUPS = (('baseline', 'candidate', 'reference'), ('control-a', 'control-b'))


def endpoint(commit, driver):
    """Read only immutable owned library blobs; both endpoints use the same current checked driver."""
    sources = {}
    for entry in git('ls-tree', '-r', '-z', commit, '--', 'src/pvm',
                     'src/codec/natural.nim').decode().split('\0'):
        if not entry:
            continue  # Git terminates its exact tree listing with one empty entry.
        header, name = entry.split('\t', 1)
        if not name.endswith('.nim'):
            continue  # Non-source files cannot become implicit compiler inputs.
        if header.split()[:2] not in (['100644', 'blob'], ['100755', 'blob']):
            raise ValueError('foreign DOOM comparison source')
        sources[source_path(name)] = git('show', commit+':'+name)
    if 'src/codec/natural.nim' not in sources or len(sources) < 2:
        raise ValueError('incomplete DOOM comparison library')
    sources.update(driver)
    return sources


def summarize(runs):
    """Reparse complete ordered process records before computing warmed CPU medians and ratios."""
    expected = [(phase, group, order, role) for phase in ('init', 'tick')
                for group, roles in enumerate(GROUPS) for order in (0, 1)
                for role in (roles if order == 0 else roles[::-1])]
    if len(runs) != len(expected):
        raise ValueError('incomplete DOOM timing matrix')
    medians = {}
    for row, identity in zip(runs, expected):
        if (type(row['group']) is not int or type(row['order']) is not int
                or (row['phase'], row['group'], row['order'], row['role']) != identity):
            raise ValueError('non-reversed DOOM timing matrix')
        engine = 'reference' if row['role'] == 'reference' else 'native'
        samples = timing_samples(row['stdout'], engine, row['phase'], row['output_bytes'])
        if json.dumps(samples, sort_keys=True) != json.dumps(row['samples'], sort_keys=True):
            raise ValueError('changed DOOM timing samples')
        medians[row['phase'], row['order'], row['role']] = statistics.median(
            s['cpu_ns'] for s in samples[3:])
    result = []
    for phase in ('init', 'tick'):
        for order in (0, 1):
            values = {role: medians[phase, order, role] for roles in GROUPS for role in roles}
            result.append(dict(phase=phase, order=order, cpu_ns=values,
                change_percent=100*(values['candidate']/values['baseline']-1),
                control_percent=100*(values['control-b']/values['control-a']-1),
                baseline_over_reference=values['baseline']/values['reference'],
                candidate_over_reference=values['candidate']/values['reference']))
    return result


def run(base_ref, check_only=False):
    """Build all images first, reject assertion misuse and image drift, then time full verified calls."""
    if not check_only and ((platform.system(), platform.machine()) != ('Linux', 'x86_64')
                           or os.environ.get('GITHUB_ACTIONS') != 'true'):
        raise RuntimeError('DOOM paired timings require isolated Linux x86-64 CI')
    if BUILD.is_symlink() or not BUILD.resolve().is_relative_to((ROOT/'build').resolve()):
        raise ValueError('DOOM comparison must stay in its private build directory')
    BUILD.mkdir(parents=True, exist_ok=True)
    (BUILD/'summary.md').unlink(missing_ok=True)
    (BUILD/'results.json').unlink(missing_ok=True)
    report = dict(status='running', baseline=revision(base_ref), candidate=revision('HEAD'),
                  builds=[], controls=[], runs=[], comparisons=[], cpu=cpu_model())
    checks = NativeChecks(BUILD)
    try:
        admission = json.loads((PREPARED_BUILD/'results.json').read_text())
        if (admission['status'] != 'checks-passed' or admission['warmup_ticks'] != 1320
                or len(admission['controls']) != 6
                or not all(c['passed'] for c in admission['controls'])):
            raise ValueError('DOOM paired preparation must pass complete gameplay admission')
        prepared = PREPARED_BUILD/'prepared'
        reference = ROOT/'build/pvm-doom-rust-target/release/ragnarok-pvm-doom'
        rom = ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'
        blob = PREPARED_BUILD/'doom.polkavm'
        identities = {prepared/name: sha for name, sha in admission['inputs'].items()}
        identities.update({reference: admission['binaries']['reference'],
                           blob: admission['linked_sha256']})
        identities.update({ROOT/name: sha for name, sha in admission['sources'].items()})
        unchanged(identities)
        report['admission'] = dict(head=admission['head'], inputs=admission['inputs'],
                                  outputs=admission['outputs'], golden=admission['golden_rgba_sha256'])
        driver = {name: (ROOT/name).read_bytes() for name in DRIVER}
        sources = {role: endpoint(commit, driver) for role, commit in
                   (('baseline', report['baseline']), ('candidate', report['candidate']))}
        report['sources'] = {role: {name: hashlib.sha256(data).hexdigest()
                                   for name, data in files.items()}
                             for role, files in sources.items()}
        compiler = installed()[0]
        identities[compiler] = digest(compiler)
        canonical = BUILD/'snapshot'
        compilation = BUILD/'compiler'
        compilation.mkdir(exist_ok=True)
        images = {'reference': reference}
        for role in ('baseline', 'candidate', 'control-a', 'control-b'):
            # Controls independently rebuild the candidate through exactly the same source/output/cache paths.
            files = sources['baseline' if role == 'baseline' else 'candidate']
            if canonical.exists():
                shutil.rmtree(canonical)  # This fixed private source snapshot contains no user checkout.
            canonical.mkdir()
            for name, data in files.items():
                target = canonical/name
                target.parent.mkdir(parents=True, exist_ok=True)
                target.write_bytes(data)
            cache = cache_directory(compiler, compilation, 'guest')
            if cache.exists():
                shutil.rmtree(cache)  # Fresh independent builds retain identical compiler paths and no stale generic body.
            row, image = build(NativeChecks(compilation), compiler,
                canonical/DRIVER[0], 'guest',
                cflags=('-g', '-I'+str(canonical/'tests/performance')))
            saved = BUILD/(role+'-build.log')
            shutil.copyfile(ROOT/row['log'], saved)
            row.update(role=role, log=str(saved.relative_to(ROOT)))
            report['builds'].append(row)
            images[role] = BUILD/role
            shutil.copyfile(image, images[role])
            images[role].chmod(0o755)
            unchanged({canonical/name: hashlib.sha256(data).hexdigest() for name, data in files.items()})
        report['binaries'] = {role: digest(path) for role, path in images.items()}
        if len({report['binaries'][r] for r in ('candidate', 'control-a', 'control-b')}) != 1:
            raise ValueError('same-source DOOM images differ')
        if report['sources']['baseline'] == report['sources']['candidate'] and (
                report['binaries']['baseline'] != report['binaries']['candidate']):
            raise ValueError('identical DOOM endpoints produced different images')
        identities.update({path: report['binaries'][role] for role, path in images.items()})
        report['harness'] = {name: digest(ROOT/name) for name in
            ('tools/pvm_doom_compare.py', 'tools/pvm_doom_attribution.py',
             'tools/pvm_guest_compare.py', 'tools/native_checks.py', 'tools/pvm_opcode_census.py')}
        identities.update({ROOT/name: sha for name, sha in report['harness'].items()})
        for role in ('baseline', 'candidate', 'control-a', 'control-b'):
            for phase in ('init', 'tick'):
                # Each independently built image must pass the complete expected state/output before clocks are enabled.
                env = dict(os.environ, RAGNAROK_PVM_DOOM_INPUT=str(prepared),
                    RAGNAROK_PVM_DOOM_PHASE=phase, RAGNAROK_PVM_DOOM_ROM=str(rom),
                    RAGNAROK_PVM_DOOM_ASSERT='0', RAGNAROK_PVM_DOOM_TIMING='0')
                row = checks.command([images[role]], role+'-'+phase+'-positive', environment=env)
                if row['exit_code'] or row['output'] != f'DOOM_OK,native,{phase},{admission["outputs"][phase]["bytes"]}\n':
                    raise RuntimeError('DOOM paired positive control failed: '+role)
            refusal = checks.command([images[role]], role+'-assertions', environment=dict(
                env, RAGNAROK_PVM_DOOM_ASSERT='1'))
            passed = refusal['exit_code'] != 0 and 'doom native assertion control' in refusal['output']
            refusal.pop('output')
            report['controls'].append(dict(role=role, passed=passed, run=refusal))
            if not passed:
                raise RuntimeError('DOOM paired assertion refusal failed: '+role)
        if not check_only:
            for phase in ('init', 'tick'):
                for group, roles in enumerate(GROUPS):
                    for order in (0, 1):
                        for role in (roles if order == 0 else roles[::-1]):
                            # All builds finish first; each process restores and validates thirteen complete calls.
                            unchanged(identities)
                            env = dict(os.environ, RAGNAROK_PVM_DOOM_INPUT=str(prepared),
                                RAGNAROK_PVM_DOOM_PHASE=phase, RAGNAROK_PVM_DOOM_ROM=str(rom),
                                RAGNAROK_PVM_DOOM_ASSERT='0', RAGNAROK_PVM_DOOM_TIMING='1')
                            args = [images[role]]
                            if role == 'reference':
                                args += ['run', blob, rom, prepared, phase]
                            row = checks.command(args, f'timing-{phase}-{group}-{order}-{role}', environment=env, timeout=1800)
                            if row['exit_code']:
                                raise RuntimeError('DOOM paired timing failed: '+role)
                            output = row.pop('output')
                            samples = timing_samples(output, 'reference' if role == 'reference' else 'native',
                                                     phase, admission['outputs'][phase]['bytes'])
                            report['runs'].append(dict(phase=phase, group=group, order=order, role=role,
                                samples=samples, stdout=output, output_bytes=admission['outputs'][phase]['bytes'], run=row))
            report['comparisons'] = summarize(report['runs'])
        unchanged(identities)
        report['status'] = 'checks-passed'
        lines = ['# Paired checked DOOM CPU times', '', f'Baseline: `{report["baseline"]}`',
                 f'Candidate: `{report["candidate"]}`', '',
                 '| Phase | Order | Baseline ms | Candidate ms | Change | Same-image control | Baseline/ref | Candidate/ref |',
                 '| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |']
        for row in report['comparisons']:
            values = row['cpu_ns']
            lines.append(f'| {row["phase"]} | {row["order"]} | {values["baseline"]/1e6:.3f} | {values["candidate"]/1e6:.3f} | {row["change_percent"]:+.3f}% | {row["control_percent"]:+.3f}% | {row["baseline_over_reference"]:.3f}× | {row["candidate_over_reference"]:.3f}× |')
        lines += ['', 'Three warmups plus ten fully validated CPU samples per process; both process orders.',
                  'Candidate and both independently rebuilt control images are byte-identical.',
                  'Initialization and one gameplay tick exclude preparation, serialization and validation.']
        (BUILD/'summary.md').write_text('\n'.join(lines)+'\n')
    except Exception as error:
        report.update(status='failed', error=str(error))
        raise
    finally:
        # A partial run cannot retain a previous successful report.
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')


if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--base', default=os.environ.get('PVM_COMPARE_BASE', 'HEAD^'))
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    run(args.base, args.check)
