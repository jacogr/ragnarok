"""Pinned native Mojo build helpers; no Python runtime is used inside a candidate binary."""
import os
from pathlib import Path
import shutil
import subprocess

ROOT = Path(__file__).resolve().parents[1]
VERSION = 'Mojo 1.1.0 (8189361e)'


# Resolve the project SDK or explicit CI override and reject compiler drift before any evaluation build.
def compiler():
    executable = os.environ.get('RAGNAROK_MOJO')
    # Prefer the hash-pinned isolated installation to an unrelated globally installed version.
    if executable is None:
        local = ROOT / 'build/mojo-env/bin/mojo'
        executable = str(local) if local.is_file() else shutil.which('mojo')
    # Missing tools must be explicit, never an implicit skipped candidate.
    if executable is None:
        raise RuntimeError('Install tools/mojo-requirements.txt into build/mojo-env')
    actual = subprocess.check_output([executable, '--version'], text=True).strip()
    # The build identity is part of the comparison, not just the language's major version.
    if actual != VERSION:
        raise RuntimeError(f'Mojo compiler drift: {actual!r}, expected {VERSION!r}')
    return executable


# Build the same batch adapter in checked optimized/unoptimized modes; retain compiler diagnostics.
def build_codec(build, run):
    # Both modes run the identical corpus; checked Variant access remains a public runtime operation.
    for level in (0, 3):
        binary = build / f'mojo-codec-{level}'
        run([compiler(), 'build', '-I', ROOT / 'mojo', f'-O{level}',
             ROOT / 'mojo/tests/driver.mojo', '-o', binary])


# Append the third candidate only when explicitly built by test_codec.py --mojo.
def codec_commands(build, drivers, family):
    commands = [[driver] for driver in drivers]
    # Existing Nim/Odin-only invocations remain available while Mojo parity is being developed.
    for level in (0, 3):
        binary = build / f'mojo-codec-{level}'
        if binary.is_file():
            # One native adapter dispatches the exact established schema-specific batch protocols.
            commands.append([binary, family])
    return commands


# Build typed native primitive drivers against the exact maintained C/Rust libraries used by Nim.
def build_primitives(build, source, library):
    # The SDK supplies the public FFI only; no generated C protocol code or alternate backend is linked.
    for mode, level in (('debug', 0), ('release', 3)):
        command = [compiler(), 'build', '-I', str(ROOT / 'mojo'), f'-O{level}',
                   str(ROOT / source), '-Xlinker', str(library),
                   '-Xlinker', '-rpath', '-Xlinker', str(library.parent),
                   '-o', str(build / f'mojo-{mode}')]
        # Retain diagnostics separately from the existing pristine dependency build log.
        with (build / f'mojo-{mode}-build.log').open('w') as log:
            subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
    return ['mojo-debug', 'mojo-release']


# Reject deliberate domain/ownership/result misuse for the intended diagnostic, never an import/link failure.
def type_checks(build):
    import json
    cases = json.loads((ROOT / 'mojo/tests/compile_fail/cases.json').read_text())
    with (build / 'mojo-type-checks.log').open('w') as log:
        # Every source is valid formatter syntax but intentionally violates one statically typed API contract.
        for name, needle in cases.items():
            command = [compiler(), 'build', '-I', str(ROOT / 'mojo'), '--emit', 'llvm',
                       str(ROOT / 'mojo/tests/compile_fail' / f'{name}.mojo'),
                       '-o', str(build / 'mojo-negative.ll')]
            result = subprocess.run(command, capture_output=True, text=True)
            log.write(name + '\n' + result.stdout + result.stderr)
            # A missing dependency/module cannot count as evidence of an intended role distinction.
            if result.returncode == 0 or needle not in result.stderr or 'unable to locate module' in result.stderr:
                raise AssertionError((name, needle, result.returncode, result.stderr))
    return len(cases)


# Measure fixed SDK startup threads in a live native readiness window before testing stream/connection growth.
def runtime_threads(binary):
    import tempfile
    import time
    from test_quic import thread_count
    with tempfile.TemporaryDirectory(prefix='ragnarok-mojo-runtime-') as directory:
        path = Path(directory) / 'runtime.log'
        with path.open('w') as log:
            process = subprocess.Popen([str(binary), '--runtime-probe'], stdout=log, stderr=subprocess.STDOUT)
            try:
                deadline = time.monotonic() + 3
                # A crashed or silent SDK cannot establish a passing baseline from process startup alone.
                while 'RUNTIME_READY\n' not in path.read_text():
                    if process.poll() is not None or time.monotonic() >= deadline:
                        raise AssertionError(('Mojo runtime probe', process.returncode, path.read_text()))
                    time.sleep(0.01)
                count = thread_count(process.pid)
                # Require a real running native process, not a pre-main zero/one-thread sample.
                if count is None or count < 1:
                    raise AssertionError(('Mojo native runtime thread count', count))
                if process.wait(timeout=3) != 0:
                    raise AssertionError(('Mojo runtime shutdown', path.read_text()))
                return count
            finally:
                # Failed baseline observations must not leave a native probe process parked in poll.
                if process.poll() is None:
                    process.kill()
                process.wait()


# Compile the small OS-layout helper and maintained native-language LSQUIC adapter, without dependency patches.
def build_quic(build, variant=None):
    import platform
    extension = 'dylib' if platform.system() == 'Darwin' else 'so'
    helper = build / f'libmojo_os.{extension}'
    library = ROOT / 'build/quic' / f'libquic_proof.{extension}'
    flags, extra = [], []
    # Separately labelled composition binaries retain the baseline transport build contract.
    if variant == 'integration':
        flags = ['-DINTEGRATION=true']
        extra = [ROOT / 'build/crypto' / f'libragnarok_crypto.{extension}']
    elif variant == 'offload':
        flags = ['-DOFFLOAD=true']
        extra = [ROOT / 'build/bandersnatch/target/release' / f'libragnarok_bandersnatch.{extension}']
    # C supplies public OS interfaces and ABI layout observations; identity/CE/queue policy stays in Mojo.
    with (build / 'mojo-build.log').open('w') as log:
        subprocess.run(['clang', '-dynamiclib' if extension == 'dylib' else '-shared', '-fPIC', '-O2',
                        '-Wall', '-Wextra', '-Werror', str(ROOT / 'interoperability/mojo/os.c'),
                        '-o', str(helper)], check=True, stdout=log, stderr=subprocess.STDOUT)
        subprocess.run([compiler(), 'build', '-I', str(ROOT / 'mojo'), '-O3',
                        str(ROOT / 'mojo/quic/peer.mojo'), *flags, '-Xlinker', str(helper),
                        *[argument for path in extra for argument in ('-Xlinker', str(path), '-Xlinker', '-rpath', '-Xlinker', str(path.parent))],
                        '-Xlinker', str(library), '-Xlinker', '-rpath', '-Xlinker', str(build),
                        '-o', str(build / 'mojo-peer')], check=True, stdout=log, stderr=subprocess.STDOUT)


# Initialize the explicit candidate set and retain each native runtime's measured fixed thread baseline.
def networking_candidates(build, enabled, skip_build, thread_baselines, variant=None):
    names = ('nim', 'odin', 'mojo') if enabled else ('nim', 'odin')
    # Only an explicitly requested third candidate changes the existing two-language invocation.
    if enabled:
        if not skip_build:
            build_quic(build, variant)
        thread_baselines['mojo'] = runtime_threads(build / 'mojo-peer')
    return names
