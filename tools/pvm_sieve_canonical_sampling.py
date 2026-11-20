#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Build the exact canonical Sieve pair and sample those ELF images externally."""

from bisect import bisect_right
from collections import Counter
import json
from pathlib import Path
from statistics import median
import subprocess

from pvm_sieve_phase_diagnostic import (BUILD, FIRST_WARM, REVISIONS, ROOT, WORKLOADS,
                                       prepare_inputs, sample)
from pvm_ci_performance import PairedRunner, PerformanceRunner, digest
from pvm_jit_platform import native_defines
from setup_nimony import installed

RAW_PAIRS = 11
PROFILE_PAIRS = 8
PRIOR = dict(baseline='ab6b88b6fe1a6ded5db19c52dedb22321dbd666ff8455478b3c8ded0dcefd32a',
             candidate='1382fba648d5a8cc59f6917af2561e895a29a023f5fa6051875e851c5a1bd11d')


class SieveImages(PerformanceRunner):
    """Use the canonical source switch and build method without declaring a full matrix result."""

    def __init__(self):
        super().__init__(BUILD, 'micro')
        self.source = BUILD/'paired-source'
        self.baseline = REVISIONS['baseline']
        self.report.update(candidate=REVISIONS['candidate'], source_manifests={})
        self.compiler, _ = installed()
        self.defines = native_defines()
        if self.defines != ['pvmX86Jit']:
            raise RuntimeError('This sampler requires Linux x86-64')
        self.cases = [case for case in self.cases if case['case_id'] in {f'sieve-{n}' for n in WORKLOADS}]
        if len(self.cases) != len(WORKLOADS):
            raise RuntimeError('Canonical Sieve inventory changed')
        self.rust = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']

    def images_for_sieve(self):
        """Fetch the candidate identity early, then invoke the existing paired builder unchanged."""
        self.command(['git', 'fetch', '--no-tags', '--depth=1', 'origin', REVISIONS['candidate']],
                     'sieve-candidate-fetch')
        first, second = PairedRunner.comparison_images(self)
        return dict(baseline=first['guest'], candidate=second['guest'])


def symbols(runner, image, role):
    """Retain sized text symbols at their canonical ELF coordinates."""
    result = runner.command(['nm', '-nS', '--defined-only', image], f'{role}-symbols')
    shaped = []
    for line in result['output'].splitlines():
        fields = line.split()
        if len(fields) == 4 and fields[2] in {'t', 'T'}:
            start, size = int(fields[0], 16), int(fields[1], 16)
            if size:
                shaped.append((start, start+size, fields[3]))
    if not shaped:
        raise RuntimeError(f'No sized text symbols for {role}')
    return shaped


def decode_pcs(file, result, text_ranges):
    """Select only PCs inside the benchmark's own measured warm call brackets."""
    base = None
    clocks, pcs, executable_maps = [], [], []
    for line in file.read_text().splitlines():
        if line.startswith('BASE,'):
            base = int(line.split(',')[1], 16)
        elif line.startswith('DROPPED,') and line != 'DROPPED,0':
            raise RuntimeError(f'Incomplete PC capture in {file.name}')
        elif line.startswith('CLOCK,'):
            clocks.append(int(line.split(',')[1]))
        elif line.startswith('PC,'):
            _, cpu, pc = line.split(',')
            pcs.append((int(cpu), int(pc, 16)))
        elif 'r-x' in line and '/memfd:ragnarok-pvm-x86-code' in line:
            begin, end = line.split()[0].split('-')
            executable_maps.append((int(begin, 16), int(end, 16)))
    if base is None or not executable_maps:
        raise RuntimeError(f'Missing mapped native image in {file.name}')
    starts = [entry[0] for entry in text_ranges]
    clock_ids = set(clocks)
    previous_end = -1
    total_cpu = 0
    counts = Counter()
    for warm in result['samples'][FIRST_WARM:]:
        duration = warm['cpu_ns']
        options = {end for end in clocks if end-duration >= previous_end and end-duration in clock_ids}
        if len(options) != 1:
            raise RuntimeError(f'Ambiguous public CPU interval in {file.name}, sample {warm["sample"]}')
        end = options.pop()
        begin = end-duration
        for at, pc in pcs:
            if not begin <= at < end:
                continue
            offset = pc-base
            index = bisect_right(starts, offset)-1
            if index >= 0 and offset < text_ranges[index][1]:
                counts[text_ranges[index][2].split('_', 1)[0]] += 1
            elif any(low <= pc < high for low, high in executable_maps):
                counts['native bitmap mapping'] += 1
            else:
                counts['outside executable symbols'] += 1
        previous_end = end
        total_cpu += duration
    total = sum(counts.values())
    if total < 100 or not counts['native bitmap mapping']:
        raise RuntimeError(f'Incomplete warm CPU samples in {file.name}')
    return dict(counts=dict(counts), total=total, cpu_ns=total_cpu)


