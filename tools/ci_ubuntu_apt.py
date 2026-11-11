# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Write signed archive mirror lists for Ubuntu 26.04 GitHub Actions package setup."""

from pathlib import Path
import platform
import subprocess
import sys
from urllib.parse import urlsplit


KEYRING = Path('/usr/share/keyrings/ubuntu-archive-keyring.gpg')
FALLBACK = 'https://mirrors.edge.kernel.org/ubuntu/'


def primary_resolves(host):
    """Bound the runner's DNS lookup before APT can repeat it per archive object."""
    try:
        return subprocess.run(['getent', 'ahosts', host], timeout=5,
                              stdout=subprocess.DEVNULL, check=False).returncode == 0
    except subprocess.TimeoutExpired:
        return False


def write_sources(directory, release=None, keyring=KEYRING):
    """Write signed lists for both APT commands in a Make-owned temporary directory."""
    release = platform.freedesktop_os_release() if release is None else release
    if release.get('ID') != 'ubuntu' or release.get('VERSION_CODENAME') != 'resolute':
        return None
    if not keyring.is_file():
        raise ValueError('The Ubuntu archive signing keyring is missing')

    directory = directory.resolve()
    directory.chmod(0o755)  # APT's sandbox user needs to traverse the temporary directory.
    mirrors = {
        'ubuntu-ci-archive.mirrors': ('https://archive.ubuntu.com/ubuntu/',
                                      ('resolute', 'resolute-updates', 'resolute-backports')),
        'ubuntu-ci-security.mirrors': ('https://security.ubuntu.com/ubuntu/', ('resolute-security',)),
    }
    lines = []
    for name, (primary, suites) in mirrors.items():
        # Keep the original Ubuntu signing key and pockets across both mirrors.
        destination = directory / name
        host = urlsplit(primary).hostname
        if primary_resolves(host):
            contents = f'{primary}\tpriority:1\n{FALLBACK}\n'
        else:
            print(f'Ubuntu APT primary {host} did not resolve. Using {FALLBACK}', file=sys.stderr)
            contents = f'{FALLBACK}\n'
        destination.write_text(contents)
        destination.chmod(0o644)
        for suite in suites:
            lines.append(f'deb [signed-by={keyring}] mirror+{destination.as_uri()} '
                         f'{suite} main restricted universe multiverse\n')
    # Publish the source only after its two mirror lists are available.
    target = directory / 'ubuntu-ci.list'
    target.write_text(''.join(lines))
    target.chmod(0o644)
    return target


if __name__ == '__main__':
    # Make passes this source path to both APT calls when CI uses the supported runner.
    source = write_sources(Path(sys.argv[1]))
    if source is not None:
        print(source)
