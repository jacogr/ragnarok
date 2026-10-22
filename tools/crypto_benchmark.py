#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Compare the maintained BLAKE2b-256 C/Rust bridge with an isolated SIMD candidate on native hosts."""
import csv
import ctypes
import hashlib
import json
import os
from pathlib import Path
import platform
import struct
import subprocess
from native_dependencies import ROOT
from pvm_reference import command
from crypto_benchmark_report import CASES, ENGINES, SAMPLES, VECTOR_LENGTHS, aggregate, parse_output, summarize_benchmark

BUILD = ROOT / 'build/tests/crypto-benchmark'
CRATE = ROOT / 'tests/performance/crypto'
TARGET = ROOT / 'build/crypto-benchmark-rust-target'


# The native driver receives exact independent digests, not another implementation's successful output.
def write_vectors(path):
    """Write a bounded little-endian corpus covering short lengths and compression boundaries."""
    count = len(VECTOR_LENGTHS) * 3
    with path.open('wb') as output:
        output.write(b'B2B1' + struct.pack('<I', count))
        for size in VECTOR_LENGTHS:
            for seed in range(3):
                # Three deterministic patterns include empty, exact-block and large messages.
                data = bytes((i * 131 + i // 7 + seed * 61) & 255 for i in range(size))
                output.write(struct.pack('<I', size) + data + hashlib.blake2b(data, digest_size=32).digest())
    return count


# CPU labels describe this execution host; VM/container exposure can differ from physical hardware.
def cpu_model():
    """Return a bounded CPU model on Linux/macOS without using platform-specific tools in CI YAML."""
    if platform.system() == 'Linux':
        for line in Path('/proc/cpuinfo').read_text().splitlines():
            if line.startswith('model name'):
                return line.split(':', 1)[1].strip()
    if platform.system() == 'Darwin':
        return subprocess.check_output(['sysctl', '-n', 'machdep.cpu.brand_string'], text=True).strip()
    return platform.processor()


# Save partial evidence after each process and refuse stale successes after setup or correctness failure.
def run():
    """Build and validate both providers, retaining fresh evidence for every setup or runtime failure."""
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(status='running', checks=[], samples=[], verified_vectors={})

    def save():
        """Publish this invocation's current evidence before starting another stage."""
        (BUILD / 'results.json').write_text(json.dumps(report, indent=2) + '\n')

    def checked(arguments, name, timeout=900):
        """Retain exit status and complete output; shared command handling kills timed-out process groups."""
        row = command(arguments, name, BUILD, timeout=timeout)
        row['name'] = name
        report['checks'].append(row)
        save()
        if row['exit_code'] != 0:
            raise RuntimeError('Crypto benchmark stage failed: ' + name + '; log: ' + row['log'])
        return Path(row['log']).read_text()

    def measure(engine, mode, size, iterations, name):
        """Keep verification and process setup outside the native monotonic-clock timing region."""
        library, symbol = providers[engine]
        output = checked([driver, library, symbol, mode, size, iterations], name, timeout=180)
        return parse_output(output, mode, size, iterations)

    save()
    for name in ('summary.md', 'samples.csv'):
        # A failed new run must not leave an earlier successful summary or CSV current.
        (BUILD / name).unlink(missing_ok=True)
    try:
        system = platform.system()
        if system not in ('Linux', 'Darwin'):
            raise ValueError('Crypto benchmark requires a native Linux or macOS host')
        rust = json.loads((ROOT / 'spec/bandersnatch-pins.json').read_text())['rust']
        os.environ['RUSTUP_TOOLCHAIN'] = rust
        from build_crypto import dependencies, build_native
        sources = [*sorted(CRATE.rglob('*.rs')), CRATE / 'Cargo.toml', CRATE / 'Cargo.lock',
            CRATE / 'workload.c', ROOT / 'tools/crypto_benchmark.py', ROOT / 'tools/crypto_benchmark_report.py',
            ROOT / 'native/crypto/primitive_bridge.c', *sorted((ROOT / 'native/crypto').glob('*.h')),
            ROOT / 'tools/build_crypto.py', ROOT / 'tools/build_bandersnatch.py',
            ROOT / 'native/bandersnatch/src/primitives.rs',
            ROOT / 'native/bandersnatch/Cargo.toml', ROOT / 'native/bandersnatch/Cargo.lock',
            ROOT / 'spec/crypto-pins.json', ROOT / 'spec/bandersnatch-pins.json',
            ROOT / 'Makefile', ROOT / '.github/workflows/ci.yml']
        report.update(head=subprocess.check_output(['git', 'rev-parse', 'HEAD'], text=True).strip(),
            worktree_dirty=bool(subprocess.check_output(['git', 'status', '--porcelain'])),
            architecture=platform.machine(), cpu=cpu_model(), platform=platform.platform(),
            python=platform.python_version(), oracle=hashlib.blake2b.__module__,
            logical_cpus=os.cpu_count(), load_average_start=os.getloadavg(),
            rustc=checked(['rustup', 'run', rust, 'rustc', '--version', '--verbose'], 'rustc').strip(),
            clang=checked(['clang', '--version'], 'clang').splitlines()[0],
            build_environment={key: os.environ[key] for key in ('RUSTFLAGS', 'CARGO_ENCODED_RUSTFLAGS', 'CFLAGS', 'LDFLAGS') if key in os.environ},
            profile='Production bridge unchanged; Rust release opt-level=3, unwind; native C -O3. No target-cpu=native.',
            pass_orders=[list(ENGINES), list(reversed(ENGINES))], measured_samples_per_pass=SAMPLES,
            warmups_per_case=1, hash_warmups_per_process=64,
            baseline_pins=json.loads((ROOT / 'spec/crypto-pins.json').read_text()), candidate_version='1.0.3',
            sources={str(p.relative_to(ROOT)): hashlib.sha256(p.read_bytes()).hexdigest() for p in sources})
        checked(['rustup', 'run', rust, 'cargo', 'fmt', '--manifest-path', CRATE / 'Cargo.toml', '--', '--check'], 'simd-format')
        checked(['rustup', 'run', rust, 'cargo', 'build', '--release', '--locked', '--offline',
                 '--manifest-path', CRATE / 'Cargo.toml', '--target-dir', TARGET], 'simd-build')
        baseline = build_native(dependencies(False))
        suffix = '.dylib' if system == 'Darwin' else '.so'
        candidate = TARGET / 'release' / ('libragnarok_crypto_benchmark' + suffix)
        providers = {'baseline': (baseline, 'rc_blake2b256'), 'simd': (candidate, 'bench_blake2b256')}
        report['libraries'] = {engine: dict(path=str(path), sha256=hashlib.sha256(path.read_bytes()).hexdigest())
                               for engine, (path, _) in providers.items()}
        feature_probe = ctypes.CDLL(str(candidate)).bench_cpu_features
        feature_probe.restype = ctypes.c_uint32
        bits = feature_probe()
        report['cpu_features'] = dict(avx2=bool(bits & 1), sse41=bool(bits & 2), neon=bool(bits & 4))
        report['expected_simd_dispatch'] = ('AVX2' if bits & 1 else 'SSE4.1' if bits & 2 else 'portable')
        driver = BUILD / 'workload'
        checked(['clang', '-O3', '-std=c11', CRATE / 'workload.c',
                 *(['-ldl'] if system == 'Linux' else []), '-o', driver], 'driver-build')
        fixture = BUILD / 'vectors.bin'
        count = write_vectors(fixture)
        report['fixture_sha256'] = hashlib.sha256(fixture.read_bytes()).hexdigest()
        for engine, (library, symbol) in providers.items():
            # Both providers must pass all independent vectors before either is timed.
            output = checked([driver, library, symbol, 'verify', fixture, count], 'verify-' + engine)
            if output != f'verified {count}\n':
                raise ValueError('Incomplete crypto correctness verification')
            report['verified_vectors'][engine] = count
        for mode, size in CASES:
            initial = 2 if mode == 'tree' else max(1, min(20000, 1000000 // max(size, 64)))
            elapsed = measure('baseline', mode, size, initial, f'calibrate-{mode}-{size}')['elapsed_ns']
            iterations = max(1, min(1000000, int(initial * 50000000 / elapsed)))
            for engine in ENGINES:
                # Whole-workload warmups precede both reversed-order measured passes.
                measure(engine, mode, size, iterations, f'warmup-{mode}-{size}-{engine}')
            for pass_index in range(2):
                order = ENGINES if pass_index == 0 else tuple(reversed(ENGINES))
                for sample in range(SAMPLES):
                    for engine in order:
                        # Equal per-case iteration counts prevent a faster engine from doing less work.
                        result = measure(engine, mode, size, iterations, f'{mode}-{size}-{engine}-{pass_index}-{sample}')
                        report['samples'].append(dict(mode=mode, size=size, engine=engine,
                            pass_index=pass_index, sample=sample, **result))
            print(f'PASS validated {mode} {size}', flush=True)
        report['cases'] = aggregate(report['samples'])
        report['status'] = 'checks-passed'
        report['load_average_end'] = os.getloadavg()
        with (BUILD / 'samples.csv').open('w', newline='') as output:
            writer = csv.DictWriter(output, fieldnames=list(report['samples'][0]))
            writer.writeheader()
            writer.writerows(report['samples'])
    except Exception as error:
        # Setup, build, malformed samples and wrong digests all fail instead of publishing a stale table.
        report.update(status='failed', error=str(error))
        raise
    finally:
        save()
        (BUILD / 'summary.md').write_text(summarize_benchmark(report))
    print(summarize_benchmark(report))


# Make owns provisioning; importing helpers never builds or runs a workload.
if __name__ == '__main__':
    run()
