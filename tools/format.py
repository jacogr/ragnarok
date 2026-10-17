#!/usr/bin/env python3
"""Apply Nim's bundled formatter to implementation and test sources, or check without writing."""
import argparse
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


# Format through stdin so check mode never edits the file being inspected.
def format_source(path):
    return subprocess.run([os.environ.get('NIMPRETTY', 'nimpretty'), '--stdin', '--indent:2', '--maxLineLen:100'],
                          input=path.read_bytes(), capture_output=True, check=True).stdout


# Include native tests and intentional compile-failure fixtures in the same canonical style.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    args = parser.parse_args()
    paths = sorted((ROOT/'src').rglob('*.nim'))+sorted((ROOT/'tests').rglob('*.nim'))
    changed = []
    # Preserve timestamps for files already matching the selected formatter output.
    for path in paths:
        output = format_source(path)
        if output == path.read_bytes():
            continue
        changed.append(path.relative_to(ROOT))
        # Check mode reports differences while write mode applies precisely the same bytes.
        if not args.check:
            path.write_bytes(output)
    # Each mismatch names its actual source so a failed CI check is actionable.
    for path in changed:
        print(f'{"Needs formatting" if args.check else "Formatted"}: {path}')
    # A successful check certifies all retained Nim files match the pinned native formatter.
    if args.check and changed:
        raise SystemExit(1)
    print(f'Formatting {"check" if args.check else "run"} passed ({len(paths)} Nim source files).')


# Imports expose the formatter helper without editing the checkout.
if __name__ == '__main__':
    main()
