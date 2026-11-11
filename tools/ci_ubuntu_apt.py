# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Write signed archive mirror lists for Ubuntu 26.04 GitHub Actions package setup."""

from pathlib import Path
import platform
import sys


KEYRING = Path('/usr/share/keyrings/ubuntu-archive-keyring.gpg')
FALLBACK = 'https://mirrors.edge.kernel.org/ubuntu/'


def write_sources(directory, release=None, keyring=KEYRING):
    """Write signed lists inside a temporary directory owned by the current Make invocation."""
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
        destination.write_text(f'{primary}\tpriority:1\n{FALLBACK}\n')
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
