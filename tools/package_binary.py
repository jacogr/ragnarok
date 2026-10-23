#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Package the checked peer and maintained native ABIs as a relocatable CI archive.

Make owns compilation and tool provisioning. package validates the pinned host, rewrites only
copied libraries, and smoke-tests a separately unpacked archive before publishing its checksum.
"""
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile

from setup_nimony import ROOT, host_pins

LIBRARIES = ('libragnarok_crypto', 'libragnarok_bandersnatch', 'libquic_proof')
SMOKE_OPTIONS = ('--version', '--help', '--selftest', '--integration-selftest')


class Package:
    """Own retained packaging diagnostics and one explicitly supported platform's loader policy."""

    def __init__(self, system, log):
        self.system = system
        self.log = log

    def command(self, arguments, **options):
        """Retain exact commands and output; any loader, signing or smoke failure is authoritative."""
        arguments = [str(value) for value in arguments]
        self.log.write('+ '+repr(arguments)+'\n')
        self.log.flush()
        result = subprocess.run(arguments, capture_output=True, text=True, timeout=180, **options)
        self.log.write(result.stdout+result.stderr)
        self.log.flush()
        result.check_returncode()
        return result.stdout

    def dependencies(self, path):
        """Read actual binary dependencies rather than assuming every backend emits the same names."""
        if self.system == 'Linux':
            return self.command(['patchelf', '--print-needed', path]).splitlines()
        # otool's first line identifies the inspected binary; remaining lines carry dependency names.
        return [line.strip().split(' (', 1)[0]
                for line in self.command(['otool', '-L', path]).splitlines()[1:]]

    def rpaths(self, path):
        """Read Mach-O runpaths so original compiler/build locations can be removed completely."""
        result = []
        commands = self.command(['otool', '-l', path]).split('cmd LC_RPATH\n')[1:]
        for command in commands:
            # The path record follows cmdsize and terminates before its numeric offset annotation.
            result.append(command.split('path ', 1)[1].split(' (offset ', 1)[0])
        return result

    def relocate(self, binary, libraries):
        """Rewrite every project dependency and use only bundle-relative paths, then sign Mach-O copies."""
        names = {path.name for path in libraries}
        for path in (*libraries, binary):
            # Inspect all copies: crypto can itself depend on the Rust provider's original absolute path.
            for dependency in self.dependencies(path):
                name = Path(dependency).name
                if name in names:
                    if self.system == 'Linux':
                        self.command(['patchelf', '--replace-needed', dependency, name, path])
                    elif dependency != '@rpath/'+name:
                        self.command(['install_name_tool', '-change', dependency, '@rpath/'+name, path])
            if self.system == 'Linux':
                # The executable sits in bin/; every maintained ABI sits together in lib/ragnarok/.
                rpath = '$ORIGIN/../lib/ragnarok' if path == binary else '$ORIGIN'
                self.command(['patchelf', '--set-rpath', rpath, path])
            else:
                if path != binary:
                    self.command(['install_name_tool', '-id', '@rpath/'+path.name, path])
                for rpath in dict.fromkeys(self.rpaths(path)):
                    self.command(['install_name_tool', '-delete_rpath', rpath, path])
                rpath = '@executable_path/../lib/ragnarok' if path == binary else '@loader_path'
                self.command(['install_name_tool', '-add_rpath', rpath, path])
        if self.system == 'Darwin':
            # Editing Mach-O invalidates its existing signature; sign libraries before the executable.
            for path in (*libraries, binary):
                self.command(['codesign', '--force', '--sign', '-', path])

    def verify(self, binary, libraries):
        """Reject undeclared non-system dependencies and any surviving build-directory loader paths."""
        names = {path.name for path in libraries}
        for path in (*libraries, binary):
            for dependency in self.dependencies(path):
                name = Path(dependency).name
                if self.system == 'Linux':
                    # These are distribution-provided runtime ABIs, not bundled project libraries.
                    system = ('libc.so.', 'libm.so.', 'libstdc++.so.', 'libgcc_s.so.',
                              'libpthread.so.', 'libdl.so.', 'librt.so.', 'libz.so.', 'ld-linux-')
                    valid = dependency in names or ('/' not in dependency and dependency.startswith(system))
                else:
                    valid = dependency in {'@rpath/'+name for name in names} or dependency.startswith(
                        ('/usr/lib/', '/System/Library/'))
                if not valid:
                    raise ValueError('Unpackaged native dependency: '+dependency)
            expected = ('$ORIGIN/../lib/ragnarok' if path == binary else '$ORIGIN') if self.system == 'Linux' else (
                '@executable_path/../lib/ragnarok' if path == binary else '@loader_path')
            actual = self.command(['patchelf', '--print-rpath', path]).strip().split(':') if self.system == 'Linux' else self.rpaths(path)
            if actual != [expected]:
                raise ValueError('Unexpected package runpaths: '+repr(actual))


