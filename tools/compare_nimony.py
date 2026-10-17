#!/usr/bin/env python3
"""Bounded checked-LTO migration comparison; isolated Nim 2 history is a control, never a supported target."""
import argparse
import hashlib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tarfile
import time
from setup_nimony import ROOT, installed

BASELINE = 'aea27ad0789ddb0abbea24c3923d0eb192a67e3a'
CASES = ('observer', 'natural decode', 'E4 sequence decode 4096', 'E4 sequence encode 4096',
         'owned bytes decode 64 KiB', 'owned bytes encode 64 KiB', 'Blake2b 64 KiB',
         'Keccak 64 KiB', 'Ed25519 verify 64 KiB')


# Retain exact build commands and their output, failing before any stale binary can become a sample.
def command(arguments, folder, label):
    result = subprocess.run([str(arg) for arg in arguments], cwd=ROOT, capture_output=True, text=True, timeout=180)
    (folder/(label+'.log')).write_text(result.stdout+result.stderr)
    if result.returncode:
        raise RuntimeError(label+' failed; see '+str(folder/(label+'.log')))
    return [str(arg) for arg in arguments]


# Compare isolated historical/current source snapshots with identical workload text and the same native library.
def build(folder, compiler, baseline_compiler):
    source = ROOT/'tests/performance/compiler_workload.nim'
    observer = ROOT/'tests/performance/observe.c'
    suffix = 'dylib' if platform.system() == 'Darwin' else 'so'
    library = folder/('libobserve.'+suffix)
    commands = [command(['clang', '-dynamiclib' if platform.system() == 'Darwin' else '-shared',
                         '-fPIC', '-O2', observer, '-o', library], folder, 'observer-build')]
    crypto = ROOT/('build/crypto/libragnarok_crypto.'+suffix)
    if not crypto.is_file():
        raise ValueError('Run the normal correctness suite to build the pinned crypto library first')
    binaries, hashes = {}, {}
    for label, executable in (('nim2', baseline_compiler), ('nimony', compiler)):
        # Historical code is extracted from Git, never rewritten to accept the current compiler.
        snapshot = folder/label
        snapshot.mkdir(exist_ok=True)
        if label == 'nim2':
            data = subprocess.check_output(['git', 'archive', BASELINE, 'src', 'native/crypto'], cwd=ROOT)
            with tarfile.open(fileobj=io.BytesIO(data)) as archive:
                archive.extractall(snapshot, filter='data')
        else:
            # The migration snapshot matches the current working tree, including staged changes.
            shutil.copytree(ROOT/'src', snapshot/'src', dirs_exist_ok=True)
        (snapshot/'main.nim').write_bytes(source.read_bytes())
        flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundChecks:on',
                 '--passC:-flto', '--passL:-flto', '--passC:-I'+str(ROOT/'native/crypto'),
                 '--passC:-I'+str(snapshot/'src/crypto'), '--passL:'+str(library), '--passL:'+str(crypto),
                 '--passL:-Wl,-rpath,'+str(folder), '--passL:-Wl,-rpath,'+str(crypto.parent)]
        if label == 'nim2':
            # Preserve every Nim 2 checked-release guard; wrapping is not exercised by these valid-input workloads.
            flags += ['--skipParentCfg', '--skipUserCfg', '--assertions:on', '--rangeChecks:on',
                      '--fieldChecks:on', '--overflowChecks:on', '--passC:-O3']
        if platform.system() == 'Linux':
            flags += ['--passL:-fuse-ld=lld'] # Identical Linux LTO linker selection.
        binary = folder/(label+'-bench')
        commands.append(command([executable, 'c', *flags, '--nimcache:'+str(snapshot/'cache'),
                                 '--out:'+str(binary), snapshot/'main.nim'], folder, label+'-build'))
        binaries[label] = binary
        hashes[label] = {str(path.relative_to(snapshot)): hashlib.sha256(path.read_bytes()).hexdigest()
                         for path in sorted((snapshot/'src').rglob('*.nim'))}
    return binaries, dict(commands=commands, source_sha256=hashes,
                         workload_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                         observer_sha256=hashlib.sha256(observer.read_bytes()).hexdigest(),
                         crypto_library_sha256=hashlib.sha256(crypto.read_bytes()).hexdigest())


# Each child reports only native batch time; process startup, compilation and preflight are excluded.
def sample(binary, case, iterations):
    result = subprocess.check_output([str(binary)], text=True, timeout=60,
        env={**os.environ, 'RAGNAROK_BENCH_CASE': str(case), 'RAGNAROK_BENCH_ITERATIONS': str(iterations)})
    values = dict(line.split(' ', 1) for line in result.splitlines())
    return int(values['TIME'])/iterations, int(values['CHECK'])


# Calibrate once, alternate execution order and retain every raw sample without subtracting observer overhead.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--baseline-compiler', type=Path, required=True)
    parser.add_argument('--destination', type=Path, default=ROOT/'build/nimony-comparison')
    args = parser.parse_args()
    compiler, _ = installed()
    baseline_compiler = args.baseline_compiler.resolve()
    baseline_version = subprocess.check_output([str(baseline_compiler), '--version'], text=True)
    if 'Nim Compiler Version 2.2.12 ' not in baseline_version:
        raise ValueError('The isolated historical control requires Nim 2.2.12')
    folder = args.destination.resolve()
    folder.mkdir(parents=True, exist_ok=True)
    binaries, metadata = build(folder, compiler, baseline_compiler)
    report = dict(baseline_revision=BASELINE, current_revision=subprocess.check_output(
                  ['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  environment=dict(platform=platform.platform(), machine=platform.machine(),
                                   clang=subprocess.check_output(['clang', '--version'], text=True)),
                  nim2_version=baseline_version, nimony_version=subprocess.check_output(
                  [str(compiler), '--version'], text=True, stderr=subprocess.STDOUT), metadata=metadata, cases=[])
    for case, name in enumerate(CASES):
        # Use identical odd iteration counts so equivalent result fingerprints remain observable rather than XOR to zero.
        probes = {label: sample(binary, case, 511)[0] for label, binary in binaries.items()}
        iterations = min(20000000, max(1, int(80000000/max(probes.values())))) | 1
        iterations = min(iterations, 19999999)
        values = {label: [] for label in binaries}
        checks = set()
        for repeat in range(7):
            # Alternating process order reduces simple temperature/order bias without claiming host isolation.
            order = ('nim2', 'nimony') if repeat % 2 == 0 else ('nimony', 'nim2')
            for label in order:
                elapsed, check = sample(binaries[label], case, iterations)
                values[label].append(elapsed)
                checks.add(check)
        if len(checks) != 1:
            raise AssertionError((name, 'different result fingerprints', checks))
        medians = {label: statistics.median(samples) for label, samples in values.items()}
        row = dict(name=name, iterations=iterations, samples_ns_per_operation=values, median_ns=medians,
                   nimony_over_nim2=medians['nimony']/medians['nim2'], fingerprint=checks.pop())
        report['cases'].append(row)
        (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
        print(name, medians, 'ratio', row['nimony_over_nim2'], flush=True)
    report['complete'] = True
    (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')


# Performance is opt-in and never changes correctness-suite verdicts or production behavior.
if __name__ == '__main__':
    main()
