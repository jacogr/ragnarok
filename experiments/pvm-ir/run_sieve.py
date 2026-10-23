#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build one pinned upstream sieve guest and compare three checked execution engines."""
import argparse
import difflib
import io
import json
import os
from pathlib import Path
import platform
import shutil
import statistics
import subprocess
import tarfile
import tomllib

from prepare_shared import generate_shared
from run import BUILD, HERE, ROOT, digest

OUT = BUILD / 'sieve'
MASTER = 'b723f0c1aeaa3b807f062af69004f1fd76352ea5'
LIMITS = [1000, 10000, 100000, 10000000]


def command(args, name, env=None):
    """Retain commands and full diagnostics, propagating build or validation failure."""
    (OUT / (name + '.command.json')).write_text(json.dumps(args, indent=2) + '\n')
    with (OUT / (name + '.log')).open('w') as log:
        subprocess.run(args, cwd=ROOT, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)


def output(args, cwd=ROOT):
    """Read a bounded identity response; never run a shell supplied by dependency content."""
    return subprocess.check_output(args, cwd=cwd, text=True, stderr=subprocess.STDOUT).strip()


def packages(path):
    """Compare exact registry versions and checksums before compiling isolated workspaces."""
    return {(p['name'], p['version'], p['source'], p['checksum'])
            for p in tomllib.loads(path.read_text())['package'] if p.get('source', '').startswith('registry+')}


def resolve(manifest, lock, allowed, toolchain, name):
    """Retain upstream resolution while allowing the smaller workspace's path graph to change."""
    shutil.copyfile(lock, manifest.parent / 'Cargo.lock')
    args = ['rustup', 'run', toolchain, 'cargo', 'metadata', '--format-version', '1',
            '--manifest-path', str(manifest)]
    try:
        # Warm caches avoid unnecessary network access; fallback fetches exact locked packages.
        command([*args, '--offline'], name + '-resolve')
    except subprocess.CalledProcessError:
        command(args, name + '-resolve-online')
    assert packages(manifest.parent / 'Cargo.lock') <= allowed, 'Dependency resolution changed pinned packages'


def generate():
    """Raise only the probe's bounded table capacity and append its private benchmark binding."""
    source = generate_shared(ROOT, BUILD).read_text()
    replacements = {
        "min(4096'u64, uint64(byteLimit))": "min(1048576'u64, uint64(byteLimit))",
        "min(256'u64, uint64(instructionLimit))": "min(65535'u64, uint64(instructionLimit))",
        'capped at 4096 code bytes': 'capped at 1048576 code bytes',
        'capped at 256 decoded operations': 'capped at 65535 decoded operations',
        'At most 256 records': 'At most 65535 records',
    }
    for old, new in replacements.items():
        # Exact matches refuse silent generator drift instead of editing an unintended body.
        assert source.count(old) == 1, old
        source = source.replace(old, new)
    source += '\n' + (HERE / 'sieve/binding.nim.inc').read_text()
    generated = BUILD / 'shared_sieve_step.nim'
    generated.write_text(source)
    (OUT / 'shared-sieve-step.diff').write_text(''.join(difflib.unified_diff(
        (ROOT / 'src/pvm/step.nim').read_text().splitlines(keepends=True),
        source.splitlines(keepends=True), fromfile='src/pvm/step.nim', tofile=str(generated.relative_to(ROOT)))))
    return generated


