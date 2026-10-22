#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Apply pinned Nim and Rust formatters, or check both languages without writing.

Exposes format_source/format_rust and a CLI to apply or check the pinned source formatters.
"""
import argparse
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


# Format through stdin so check mode never edits the file being inspected.
def format_source(path):
    return subprocess.run([os.environ.get('NIMPRETTY', 'nimpretty'), '--stdin', '--indent:2', '--maxLineLen:100'],
                          input=path.read_bytes(), capture_output=True, check=True).stdout


# Cargo selects project-owned Rust modules; the explicit toolchain pin also applies outside Make.
def format_rust(check):
    toolchain = json.loads((ROOT/'spec/bandersnatch-pins.json').read_text())['rust']
    passed = True
    for relative in ('native/bandersnatch/Cargo.toml', 'tests/performance/crypto/Cargo.toml'):
        # The benchmark candidate remains separately locked but follows the same Rust formatting rules.
        arguments = ['rustup', 'run', toolchain, 'cargo', 'fmt', '--manifest-path', str(ROOT/relative)]
        if check:
            arguments += ['--', '--check']
        if subprocess.run(arguments, cwd=ROOT).returncode != 0:
            passed = False
    return passed


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
    # Run Rust even after Nim mismatches so one invocation reports both languages' formatting failures.
    rust_passed = format_rust(args.check)
    if not rust_passed or (args.check and changed):
        # Neither a Rust failure nor pending Nim edits may produce a successful combined check.
        raise SystemExit(1)
    print(f'Formatting {"check" if args.check else "run"} passed ({len(paths)} Nim source files; Rust crate).')


# Imports expose the formatter helper without editing the checkout.
if __name__ == '__main__':
    main()
