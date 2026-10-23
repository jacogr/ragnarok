#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Semantically compile every production module in one discovered import graph and check the peer main.

The compiler visits shared imports once instead of rebuilding each module's import graph in a
separate process. Smoke uses a checked, unoptimized profile; ordinary audits keep release flags.
Neither path links native libraries or claims runtime coverage.
"""
import argparse
import hashlib
import json
from pathlib import Path
import platform
import subprocess
import tempfile
import time
from setup_nimony import cache_directory

ROOT = Path(__file__).resolve().parents[1]


# Retain one compiler operation's actual command, diagnostics, timing and strict exit status.
def check_module(compiler, source, folder, main=False, fast=False, cache=None):
    started = time.monotonic()
    relative = source.relative_to(ROOT)
    name = '-'.join(relative.with_suffix('').parts)
    flags = ['--mm:arc', '--cc:clang', '--boundchecks:on']
    if fast:
        # The PR gate checks debug code without optimizer or link-time optimization work.
        flags += ['--opt:none']
    else:
        # Explicit/full audits retain their established release profile and all runtime checks.
        flags += ['-d:release', '--opt:speed', '--passC:-flto=thin', '--passL:-flto=thin']
    if main:
        # Imported CLI modules do not select isMainModule; check the real entry point independently too.
        flags += ['--isMain', '-d:integration', '-d:offload']
    args = [str(compiler), 'check', *flags,
            '--nimcache:'+str(cache_directory(compiler, cache or folder, name)), str(source)]
    try:
        result = subprocess.run(args, cwd=ROOT, capture_output=True, text=True, timeout=180)
        code, output = result.returncode, result.stdout+result.stderr
    except subprocess.TimeoutExpired:
        # A timeout remains a failed compilation with actionable retained diagnostics.
        code, output = 124, 'Module semantic check exceeded 180 seconds.\n'
    log = folder/(name+'.log')
    log.write_text(output)
    return dict(source=str(relative), source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(),
                passed=code == 0, exit_code=code, elapsed_seconds=round(time.monotonic()-started, 6),
                command=args, log=str(log.relative_to(ROOT)))


# Discover every module each time; successful compilation cannot omit newly added or currently unused code.
def audit(compiler, folder, smoke=False):
    started = time.monotonic()
    folder.mkdir(parents=True, exist_ok=True)
    (folder/'results.json').unlink(missing_ok=True)
    sources = sorted((ROOT/'src').rglob('*.nim'))
    entry = ROOT/'src/ragnarok.nim'
    if not sources or not entry.is_file():
        raise ValueError('Source tree has no requested Nim modules or peer entry point')
    version = subprocess.check_output([str(compiler), '--version'], text=True, stderr=subprocess.STDOUT)
    driver = folder/'all_sources.nim'
    # Unique aliases prevent name collisions; quoted absolute paths preserve spaces and module locations.
    imports = ['import '+json.dumps(str(source), ensure_ascii=False)+' as source_'+str(index)
               for index, source in enumerate(sources)]
    driver.write_text('# Copyright (c) 2026 Ragnarök contributors\n'
                      '# SPDX-License-Identifier: MIT OR Apache-2.0\n'
                      '## Generated complete production-source semantic import graph.\n'+
                      '\n'.join(imports)+'\n')
    with tempfile.TemporaryDirectory(prefix='source-caches-', dir=folder) as temporary:
        # Fresh private caches prevent prior invocations/profiles from substituting stale compiled modules.
        checks = [check_module(compiler, driver, folder, fast=smoke, cache=Path(temporary)),
                  check_module(compiler, entry, folder, main=True, fast=smoke, cache=Path(temporary))]
    passed = all(check['passed'] for check in checks)
    # Every row shares the complete-graph verdict; errors are diagnosed in the actual compiler-operation logs.
    rows = [dict(source=str(source.relative_to(ROOT)),
                 source_sha256=hashlib.sha256(source.read_bytes()).hexdigest(), passed=passed)
            for source in sources]
    report = dict(status='compile-checks-passed' if passed else 'compile-checks-failed',
                  scope='every production module in one import graph plus the production peer main; semantic only, no native link',
                  profile='debug-unoptimized' if smoke else 'checked-release',
                  environment=dict(system=platform.system(), machine=platform.machine()), compiler=version.strip(),
                  jobs=1, elapsed_seconds=round(time.monotonic()-started, 6), compilations=checks,
                  project_revision=subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
                  modules=rows)
    (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print(('PASS ' if passed else 'FAIL ')+f'{len(rows)} production modules and peer entry point', flush=True)
    return report


# Both the complete source audit and PR smoke retain strict compiler failures and complete inventories.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--compiler', type=Path, required=True)
    parser.add_argument('--output', type=Path)
    parser.add_argument('--smoke', action='store_true', help='Check all production sources with an unoptimized debug profile')
    args = parser.parse_args()
    output = args.output or ROOT/'build/tests'/('smoke' if args.smoke else 'modules')
    report = audit(args.compiler.resolve(), output.resolve(), smoke=args.smoke)
    passed = sum(row['passed'] for row in report['modules'])
    print(f'Module semantic compilation: {passed}/{len(report["modules"])} passed')
    raise SystemExit(0 if report['status'] == 'compile-checks-passed' else 1)


if __name__ == '__main__':
    main()