def publish(raw, profiles, hashes):
    """Publish ordinary paired timings plus a separate sample-based attribution."""
    rows = ['# Canonical Sieve binaries and external PC samples', '',
            '| Size | Baseline warm ms | Candidate warm ms | Median paired CPU delta | Slower pairs |',
            '| ---: | ---: | ---: | ---: | ---: |']
    for limit in WORKLOADS:
        a = [raw[limit, i, 'baseline']['warm_cpu_ns'] for i in range(RAW_PAIRS)]
        b = [raw[limit, i, 'candidate']['warm_cpu_ns'] for i in range(RAW_PAIRS)]
        relative = median((y/x-1)*100 for x,y in zip(a,b))
        rows.append(f'| {limit} | {median(a)/1e6:.5f} | {median(b)/1e6:.5f} | {relative:+.2f}% | '
                    f'{sum(y>x for x,y in zip(a,b))}/{RAW_PAIRS} |')
    rows.extend(['', '| Role | Matches previous executable SHA-256 | Warm profiled samples |',
                 '| --- | --- | ---: |'])
    for role, hashed in hashes.items():
        total = sum(profiles[role, i]['total'] for i in range(PROFILE_PAIRS))
        rows.append(f'| {role} | {hashed == PRIOR[role]} | {total} |')
    combined = {role: sum((Counter(profiles[role, i]['counts']) for i in range(PROFILE_PAIRS)), Counter())
                for role in hashes}
    rows.extend(['', '| Symbol or mapping | Baseline samples | Candidate samples |',
                 '| --- | ---: | ---: |'])
    for name, _ in (combined['baseline']+combined['candidate']).most_common(20):
        rows.append(f'| {name} | {combined["baseline"][name]} | {combined["candidate"][name]} |')
    (BUILD/'summary.md').write_text('\n'.join(rows)+'\n')
    data = dict(revisions=REVISIONS, binary_sha256=hashes, prior_binary_sha256=PRIOR,
        raw=[dict(size=k[0], pair=k[1], role=k[2], **v) for k,v in raw.items()],
        profiles=[dict(role=k[0], pair=k[1], **v) for k,v in profiles.items()])
    (BUILD/'sieve-canonical-samples.json').write_text(json.dumps(data, indent=2)+'\n')


def order(pair):
    """Alternate to remove a fixed version-order bias."""
    return ('baseline', 'candidate') if pair % 2 == 0 else ('candidate', 'baseline')


def main():
    """Time both canonical variants first, then attach a sampler to the exact retained binaries."""
    BUILD.mkdir(parents=True, exist_ok=True)
    runner = SieveImages()
    environments = prepare_inputs(runner)
    images = runner.images_for_sieve()
    hashes = {role: digest(image) for role, image in images.items()}
    raw = {}
    for size, env in environments.items():
        for pair in range(RAW_PAIRS):
            for role in order(pair):
                raw[size, pair, role] = sample(runner, images[role], env, size, 'raw', role, pair)
            if raw[size, pair, 'baseline']['work'] != raw[size, pair, 'candidate']['work']:
                raise RuntimeError(f'Unmatched native attempts at {size}, pair {pair}')
            print(f'Completed canonical {size} pair {pair+1}/{RAW_PAIRS}', flush=True)
    library = BUILD/'sieve-pc-sample.so'
    runner.command(['clang', '-O2', '-Wall', '-Wextra', '-Werror', '-shared', '-fPIC',
                    ROOT/'tools/pvm_sieve_pc_sample.c', '-o', library, '-ldl'], 'sampler-build')
    tables = {role: symbols(runner, image, role) for role, image in images.items()}
    profiles = {}
    size = WORKLOADS[-1]
    for pair in range(PROFILE_PAIRS):
        for role in order(pair):
            trace = BUILD/f'pc-{role}-{pair}.log'
            environment = dict(environments[size], LD_PRELOAD=str(library), PVM_SIEVE_PC_LOG=str(trace))
            result = sample(runner, images[role], environment, size, 'sampled', role, pair)
            if result['work'] != raw[size, pair, role]['work']:
                raise RuntimeError('Sampling changed native work')
            profiles[role, pair] = decode_pcs(trace, result, tables[role])
        print(f'Completed external sample pair {pair+1}/{PROFILE_PAIRS}', flush=True)
    runner.verify()
    publish(raw, profiles, hashes)


if __name__ == '__main__':
    main()
