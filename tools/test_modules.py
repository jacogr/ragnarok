#!/usr/bin/env python3
"""Check every source module with the selected Nimony compiler; never accept an expected-failure allowlist."""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
from setup_nimony import cache_directory

ROOT = Path(__file__).resolve().parents[1]


# Capture one independent semantic check, including timeout failures, without hiding later modules.
def check_module(compiler, source, folder):
    relative = source.relative_to(ROOT)
    name = '-'.join(relative.with_suffix('').parts)
    args = [str(compiler), 'check', '--mm:arc', '--cc:clang', '-d:release', '--boundchecks:on',
            '--passC:-flto', '--passL:-flto', '--nimcache:'+str(cache_directory(compiler, folder, name)), str(source)]
    try:
        # A fresh module cache isolates each result; checking does not pretend to prove native linking or runtime behavior.
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=180)
        code, output = result.returncode, result.stdout+result.stderr
    except subprocess.TimeoutExpired:
        # A timeout is a failed check, never a silently omitted source file.
        code, output = 124, 'Module semantic check exceeded 180 seconds.\n'
    log = folder/(name+'.log')
    log.write_text(output)
    return dict(source=str(relative), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                passed=code == 0, exit_code=code, command=args, log=str(log.relative_to(ROOT)))


# Derive coverage from the source tree so newly added or still-unported modules cannot disappear from the gate.
def audit(compiler, folder):
    folder.mkdir(parents=True, exist_ok=True)
    # The pinned compiler prints its version to stderr; retain it in provenance rather than only the console.
    version = subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT)
    rows = []
    # Continue after genuine failures to show all remaining work, while retaining a failing final exit status.
    for source in sorted((ROOT/'src').rglob('*.nim')):
        row = check_module(compiler, source, folder)
        rows.append(row)
        print(('PASS ' if row['passed'] else 'FAIL ')+row['source'], flush=True)
    if not rows:
        raise ValueError('Source tree has no Nim modules')
    report = dict(status='compile-checks-passed' if all(row['passed'] for row in rows) else 'compile-checks-failed',
                  scope='semantic module compilation only; linking and runtime parity remain separate',
                  environment=dict(system=platform.system(), machine=platform.machine()), compiler=version.strip(),
                  project_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(), modules=rows)
    (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    return report


# A failed module keeps this independent PR check red even when all migrated runtime tests pass.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path, default=ROOT/'build/tests/modules')
    args = parser.parse_args()
    report = audit(args.compiler.resolve(), args.output.resolve())
    passed = sum(row['passed'] for row in report['modules'])
    print(f'Module semantic compilation: {passed}/{len(report["modules"])} passed')
    raise SystemExit(0 if report['status'] == 'compile-checks-passed' else 1)


# Importing this inventory never starts compilation or modifies source files.
if __name__ == '__main__':
    main()
