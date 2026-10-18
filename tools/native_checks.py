# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Shared checked native compilation and diagnostic capture for independent verification groups."""
from pathlib import Path
import platform
import subprocess
import time
from setup_nimony import cache_directory

ROOT = Path(__file__).resolve().parents[1]


class NativeChecks:
    """Own one group's output directory; callers prepare it before running commands."""

    # Store a group-owned workspace without doing I/O during import or command planning.
    def __init__(self, folder):
        self.folder = Path(folder)

    # Retain exact arguments, elapsed time, exit status and diagnostics, including expected failures.
    def command(self, arguments, name, environment=None, cwd=ROOT):
        started = time.monotonic()
        result = subprocess.run([str(arg) for arg in arguments], cwd=cwd,
                                capture_output=True, text=True, timeout=180, env=environment)
        output = result.stdout+result.stderr
        log = self.folder/(name+'.log')
        log.write_text(output)
        return dict(command=[str(arg) for arg in arguments], exit_code=result.returncode,
                    elapsed_seconds=round(time.monotonic()-started, 6),
                    log=str(log.relative_to(ROOT)), output=output)


    # Keep ARC, Clang, guards, LTO and explicit native ABI profiles identical across verification groups.
    def build(self, compiler, source, name, crypto_library=None, native_libraries=(), cflags=(), quic_library=None, defines=()):
        flags = ['--mm:arc', '--cc:clang', '-d:release', '--opt:speed',
                 '--boundchecks:on', '--passC:-flto', '--passL:-flto']
        if platform.system() == 'Linux':
            # Preserve the established Linux LTO linker choice on that host.
            flags += ['--passL:-fuse-ld=lld']
        if crypto_library is not None:
            # Crypto clients use the maintained public C header and one explicit native library.
            flags += [f'--passC:-I{ROOT/"native/crypto"}', f'--passL:{crypto_library}']
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
        result = self.command([compiler, 'c', *flags, f'--nimcache:{cache_directory(compiler, self.folder, name)}',
                          f'--out:{binary}', source], name+'-build')
        return result, binary



# Print independent verdicts without letting a later successful group hide a failure.
def announce(name, passed):
    print(('PASS ' if passed else 'FAIL ')+name, flush=True)
