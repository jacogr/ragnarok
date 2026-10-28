# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Six native validators must author, remotely adopt, cross an epoch and recover a stopped node."""
from tiny_devnet import exercise
from tiny_devnet_oracle import freeze, verify


def check(binary, folder, progress=print):
    """Independent expectations are materialized before launch; all complete maps are checked after clean shutdown."""
    return exercise(binary,folder,slots=14,restart=True,before_start=freeze,
                    after_stop=verify,progress=progress)


def smoke(binary, folder, progress=print):
    """Two ordinary six-second slots exercise six real processes and all independent map/journal checks in CI."""
    return exercise(binary,folder,slots=2,restart=False,before_start=freeze,
                    after_stop=verify,progress=progress)


def authoring(binary, folder, progress=print):
    """Cold eligible node3 must import the existing head before signing, with whole maps checked independently."""
    return exercise(binary, folder, slots=3, restart=False, late_join=True, before_start=freeze,
                    after_stop=verify, progress=progress)


if __name__ == '__main__':
    # Standalone acceptance uses the built executable; Make owns every build/setup prerequisite.
    import argparse
    from pathlib import Path
    import time
    parser = argparse.ArgumentParser(description=__doc__)
    group = parser.add_mutually_exclusive_group()
    group.add_argument('--smoke', action='store_true')
    group.add_argument('--late-join', action='store_true')
    arguments = parser.parse_args()
    selected = authoring if arguments.late_join else smoke if arguments.smoke else check
    selected(Path('build/ragnarok').resolve(),
          Path('build/tiny-devnet')/time.strftime('check-%Y%m%d-%H%M%S'))
