#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Format only the isolated experiment; production sources and reference drivers stay unchanged."""
import argparse
from pathlib import Path
from formatting import nim, rust


def main():
    """Apply or verify pinned formatting for both generated and handwritten source files."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent
    changed = []
    for extension, formatter in (('nim', nim), ('rs', rust)):
        for path in sorted(root.rglob('*.'+extension)):
            output = formatter(path.read_text())
            if output != path.read_text():
                changed.append(str(path.relative_to(root)))
                if not args.check:
                    path.write_text(output)
    if args.check and changed:
        raise ValueError('Experiment formatting differs: '+', '.join(changed))
    print('Faithful experiment formatting passed; changed='+str(len(changed)))


if __name__ == '__main__':
    main()
