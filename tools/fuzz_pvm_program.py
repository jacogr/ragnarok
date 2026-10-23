#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Build and run bounded checked-Nimony program fuzzing with real failure controls and artifact replay.

Make owns toolchain setup. This opt-in command never changes pins, installs dependencies or schedules CI.
"""
import hashlib
import json
import os
from pathlib import Path
import platform
import re
import shutil
import subprocess
import tempfile
import signal
import time
from native_checks import NativeChecks, ROOT
from native_fixture_contracts import FIXTURE_CONTRACTS
from runtime_provenance import discover_project_sources
from setup_nimony import installed

BUILD = ROOT/'build/tests/pvm-program-fuzz'
SOURCE = ROOT/'tests/fuzz/pvm_program_fuzzer.nim'
DRIVER = ROOT/'tests/fuzz/fuzz_driver.c'
HEADER = ROOT/'tests/fuzz/fuzz_driver.h'
MAX_INPUT = 1024



def source_hashes():
    """Retain current project input bytes as evidence without changing the compiler cache profile."""
    return {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
            for path in sorted(discover_project_sources(ROOT))}


def run_count(value):
    """Require one canonical finite campaign count, large enough to include all frozen seeds plus empty input."""
    if not isinstance(value, str) or re.fullmatch(r'[1-9][0-9]{0,6}', value) is None:
        raise ValueError('FUZZ_RUNS must be canonical decimal in 16..1000000')
    number = int(value)
    if not 16 <= number <= 1000000:
        raise ValueError('FUZZ_RUNS must be in 16..1000000')
    return number


def select_runtime(resource, override=None):
    """Use an explicitly supplied installed archive or exactly one compiler-owned no-main runtime; never download a replacement."""
    if override:
        path = Path(override).resolve()
        if not path.is_file() or path.suffix != '.a':
            raise ValueError('FUZZ_LIBFUZZER must name an existing static no-main libFuzzer archive')
        return path
    paths = sorted(Path(resource).glob('lib/**/libclang_rt.fuzzer_no_main*.a'))
    if len(paths) != 1:
        raise ValueError('Expected one no-main libFuzzer runtime; set FUZZ_LIBFUZZER to an installed archive')
    return paths[0].resolve()


def seed_files():
    """Verify the source-owned frozen corpus before copying it into an invocation-owned mutable coverage corpus."""
    variable, target, required = FIXTURE_CONTRACTS['pvm_program_fuzz']
    if variable != 'RAGNAROK_PVM_PROGRAM_FUZZ' or not target.is_dir() or not 1 <= len(required) <= 5:
        raise ValueError('Invalid program fuzz seed contract')
    paths = []
    for path, expected in required:
        # Input size and exact authored bytes are preflight, never inferred semantic correctness expectations.
        if not path.is_file() or not 1 <= path.stat().st_size <= MAX_INPUT:
            raise ValueError('Missing/oversized program fuzz seed: '+path.name)
        if hashlib.sha256(path.read_bytes()).hexdigest() != expected:
            raise ValueError('Program fuzz seed checksum mismatch: '+path.name)
        paths.append(path)
    return paths


def campaign_observation(output, count):
    """Incomplete, failed or coverage-free output cannot replace a successful bounded libFuzzer run."""
    done = re.findall(r'^#([0-9]+)\s+DONE\s+cov:\s*([0-9]+)\s+ft:\s*([0-9]+)', output, re.MULTILINE)
    if (len(done) != 1 or int(done[0][0]) != count or min(map(int, done[0][1:])) <= 0
            or 'inline 8-bit counters' not in output or 'PC tables' not in output
            or 'ERROR:' in output or 'runtime error:' in output):
        raise ValueError('Incomplete or failed libFuzzer campaign evidence')
    return dict(runs=count, coverage=int(done[0][1]), features=int(done[0][2]))



def run_group(arguments, name, folder, environment, timeout):
    """Join the complete invocation group on timeout, including the driver child, before reporting a failed run."""
    started = time.monotonic()
    process = subprocess.Popen([str(value) for value in arguments], cwd=ROOT, env=environment,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True,
                               start_new_session=True)
    timed_out = False
    try:
        output, _ = process.communicate(timeout=timeout)
    except subprocess.TimeoutExpired:
        timed_out = True
        try:
            os.killpg(process.pid, signal.SIGKILL)
        except ProcessLookupError:
            pass  # The same invocation may have completed between timeout and group retirement.
        output, _ = process.communicate()
    log = Path(folder)/(name+'.log')
    log.write_text(output)
    return dict(command=[str(value) for value in arguments], exit_code=process.returncode,
                elapsed_seconds=round(time.monotonic()-started, 6), timed_out=timed_out,
                log=str(log.relative_to(ROOT)), output=output)


def run():
    """Keep every failure/timeout visible, retire stale success first, and retain exact tools, bytes, flags and generated artifacts."""
    BUILD.mkdir(parents=True, exist_ok=True)
    report = dict(schema=1, status='running', checks=[], controls={})
    result = BUILD/'results.json'
    summary = BUILD/'summary.md'
    summary.unlink(missing_ok=True)

    def save():
        """Partial progress stays explicitly incomplete, including setup or control failure."""
        result.write_text(json.dumps(report, indent=2)+'\n')

    save()
    try:
        # Build identity includes foreign bytes and flags; compiler caches cannot hide a changed runtime or driver.
        count = run_count(os.environ.get('FUZZ_RUNS', '100000'))
        compiler, _ = installed()
        requested = os.environ.get('FUZZ_CLANG', 'clang')
        selected = shutil.which(requested)
        if selected is None:
            raise ValueError('FUZZ_CLANG must name an installed Clang compiler')
        clang = Path(selected).resolve()
        version = subprocess.check_output([clang, '--version'], text=True).strip()
        if 'clang' not in version.lower():
            raise ValueError('Program fuzzing requires Clang instrumentation')
        resource = subprocess.check_output([clang, '--print-resource-dir'], text=True).strip()
        runtime = select_runtime(resource, os.environ.get('FUZZ_LIBFUZZER'))
        seeds = seed_files()
        environment = dict(os.environ)
        environment['PATH'] = str(clang.parent)+os.pathsep+environment.get('PATH', '')
        environment.update(ASAN_OPTIONS='abort_on_error=1:detect_leaks=0', UBSAN_OPTIONS='halt_on_error=1:print_stacktrace=1')
        # No useMalloc/private runtime hook is available on the pinned native allocator; retain its checks and document sanitizer granularity honestly.
        instrumentation = ('-g', '-fno-omit-frame-pointer', '-fno-sanitize-recover=all', '-fsanitize=fuzzer-no-link,address,undefined', '-I'+str(HEADER.parent))
        profile = dict(compiler=str(compiler), clang=str(clang), clang_version=version,
                       runtime=str(runtime), runtime_sha256=hashlib.sha256(runtime.read_bytes()).hexdigest(), flags=instrumentation)
        identity = dict(files=source_hashes(), **profile)
        # Keep source provenance separate; the pinned compiler invalidates imports in this stable tool/flag profile.
        epoch = hashlib.sha256(json.dumps(profile, sort_keys=True).encode()).hexdigest()[:16]
        folder = BUILD/('build-'+epoch)
        folder.mkdir(exist_ok=True)
        checks = NativeChecks(folder, lto=False)
        report.update(identity=identity, runs_requested=count, input_cap=MAX_INPUT, profile='checked release ARC/Clang; address/undefined/coverage; default Nimony allocator; no fine-grained Nim heap/leak claim',
                      sanitizer_environment={key: environment[key] for key in ('ASAN_OPTIONS', 'UBSAN_OPTIONS')},
                      seeds={str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest() for path in seeds})
        save()

        def checked(arguments, name, timeout=60, expected_failure=False):
            """Exit status and diagnostics belong to this exact invocation; expected failures still need independent specific predicates."""
            row = run_group(arguments, name, folder, environment, timeout)
            output = row.pop('output')
            report['checks'].append(row)
            save()
            if row['timed_out'] or (row['exit_code'] == 0) == expected_failure:
                raise RuntimeError(name+' unexpected exit status; see '+row['log'])
            return output, row

        def build(name, defines=(), replay=False):
            """Use the shared checked native builder; C ABI ownership and coverage live only in this test adapter."""
            print('Building program fuzz '+name, flush=True)
            flags = instrumentation if not replay else tuple(flag.replace('fuzzer-no-link,', '') for flag in instrumentation)
            link = ['-fsanitize='+('address,undefined' if replay else 'fuzzer-no-link,address,undefined')]
            if not replay:
                link += [str(runtime), str(folder/'driver.o'), '-lc++' if platform.system() == 'Darwin' else '-lstdc++']
            row, binary = checks.build(compiler, SOURCE, name, cflags=flags, defines=defines, link_flags=link, environment=environment)
            output = row.pop('output')
            report['checks'].append(row)
            save()
            if row['exit_code'] != 0 or 'Error:' in output or 'FAILURE:' in output or not binary.is_file():
                raise RuntimeError(name+' build failed; see '+row['log'])
            return binary

        checked([clang, '-O2', '-std=c11', *instrumentation, '-c', DRIVER, '-o', folder/'driver.o'], 'driver-build')
        replay = build('replay', defines=('fuzzReplay',), replay=True)
        expected = 'PVM program fuzz replay passed: '+str(len(seeds))
        output, _ = checked([replay, *seeds], 'frozen-seed-replay')
        if output.strip() != expected:
            raise RuntimeError('Frozen seed replay produced incomplete evidence')
        if os.environ.get('FUZZ_REPLAY'):
            # A user-selected artifact uses the same bounded reader/properties without starting a coverage campaign.
            artifact = Path(os.environ['FUZZ_REPLAY']).resolve()
            output, _ = checked([replay, artifact], 'artifact-replay')
            if output.strip() != 'PVM program fuzz replay passed: 1':
                raise RuntimeError('Artifact replay produced incomplete evidence')
            report.update(status='checks-passed', mode='replay', artifact=str(artifact))
            return
        invocation = Path(tempfile.mkdtemp(prefix='campaign-', dir=BUILD))
        corpus = invocation/'corpus'
        corpus.mkdir()
        for seed in seeds:
            shutil.copyfile(seed, corpus/seed.name) # Coverage mutations never touch frozen source fixtures or another campaign.
        report['directory'] = str(invocation.relative_to(ROOT))
        save()
        for name, define, diagnostic in [('assertion', 'fuzzAssertionControl', '[Assertion')]:
            # Each independent control must crash, name its expected failure and save a new reproducible input.
            binary = build(name+'-control', defines=(define,))
            artifacts = invocation/(name+'-artifacts')
            artifacts.mkdir()
            output, row = checked([binary, corpus, '-runs=16', '-artifact_prefix='+str(artifacts)+os.sep], name+'-control', expected_failure=True)
            generated = sorted(artifacts.glob('crash-*'))
            if diagnostic not in output or not generated:
                raise RuntimeError(name+' failure/artifact control was not observed; see '+row['log'])
            replayed, _ = checked([replay, generated[0]], name+'-artifact-replay')
            if replayed.strip() != 'PVM program fuzz replay passed: 1':
                raise RuntimeError(name+' control artifact could not be replayed independently')
            report['controls'][name] = dict(passed=True, artifacts=[str(path.relative_to(ROOT)) for path in generated])
            save()
        binary = build('program-fuzzer')
        artifacts = invocation/'artifacts'
        artifacts.mkdir()
        output, _ = checked([binary, corpus, '-runs='+str(count), '-artifact_prefix='+str(artifacts)+os.sep], 'campaign')
        report['campaign'] = campaign_observation(output, count)
        report['binary_sha256'] = hashlib.sha256(binary.read_bytes()).hexdigest()
        report.update(status='checks-passed', mode='campaign')
    except Exception as error:
        # Tooling catches orchestration failures only; Nim property assertions and sanitizer findings are never input refusals.
        report.update(status='failed', error=str(error))
        raise
    finally:
        save()
        lines = ['# Bounded PVM program fuzzing', '', '**Status: '+report['status']+'**']
        if 'campaign' in report:
            observed = report['campaign']
            lines += ['', f"Validated runs: {observed['runs']}; coverage counters: {observed['coverage']}; features: {observed['features']}."]
        if report.get('error'):
            lines += ['', report['error']]
        summary.write_text('\n'.join(lines)+'\n')
        print('Program fuzz '+report['status']+'; report: '+str(result.relative_to(ROOT)), flush=True)


if __name__ == '__main__':
    run()  # Importing helpers never provisions tools, starts workers or mutates a corpus.