def build():
    """Freeze master, verify supplied pristine dependencies, and build the three engines and guest."""
    OUT.mkdir(parents=True, exist_ok=True)
    upstream = Path(os.environ.get('POLKAVM_SOURCE', ROOT / 'vendor/polkavm')).resolve()
    pins = json.loads((ROOT / 'spec/polkavm-pins.json').read_text())
    assert output(['git', 'rev-parse', 'HEAD'], upstream) == pins['commit']
    assert not output(['git', 'status', '--porcelain', '--untracked-files=no'], upstream), 'Modified PolkaVM source'
    for name, checksum in pins['source_sha256'].items():
        assert digest(upstream / name) == checksum, name
    compiler = Path(os.environ['NIMONY']).resolve()
    identity = dict(line.split(':', 1) for line in
                    (compiler.parents[1] / 'NIGHTLY.txt').read_text().splitlines() if ':' in line)
    toolchain = json.loads((ROOT / 'spec/toolchain.json').read_text())
    assert identity['nimony-commit'].strip() == toolchain['commit']
    master = output(['git', 'rev-parse', os.environ.get('PVM_SIEVE_MASTER', MASTER) + '^{commit}'])
    archive = subprocess.check_output(['git', 'archive', master, 'src', 'spec/toolchain.json'], cwd=ROOT)
    baseline = OUT / 'master'
    if baseline.exists():
        # This directory contains only a prior generated archive, never a managed checkout.
        shutil.rmtree(baseline)
    baseline.mkdir()
    with tarfile.open(fileobj=io.BytesIO(archive)) as tree:
        tree.extractall(baseline, filter='data')
    assert json.loads((baseline / 'spec/toolchain.json').read_text())['commit'] == toolchain['commit']
    guest_toolchain = tomllib.loads((upstream / 'guest-programs/rust-toolchain.toml').read_text())['toolchain']['channel']
    host_toolchain = json.loads((ROOT / 'spec/bandersnatch-pins.json').read_text())['rust']
    # Provision exact pins only; neither rustup default nor project pins are changed.
    command(['rustup', 'toolchain', 'install', guest_toolchain, '--profile', 'minimal', '--component', 'rust-src'], 'guest-toolchain')
    command(['rustup', 'toolchain', 'install', host_toolchain, '--profile', 'minimal'], 'host-toolchain')
    guest = OUT / 'guest'
    (guest / 'src').mkdir(parents=True, exist_ok=True)
    original_guest = upstream / 'guest-programs/bench-prime-sieve'
    for name in ['main.rs', 'unrolled.rs', 'unrolled_extreme.rs']:
        shutil.copyfile(original_guest / 'src' / name, guest / 'src' / name)
    with (guest / 'src/main.rs').open('a') as file:
        file.write('\n' + (HERE / 'sieve/checked_entry.rs.inc').read_text())
    shutil.copyfile(upstream / 'guest-programs/bench-common.rs', OUT / 'bench-common.rs')
    manifest = (original_guest / 'Cargo.toml').read_text()
    for old, path in [('helper-macros', original_guest / 'helper-macros'),
                      ('../simplealloc', upstream / 'guest-programs/simplealloc'),
                      ('../../crates/polkavm-derive', upstream / 'crates/polkavm-derive')]:
        # TOML strings use JSON escaping, including spaces in a supplied dependency path.
        assert manifest.count('"' + old + '"') == 1
        manifest = manifest.replace('"' + old + '"', json.dumps(str(path)))
    manifest += '''
[workspace]
[workspace.dependencies]
picoalloc = { version = "5.0.0", no-default-features = true }
[workspace.lints.rust]
unexpected_cfgs = "allow"
static_mut_refs = "allow"
[profile.release]
lto = "fat"
panic = "abort"
opt-level = 3
codegen-units = 1
debug = true
'''
    (guest / 'Cargo.toml').write_text(manifest)
    allowed = packages(upstream / 'Cargo.lock')
    resolve(guest / 'Cargo.toml', upstream / 'guest-programs/Cargo.lock',
            allowed | packages(upstream / 'guest-programs/Cargo.lock'), guest_toolchain, 'guest')
    target = upstream / 'crates/polkavm-linker/targets/legacy/riscv64emac-unknown-none-polkavm.json'
    command(['rustup', 'run', guest_toolchain, 'cargo', 'build', '--release', '--locked', '--offline',
             '--manifest-path', str(guest / 'Cargo.toml'), '-Z', 'build-std=core,alloc',
             '--target', str(target), '--bin', 'bench-prime-sieve'], 'guest-build',
            {**os.environ, 'CARGO_TARGET_DIR': str(OUT / 'guest-target')})
    host = OUT / 'host'
    (host / 'src').mkdir(parents=True, exist_ok=True)
    manifest = (ROOT / 'tests/performance/polkavm/Cargo.toml').read_text().replace(
        'ragnarok-pvm-benchmark', 'ragnarok-sieve-reference')
    for crate in ['polkavm', 'polkavm-common']:
        manifest = manifest.replace('"../../../vendor/polkavm/crates/' + crate + '"',
                                    json.dumps(str(upstream / 'crates' / crate)))
    manifest = manifest.replace('[dependencies]', '[dependencies]\nlibc = "=0.2.154"\npolkavm-linker = { path = ' +
                                json.dumps(str(upstream / 'crates/polkavm-linker')) + ' }')
    (host / 'Cargo.toml').write_text(manifest)
    shutil.copyfile(HERE / 'sieve/host.rs', host / 'src/main.rs')
    resolve(host / 'Cargo.toml', upstream / 'Cargo.lock', allowed, host_toolchain, 'host')
    command(['rustup', 'run', host_toolchain, 'cargo', 'build', '--release', '--locked', '--offline',
             '--manifest-path', str(host / 'Cargo.toml'), '--target-dir', str(OUT / 'host-target')], 'host-build')
    elf = OUT / 'guest-target/riscv64emac-unknown-none-polkavm/release/bench-prime-sieve'
    command([str(OUT / 'host-target/release/ragnarok-sieve-reference'), 'link', str(elf), str(OUT)], 'link')
    generated = generate()
    flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed', '--boundchecks:on',
             '--passC:-flto=thin', '--passL:-flto=thin', '--passC:-I' + str(HERE)]
    for engine in ['master', 'prepared']:
        # Separate caches and binaries prevent conditional imports leaking between builds.
        epoch = digest(HERE / 'sieve_probe.nim')[:12] + digest(generated)[:12] + master[:8]
        binary = OUT / ('nim-' + engine)
        command([str(compiler), 'c', *flags, *(['-d:SieveMaster'] if engine == 'master' else []),
                 '--nimcache:' + str(OUT / (engine + '-cache-' + epoch)), '--out:' + str(binary),
                 str(HERE / 'sieve_probe.nim')], engine + '-build')
        assert binary.is_file()
        control = subprocess.run([str(binary)], cwd=ROOT, capture_output=True, text=True,
                                 env={**os.environ, 'PVM_IR_ASSERT_PROBE': '1'})
        (OUT / (engine + '-assertion-control.log')).write_text(control.stdout + control.stderr)
        assert control.returncode != 0 and 'pvm-ir sieve assertion control' in control.stdout + control.stderr
    inputs = [p for p in HERE.glob('sieve/*') if p.is_file()]
    inputs += [HERE / p for p in ['run_sieve.py', 'sieve_probe.nim', 'prepare_shared.py',
                                 'shared_api.nim.inc', 'cpu_clock.h', 'run.py']]
    inputs += list((ROOT / 'src/pvm').glob('*.nim')) + list((ROOT / 'src/codec').glob('*.nim'))
    inputs += [ROOT / 'spec/toolchain.json', ROOT / 'spec/polkavm-pins.json', generated,
               OUT / 'host/Cargo.lock', OUT / 'guest/Cargo.lock', elf,
               OUT / 'sieve.polkavm', OUT / 'nim-master', OUT / 'nim-prepared',
               OUT / 'host-target/release/ragnarok-sieve-reference']
    cpu = output(['sysctl', '-n', 'machdep.cpu.brand_string']) if platform.system() == 'Darwin' else platform.processor()
    report = dict(master=master, head=output(['git', 'rev-parse', 'HEAD']), polkavm=pins['commit'],
                  cpu=cpu, platform=platform.platform(),
                  compiler=output([str(compiler), '--version']), clang=output(['clang', '--version']),
                  guest_rust=output(['rustup', 'run', guest_toolchain, 'rustc', '--version']),
                  host_rust=output(['rustup', 'run', host_toolchain, 'rustc', '--version']),
                  sources={str(p.relative_to(ROOT)): digest(p) for p in inputs},
                  upstream={str(p.relative_to(upstream)): digest(p) for p in
                            [original_guest / 'src/main.rs', original_guest / 'src/unrolled.rs',
                             original_guest / 'src/unrolled_extreme.rs', upstream / 'guest-programs/bench-common.rs',
                             upstream / 'guest-programs/Cargo.lock', upstream / 'Cargo.lock', target]})
    (OUT / 'build-identity.json').write_text(json.dumps(report, indent=2) + '\n')
    print('Build and assertion controls passed.', flush=True)