def package(root=ROOT):
    """Publish an archive/checksum only after its copied native closure and relocated peer pass checks."""
    pins = json.loads((root/'spec/toolchain.json').read_text())
    selected = host_pins(pins)
    system = selected['system']
    suffix = '.dylib' if system == 'Darwin' else '.so'
    name = 'ragnarok-'+selected['platform'].replace('_', '-')+'.tar.gz'
    destination = root/'build/dist'
    destination.mkdir(parents=True, exist_ok=True)
    archive_path = destination/name
    checksum_path = destination/(name+'.sha256')
    # A failed rebuild must never leave a previous archive looking current to artifact upload.
    archive_path.unlink(missing_ok=True)
    checksum_path.unlink(missing_ok=True)
    diagnostics = root/'build/ci/binary-package.log'
    diagnostics.parent.mkdir(parents=True, exist_ok=True)
    with diagnostics.open('w') as log, tempfile.TemporaryDirectory(dir=root/'build', prefix='package-') as temporary:
        stage = Path(temporary)/'payload'
        (stage/'bin').mkdir(parents=True)
        library_dir = stage/'lib/ragnarok'
        library_dir.mkdir(parents=True)
        binary = stage/'bin/ragnarok'
        shutil.copy2(root/'build/ragnarok', binary)
        sources = (root/'build/crypto'/(LIBRARIES[0]+suffix),
                   root/'build/bandersnatch/target/release'/(LIBRARIES[1]+suffix),
                   root/'build/quic'/(LIBRARIES[2]+suffix))
        libraries = []
        for source in sources:
            # Copy only the maintained production ABIs; observers, fixtures, keys and toolchains stay out.
            target = library_dir/source.name
            shutil.copy2(source, target)
            libraries.append(target)
        for license_name in ('LICENSE-APACHE', 'LICENSE-MIT'):
            shutil.copy2(root/license_name, stage/license_name)
        checks = Package(system, log)
        checks.relocate(binary, libraries)
        checks.verify(binary, libraries)
        files = {str(path.relative_to(stage)): hashlib.sha256(path.read_bytes()).hexdigest()
                 for path in sorted(stage.rglob('*')) if path.is_file()}
        manifest = dict(platform=selected['platform'], compiler_commit=pins['commit'],
                        revision=checks.command(['git', 'rev-parse', 'HEAD'], cwd=root).strip(),
                        lto='thin', files=files)
        (stage/'manifest.json').write_text(json.dumps(manifest, indent=2)+'\n')
        candidate = Path(temporary)/name
        with tarfile.open(candidate, 'w:gz') as archive:
            # Enumerate a fresh explicit payload, never glob the compiler/build workspace into an artifact.
            for path in sorted(stage.iterdir()):
                archive.add(path, arcname=path.name)
        unpacked = Path(temporary)/'unpacked'
        with tarfile.open(candidate) as archive:
            archive.extractall(unpacked, filter='data')
        relocated = unpacked/'bin/ragnarok'
        checks.verify(relocated, sorted((unpacked/'lib/ragnarok').iterdir()))
        environment = {key: value for key, value in os.environ.items()
                       if not key.startswith(('LD_', 'DYLD_'))}
        for option in SMOKE_OPTIONS:
            # Execute the archive's peer from its own directory, without loader environment overrides.
            checks.command([relocated, option], cwd=unpacked, env=environment)
        shutil.move(candidate, archive_path)
        checksum_path.write_text(hashlib.sha256(archive_path.read_bytes()).hexdigest()+'  '+name+'\n')
    print('Packaged and smoke-tested '+str(archive_path))
    return archive_path


if __name__ == '__main__':
    package()
