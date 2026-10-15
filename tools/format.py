#!/usr/bin/env python3
"""Format all project Nim/Odin/Mojo sources, or check them without writing changes."""
import argparse
import os
import shutil
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]


def mojo_formatter():
    """Resolve the pinned local SDK, an explicit override, or the installed Mojo executable."""
    configured = os.environ.get("RAGNAROK_MOJO")
    # An explicit SDK path lets CI and isolated developer environments select their compiler.
    if configured:
        return configured
    isolated = ROOT / "build/mojo-env/bin/mojo"
    # Prefer the project installation so formatting follows the evaluation compiler pin.
    if isolated.is_file():
        return str(isolated)
    installed = shutil.which("mojo")
    # Missing tooling is a failed check, rather than silently skipping the third language.
    if installed is None:
        raise SystemExit("Mojo not found; install tools/mojo-requirements.txt in build/mojo-env")
    return installed


def format_source(path):
    """Use the language's formatter on stdin so check mode never modifies a source file."""
    # Select the formatter and its explicit project settings from the source extension.
    if path.suffix == '.nim':
        command = ['nimpretty', '--stdin', '--indent:2', '--maxLineLen:100']
    elif path.suffix == '.mojo':
        # Invoke the compiler's official formatter; stdin keeps check mode read-only.
        command = [mojo_formatter(), 'format', '--quiet', '--line-length', '100', '-']
    else:
        # Odin reads the shared config even when formatting individual files through stdin.
        command = ['odinfmt', '-stdin', f'-config:{ROOT / "odinfmt.json"}']
    return subprocess.run(command, input=path.read_bytes(), capture_output=True,
                          check=True).stdout


def main():
    """Visit all language sources, reporting differences or applying the formatter output."""
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true', help='report differences without changing files')
    args = parser.parse_args()
    changed = []
    # Include tests and deliberate compile-failure fixtures with valid formatter syntax.
    paths = (sorted((ROOT / 'nim').rglob('*.nim'))
             + sorted((ROOT / 'odin').rglob('*.odin'))
             + sorted((ROOT / 'mojo').rglob('*.mojo')))
    for path in paths:
        formatted = format_source(path)
        # Skip files already in canonical formatter output so their timestamps remain untouched.
        if formatted == path.read_bytes():
            continue
        changed.append(path.relative_to(ROOT))
        # Check mode reports the same differences as write mode, but preserves source bytes.
        if not args.check:
            path.write_bytes(formatted)
    # List every affected file so a failed check tells the maintainer what needs formatting.
    for path in changed:
        print(f'{"Needs formatting" if args.check else "Formatted"}: {path}')
    # A check fails only when at least one file differs; write mode completes successfully.
    if args.check and changed:
        raise SystemExit(1)
    print(f'Formatting {"check" if args.check else "run"} passed ({len(paths)} source files).')


# Keep this module importable without formatting the repository as an import side effect.
if __name__ == '__main__':
    main()
