# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Shared checked native compilation and diagnostic capture for independent verification groups.

Exposes NativeChecks and announce for checked compilation, process execution and retained
diagnostics.
"""
from pathlib import Path
from contextlib import contextmanager, nullcontext
import fcntl
import hashlib
import json
import platform
import subprocess
import time
from setup_nimony import cache_directory
from native_source_identity import source_identity

ROOT = Path(__file__).resolve().parents[1]


class NativeChecks:
    """Own one group's output directory; callers prepare it before running commands."""

    # Store a group-owned workspace without doing I/O during import or command planning.
    def __init__(self, folder, reuse_builds=False, lto=True):
        self.folder = Path(folder)
        self.reuse_builds = reuse_builds
        if lto not in (False, True, 'thin'):
            raise ValueError('Native LTO must be disabled, full or thin')
        self.lto = lto
        self.builds = []

    # Retain exact arguments, elapsed time, exit status and diagnostics, including expected failures.
    def command(self, arguments, name, environment=None, cwd=ROOT, timeout=180):
        started = time.monotonic()
        result = subprocess.run([str(arg) for arg in arguments], cwd=cwd,
                                capture_output=True, text=True, timeout=timeout, env=environment)
        output = result.stdout+result.stderr
        log = self.folder/(name+'.log')
        log.write_text(output)
        return dict(command=[str(arg) for arg in arguments], exit_code=result.returncode,
                    elapsed_seconds=round(time.monotonic()-started, 6),
                    log=str(log.relative_to(ROOT)), output=output)


    # Only opted-in serial groups share intermediates; a killed/failed build must release the lock.
    @contextmanager
    def _build_lock(self, compiler):
        path = cache_directory(compiler, self.folder, 'builds').parent/'builds.lock'
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open('a') as lock:
            # Linux/macOS release descriptor locks even when a command or parent process fails.
            fcntl.flock(lock, fcntl.LOCK_EX)
            try:
                yield
            finally:
                fcntl.flock(lock, fcntl.LOCK_UN)


    # Keep ARC, Clang and checks fixed; production-like callers retain full LTO by default.
    def build(self, compiler, source, name, crypto_library=None, native_libraries=(), cflags=(), quic_library=None, defines=()):
        flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
                 '--boundchecks:on']
        if self.lto:
            # Units/contracts may opt out of link-time optimization without disabling runtime checks.
            option = '-flto=thin' if self.lto == 'thin' else '-flto'
            flags += ['--passC:'+option, '--passL:'+option]
        if platform.system() == 'Linux':
            # Preserve the established Linux LLD linker choice on that host.
            flags += ['--passL:-fuse-ld=lld']
        if crypto_library is not None:
            # Crypto clients use the maintained public C header and one explicit native library.
            flags += [f'--passC:-I{ROOT/"native/crypto"}', f'--passL:{crypto_library}',
                      f'--passL:-Wl,-rpath,{crypto_library.parent}']
        if quic_library is not None:
            # QUIC clients use the unchanged maintained bridge and its public headers.
            flags += [f'--passC:-I{ROOT/"native/quic"}', f'--passL:{quic_library}',
                      f'--passL:-Wl,-rpath,{quic_library.parent}']
        if native_libraries:
            # Native Bandersnatch clients use one maintained header and explicit original/observer library paths.
            flags += [f'--passC:-I{ROOT/"native/bandersnatch"}']
            for library in native_libraries:
                flags += [f'--passL:{library}', f'--passL:-Wl,-rpath,{library.parent}']
        flags += ['-d:'+name for name in defines]
        flags += ['--passC:'+flag for flag in cflags]
        binary = self.folder/name
        # The pinned compiler can retain old generic call bodies after an imported helper changes arity.
        # Reuse only within this exact owned source epoch, including non-shared benchmark caches.
        sources = source_identity(ROOT, source)
        cache_name = name+'-sources-'+sources
        if self.reuse_builds:
            # Identical source epochs, flags and native bytes share frontend work; each main keeps its own binary.
            inputs = [Path(path).resolve() for path in (crypto_library, quic_library, *native_libraries)
                      if path is not None]
            includes = [('crypto', crypto_library is not None), ('quic', quic_library is not None),
                        ('bandersnatch', bool(native_libraries))]
            for directory, used in includes:
                # Header content changes must invalidate a profile just like changed native libraries.
                if used:
                    inputs.extend(sorted((ROOT/'native'/directory).glob('*.h')))
            profile = dict(directory=str(Path(source).resolve().parent), flags=flags, sources=sources,
                           native={str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in inputs})
            identity = hashlib.sha256(json.dumps(profile, sort_keys=True).encode()).hexdigest()[:16]
            cache_name = 'profile-'+identity
        with self._build_lock(compiler) if self.reuse_builds else nullcontext():
            # Other verification groups retain their existing per-build cache and scheduling behavior.
            if self.reuse_builds:
                print('BUILD '+name, flush=True)
            result = self.command([compiler, 'c', *flags,
                                   f'--nimcache:{cache_directory(compiler, self.folder, cache_name)}',
                                   f'--out:{binary}', source], name+'-build')
            if self.reuse_builds:
                print(f'Completed build {name} in {result["elapsed_seconds"]:.2f}s', flush=True)
        self.builds.append(result)
        return result, binary



# Print independent verdicts without letting a later successful group hide a failure.
def announce(name, passed):
    print(('PASS ' if passed else 'FAIL ')+name, flush=True)
