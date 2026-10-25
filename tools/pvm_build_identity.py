#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Diagnose identical-source Linux images before collecting any interpreter timings.

The rejected byte prototype is a fixed source stress case only. It is never installed
or executed here. Both ordinary and fresh canonical object paths use unchanged build flags.
"""
import difflib
import hashlib
import json
from pathlib import Path
import platform

from native_checks import NativeChecks, ROOT
from pvm_guest_compare import DRIVER, compile_image, snapshot
from pvm_guest_inputs import digest
from pvm_opcode_census import build
from setup_nimony import installed


BUILD = ROOT/'build/tests/pvm-build-identity'
SOURCE = '11f79d97'


def generated(row):
    """Bind generated C basenames to bytes before the next clean staging build retires its cache."""
    cache = Path(next(arg.split(':', 1)[1] for arg in row['command'] if arg.startswith('--nimcache:')))
    if not cache.resolve().is_relative_to(BUILD.resolve()):
        raise ValueError('compiler cache escapes identity diagnostic')
    paths = sorted((cache/'c').rglob('*.c'))
    if not paths or len({p.name for p in paths}) != len(paths):
        raise ValueError('incomplete or ambiguous generated C manifest')
    return {p.name: p.read_text() for p in paths}


def run():
    """Separate C-generation differences from ELF/link effects and require all canonical pairs to match."""
    BUILD.mkdir(parents=True, exist_ok=True)
    for name in ('results.json', 'partial.json'):
        (BUILD/name).unlink(missing_ok=True) # Stale success cannot survive a refused control.
    report = dict(status='running', pairs=[], timings_collected=False)
    try:
        if platform.system() != 'Linux':
            raise RuntimeError('ELF build identity diagnosis requires Linux CI')
        compiler, _ = installed()
        report['head'] = NativeChecks(BUILD).command(['git', 'rev-parse', 'HEAD'], 'head')['output'].strip()
        source = BUILD/'source'
        manifest = snapshot(source, SOURCE, {p: (ROOT/p).read_bytes() for p in DRIVER})
        report['source_sha256'] = manifest
        for profile, main, defines in [('native', DRIVER[0], ()),
                ('synthetic-legacy', DRIVER[2], ()), ('synthetic-memo', DRIVER[2], ('pvmBenchmarkMemo',))]:
            for policy in ('independent-paths', 'canonical-paths'):
                images, c_sources = {}, {}
                for role in ('baseline', 'candidate'):
                    # Only the private cache/object/output placement changes between the two policies.
                    folder = BUILD/policy
                    folder.mkdir(exist_ok=True)
                    options = dict(defines=defines)
                    if profile == 'native':
                        options['cflags'] = ('-I'+str(source/'tests/performance'),)
                    if policy == 'independent-paths':
                        path = folder/role
                        path.mkdir(exist_ok=True)
                        row, image = build(NativeChecks(path, reuse_builds=True), compiler,
                                           source/main, profile, **options)
                    else:
                        row, image = compile_image(folder, role, compiler, source/main, profile, **options)
                        path = folder/'compilation'
                    name = policy+'-'+profile+'-'+role
                    c_sources[role] = generated(row)
                    images[role] = dict(sha256=digest(image), build=row,
                        generated_c_sha256={n: hashlib.sha256(t.encode()).hexdigest()
                                            for n, t in c_sources[role].items()})
                    checks = NativeChecks(BUILD)
                    section = BUILD/(name+'-text.bin')
                    extracted = checks.command(['objcopy', '--dump-section', '.text='+str(section),
                                                image, BUILD/(name+'-copy.bin')], name+'-text')
                    if extracted['exit_code'] or not section.is_file():
                        raise RuntimeError('native code section unavailable')
                    images[role]['text_sha256'] = digest(section)
                    for suffix, command in [('elf', ['readelf', '-W', '-a', image]),
                                            ('assembly', ['objdump', '-d', '--no-show-raw-insn', image])]:
                        result = checks.command(command, name+'-'+suffix, timeout=60)
                        if result['exit_code']:
                            raise RuntimeError('missing native identity diagnostics')
                    # Literal strings expose promoted-symbol/module-path effects without archiving executables.
                    result = checks.command(['strings', image], name+'-strings', timeout=30)
                    if result['exit_code']:
                        raise RuntimeError('missing native image strings')
                changed = sorted(n for n in c_sources['baseline'].keys() | c_sources['candidate'].keys()
                                 if c_sources['baseline'].get(n) != c_sources['candidate'].get(n))
                diff = ''.join(line for n in changed for line in difflib.unified_diff(
                    c_sources['baseline'].get(n, '').splitlines(True),
                    c_sources['candidate'].get(n, '').splitlines(True), fromfile='baseline/'+n,
                    tofile='candidate/'+n))
                (BUILD/(policy+'-'+profile+'-generated.diff')).write_text(diff)
                equal = images['baseline']['sha256'] == images['candidate']['sha256']
                report['pairs'].append(dict(policy=policy, profile=profile, images=images,
                                            changed_generated_c=changed, identical=equal))
                print(policy, profile, 'identical='+str(equal), 'changed C='+str(changed), flush=True)
                (BUILD/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
                if policy == 'canonical-paths' and not equal:
                    raise RuntimeError('fresh canonical native image control failed')
        report['status'] = 'checks-passed'
        (BUILD/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    except Exception as error:
        report.update(status='failed', error=str(error))
        (BUILD/'partial.json').write_text(json.dumps(report, indent=2)+'\n')
        raise


if __name__ == '__main__':
    run() # Imported helpers never build or execute a guest.
