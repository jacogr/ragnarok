# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Write a signed HTTPS Ubuntu source list for pressure-target APT calls, never edit host sources."""
from pathlib import Path
import platform
import re

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT/'build/ci/storage-pressure-https.list'
KEYRING = Path('/usr/share/keyrings/ubuntu-archive-keyring.gpg')


def write_sources(target=TARGET, release=None, machine=None, keyring=KEYRING):
    """Only native amd64 Ubuntu uses archive mirrors; all other hosts keep their original APT policy."""
    target = Path(target)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.unlink(missing_ok=True)
    release = platform.freedesktop_os_release() if release is None else release
    machine = platform.machine() if machine is None else machine
    if release.get('ID') != 'ubuntu' or machine != 'x86_64':
        return False
    codename = release.get('VERSION_CODENAME', '')
    if re.fullmatch('[a-z][a-z0-9]+', codename) is None or not Path(keyring).is_file():
        raise ValueError('Missing Ubuntu release identity or official archive keyring')
    lines = ['# Copyright (c) 2026 Ragnarök contributors',
             '# SPDX-License-Identifier: MIT OR Apache-2.0',
             '# Target-local HTTPS transport; original Ubuntu suites and signature verification.']
    for suite in (codename, codename+'-updates', codename+'-backports', codename+'-security'):
        # Security uses its official archive; suite text cannot inject options or extra repository lines.
        host = 'security.ubuntu.com' if suite.endswith('-security') else 'archive.ubuntu.com'
        lines.append(f'deb [signed-by={keyring}] https://{host}/ubuntu/ {suite} main restricted universe multiverse')
    target.write_text('\n'.join(lines)+'\n')
    return True


# Make alone opts into this source list and supplies it to the normal bounded host-tools APT calls.
if __name__ == '__main__':
    enabled = write_sources()
    print('Pressure APT HTTPS sources: '+str(TARGET) if enabled else 'Pressure APT: original host sources')
