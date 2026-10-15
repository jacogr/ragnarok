#!/usr/bin/env python3
"""Build checked native complete-report drivers and verify the identical independent corpus."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
from report_oracle import ROOT, requests
from mojo_support import compiler
from report_fixtures import fixtures, verify_composition

BUILD = ROOT / 'build/report'


# Build only shared OS observation helpers, independently without LTO; they contain no codec/crypto policy.
def prepare_observers():
    folder = ROOT / 'build/bench'
    folder.mkdir(parents=True, exist_ok=True)
    suffix = 'dylib' if platform.system() == 'Darwin' else 'so'
    shared = '-dynamiclib' if suffix == 'dylib' else '-shared'
    commands = [
        ['clang',shared,'-fPIC','-O2','-Wall','-Wextra','-Werror',ROOT/'interoperability/bench/observe.c','-o',folder/f'libobserve.{suffix}'],
        ['clang',shared,'-fPIC','-O2','-Wall','-Wextra','-Werror',ROOT/'interoperability/mojo/os.c','-o',folder/f'libmojo_os.{suffix}'],
    ]
    with (folder/'report-observers.log').open('w') as log:
        for command in commands:
            # Preserve native helper diagnostics; neither command is a candidate-language repair attempt.
            subprocess.run(list(map(str,command)),cwd=ROOT,stdout=log,stderr=subprocess.STDOUT,check=True)
    recorded = [[str(part) for part in command] for command in commands]
    paths = [ROOT/'interoperability/bench/observe.c',ROOT/'interoperability/mojo/os.c']
    binaries = [folder/f'libobserve.{suffix}',folder/f'libmojo_os.{suffix}']
    receipt = dict(commands=recorded,compiler=subprocess.check_output(['clang','--version'],text=True).strip(),
                   sources={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in paths},
                   binaries={str(path.relative_to(ROOT)):hashlib.sha256(path.read_bytes()).hexdigest() for path in binaries})
    (folder/'report-observers.json').write_text(json.dumps(receipt,indent=2)+'\n')
    return recorded


# Resolve explicit checked compiler commands; Nim uses LTO exclusively for this increment.
def commands(language, instrumented=False):
    suffix = 'dylib' if platform.system() == 'Darwin' else 'so'
    library = ROOT / f'build/crypto/libragnarok_crypto.{suffix}'
    observer = ROOT / f'build/bench/libobserve.{suffix}'
    # Both libraries must be independently built before native report adapters link them.
    assert library.is_file() and observer.is_file(), 'Build the pinned crypto library and shared report observation helpers first'
    name = language + ('-alloc' if instrumented else '')
    if language == 'nim':
        return [['nim', 'c', '--mm:arc', '--cc:clang', '--clang.linkerexe:clang++', '--skipParentCfg',
                 '--skipUserCfg', '-d:release', '--opt:speed', '--passC:-O3', '--passC:-flto', '--passL:-flto',
                 *(['-d:nimAllocStats'] if instrumented else []),
                 *(['--passL:-fuse-ld=lld'] if platform.system() == 'Linux' else []),
                 '--assertions:on', '--boundChecks:on', '--rangeChecks:on', '--fieldChecks:on', '--overflowChecks:on',
                 f'--passL:{library}', f'--passL:{observer}', f'--nimcache:{BUILD / ("nim-cache-alloc" if instrumented else "nim-cache")}',
                 f'--out:{BUILD / name}', ROOT / 'nim/tests/report_driver.nim']]
    if language == 'odin':
        linker = []
        if platform.system() == 'Darwin':
            sdk = subprocess.check_output(['xcrun', '--show-sdk-path'], text=True).strip()
            linker = [f'-extra-linker-flags:-isysroot {sdk}']
        return [['odin', 'build', ROOT / 'odin/report_driver', '-o:speed', '-vet', '-strict-style',
                 *(['-define:REPORT_ALLOCATIONS=true'] if instrumented else []),
                 f'-out:{BUILD / name}', *linker]]
    return [[compiler(), 'build', '-I', ROOT / 'mojo', '-O3', ROOT / 'mojo/tests/report_driver.mojo',
             '-Xlinker', library, '-Xlinker', observer,
             *(['-DREPORT_ALLOCATIONS=true', '-Xlinker', ROOT / f'build/bench/libmojo_os.{suffix}'] if instrumented else []),
             '-o', BUILD / name]]


# Retain exact native compiler logs; prospective trials wrap each of these direct invocations themselves.
def build(language):
    BUILD.mkdir(parents=True, exist_ok=True)
    prepare_observers()
    for index, command in enumerate(commands(language)):
        with (BUILD / f'{language}-build-{index}.log').open('w') as log:
            subprocess.run(list(map(str, command)), cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)


# One identical file request corpus reaches independently implemented production codecs in each candidate.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=('nim', 'odin', 'mojo', 'all'), default='all')
    parser.add_argument('--skip-build', action='store_true')
    args = parser.parse_args()
    BUILD.mkdir(parents=True, exist_ok=True)
    lines, expected = requests()
    folder = BUILD / f'check-{args.language}'
    folder.mkdir(parents=True, exist_ok=True)
    path = folder / 'requests.txt'
    path.write_text('\n'.join(lines) + '\n')
    provider, signed_values = fixtures()
    languages = ('nim', 'odin', 'mojo') if args.language == 'all' else (args.language,)
    for language in languages:
        if not args.skip_build:
            build(language)
        result = subprocess.run([str(BUILD / language), str(path)], capture_output=True, text=True, timeout=180, cwd=ROOT)
        (BUILD / f'{language}-stderr.log').write_text(result.stderr)
        assert result.returncode == 0, (language, result.returncode, result.stderr[-5000:])
        actual = result.stdout.splitlines()
        assert len(actual) == len(expected), (language, len(actual), len(expected), result.stderr[-2000:])
        for index, (got, wanted) in enumerate(zip(actual, expected)):
            assert got == wanted, (language, index, lines[index][:350], got[:350], wanted[:350])
        composition_checks = verify_composition(BUILD/language, folder, signed_values)
        report = {'composition_checks':composition_checks,'fixture_provider':provider,'language':language, 'requests':len(lines), 'request_sha256':hashlib.sha256(path.read_bytes()).hexdigest(),
                  'binary_sha256':hashlib.sha256((BUILD/language).read_bytes()).hexdigest(), 'official_profiles':['tiny','full'],
                  'status':'passed'}
        (BUILD / f'{language}-correctness.json').write_text(json.dumps(report, indent=2)+'\n')
        print(f'PASS {language}: {len(lines)} complete-report requests, official tiny/full, atomic encoders, owner checks and {composition_checks} independent crypto composition checks', flush=True)


# Importing the build-command helper must never run compilers or conformance tests.
if __name__ == '__main__':
    main()
