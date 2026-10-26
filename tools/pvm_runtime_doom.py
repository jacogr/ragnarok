#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Verify the real pinned DOOM guest through the production runtime boundary, without local timing.

The existing independent reference prepares complete CPU/RAM/event goldens. Each selected
runtime adapter must match both initialization and one actual tick, including immutable sources.
"""
import json
import os
import platform
from build_polkavm import build_native
from native_checks import NativeChecks, ROOT
from pvm_doom_attribution import run as prepare, BUILD as REFERENCE_BUILD
from setup_nimony import installed


def run():
    """Prepare independent goldens, then compare actual resident runtime engines with no fallback."""
    prepare(check_only=True, warmup=0)
    folder = ROOT/'build/tests/pvm-runtime-doom'
    checks = NativeChecks(folder)
    library = build_native()
    built, binary = checks.build(installed()[0], ROOT/'tests/performance/pvm_doom.nim',
                                'runtime-doom', native_libraries=(library,),
                                defines=('polkavmRuntime',),
                                cflags=('-I'+str(ROOT/'tests/performance'), '-I'+str(ROOT/'native/polkavm')))
    if built['exit_code']:
        raise RuntimeError('Runtime DOOM build failed: '+built['log'])
    report = dict(status='running', scope='complete CPU/RAM/events; no local timing',
                  builds=[built], runs=[])
    # macOS ARM cannot compile this pinned upstream engine; the boundary suite checks its actual refusal.
    engines = ['polkavm-interpreted']
    if (platform.system(), platform.machine()) == ('Linux', 'x86_64'):
        engines.append('polkavm-native')
    for engine in engines:
        for phase in ('init', 'tick'):
            environment = dict(os.environ, RAGNAROK_PVM_DOOM_INPUT=str(REFERENCE_BUILD/'prepared'),
                               RAGNAROK_PVM_DOOM_ROM=str(ROOT/'vendor/polkavm/examples/doom/roms/doom1.wad'),
                               RAGNAROK_PVM_DOOM_PHASE=phase, RAGNAROK_PVM_DOOM_TIMING='0',
                               RAGNAROK_PVM_DOOM_BACKEND=engine)
            row = checks.command([binary], engine+'-'+phase, environment=environment, timeout=1800)
            row.pop('output', None)
            report['runs'].append(dict(engine=engine, phase=phase, run=row))
            if row['exit_code']:
                report['status'] = 'failed'
                (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
                raise RuntimeError('Runtime DOOM comparison failed: '+row['log'])
    report['status'] = 'checks-passed'
    (folder/'results.json').write_text(json.dumps(report, indent=2)+'\n')
    print('PASS runtime DOOM CPU, RAM and output events')


if __name__ == '__main__':
    run()