def measure():
    """Run sequential reversed-order passes, discarding warmups and checking every timed output."""
    identity = json.loads((OUT / 'build-identity.json').read_text())
    for name, checksum in identity['sources'].items():
        assert digest(ROOT / name) == checksum, 'Rebuild changed source: ' + name
    for name in ['results.json', 'summary.md']:
        # Failed attempts cannot leave a passing result at the final report path.
        (OUT / name).unlink(missing_ok=True)
    samples, preparation = [], []
    for run in range(2):
        for limit in LIMITS:
            # Original-size execution is expensive; its lower repetition count is explicit.
            total, warmups = (3, 1) if limit == 10000000 else (13, 3)
            order = ['polkavm', 'master', 'prepared'] if run == 0 else ['prepared', 'master', 'polkavm']
            if run == 1 and limit == LIMITS[0]:
                # First pass always creates the exact fixtures before either Nim engine reads them.
                assert (OUT / f'expected-{limit}.bin').is_file()
            for engine in order:
                print(f'Pass {run + 1}: limit={limit}, engine={engine}, samples={total}', flush=True)
                name = f'run-{run}-{limit}-{engine}'
                env = {**os.environ, 'PVM_SIEVE_INPUT': str(OUT / f'input-{limit}.bin'),
                       'PVM_SIEVE_EXPECTED': str(OUT / f'expected-{limit}.bin'),
                       'PVM_SIEVE_ENGINE': engine, 'PVM_SIEVE_SAMPLES': str(total)}
                args = ([str(OUT / 'host-target/release/ragnarok-sieve-reference'), 'run',
                         str(OUT / 'sieve.polkavm'), str(OUT), str(limit), str(total)]
                        if engine == 'polkavm' else [str(OUT / ('nim-' + engine))])
                fixtures = [OUT / f'{kind}-{limit}.bin' for kind in ['input', 'expected']]
                previous = {str(p): digest(p) for p in fixtures if p.is_file()} if run == 1 else {}
                command(args, name, env)
                for path, checksum in previous.items():
                    # Opposite-order passes must consume byte-identical inputs and reference results.
                    assert digest(Path(path)) == checksum, 'Reference fixture drift: ' + path
                seen = []
                for line in (OUT / (name + '.log')).read_text().splitlines():
                    fields = line.split(',')
                    if fields[0] == 'PREP':
                        preparation.append(dict(run=run, limit=int(fields[1]), wall_ns=int(fields[2]), payload=int(fields[3])))
                    else:
                        assert fields[0] == 'SIEVE' and fields[1] == engine and int(fields[2]) == limit
                        sample, wall, cpu = map(int, fields[3:])
                        assert wall > 0 and cpu > 0
                        seen.append(sample)
                        samples.append(dict(run=run, limit=limit, engine=engine, sample=sample,
                                            warmup=sample < warmups, wall_ns=wall, cpu_ns=cpu))
                assert seen == list(range(total)), (engine, seen)
                (OUT / 'partial.json').write_text(json.dumps(dict(raw=samples, preparation=preparation), indent=2) + '\n')
    rows = []
    for limit in LIMITS:
        for engine in ['polkavm', 'master', 'prepared']:
            group = [s for s in samples if s['limit'] == limit and s['engine'] == engine and not s['warmup']]
            assert len(group) == (4 if limit == 10000000 else 20)
            cpu = [s['cpu_ns'] for s in group]
            rows.append(dict(limit=limit, engine=engine, n=len(group), cpu_median=statistics.median(cpu),
                             cpu_min=min(cpu), cpu_max=max(cpu), wall_median=statistics.median(s['wall_ns'] for s in group),
                             pass_medians=[statistics.median(s['cpu_ns'] for s in group if s['run'] == r) for r in range(2)]))
    for name, checksum in identity['sources'].items():
        assert digest(ROOT / name) == checksum, 'Source changed during measurement: ' + name
    report = dict(status='passed', identity=identity, inventory=json.loads((OUT / 'inventory.json').read_text()),
                  rows=rows, raw=samples, preparation=preparation,
                  fixtures={str(p.name): digest(p) for p in OUT.glob('*.bin')})
    (OUT / 'results.json').write_text(json.dumps(report, indent=2) + '\n')
    lines = ['| Limit | Engine | CPU ms median (min–max) | Samples | Master / engine |',
             '| ---: | --- | ---: | ---: | ---: |']
    for row in rows:
        baseline = next(r for r in rows if r['limit'] == row['limit'] and r['engine'] == 'master')
        lines.append(f"| {row['limit']:,} | {row['engine']} | {row['cpu_median']/1e6:.3f} "
                     f"({row['cpu_min']/1e6:.3f}–{row['cpu_max']/1e6:.3f}) | {row['n']} | "
                     f"{baseline['cpu_median']/row['cpu_median']:.3f}× |")
    summary = '\n'.join(lines) + '\n'
    (OUT / 'summary.md').write_text(summary)
    print(summary, flush=True)


def main():
    """Make exposes build and measurement stages; default invocation performs both."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--build-only', action='store_true')
    parser.add_argument('--measure-only', action='store_true')
    args = parser.parse_args()
    assert not (args.build_only and args.measure_only)
    if not args.measure_only:
        build()
    if not args.build_only:
        measure()


if __name__ == '__main__':
    main()
