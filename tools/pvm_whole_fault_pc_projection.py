#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Move standalone checked-memory fault-PC publication to the existing failure branch only.

The accepted width-specialized compiler remains the baseline. The old ignored width argument now
carries the source PC, so the original checked helper can publish it only when reporting failure.
"""
from pathlib import Path
from native_checks import ROOT
from pvm_whole_memory_projection import once
from pvm_whole_width_projection import derive as derive_width


def derive(folder, *, clocked=False):
    """Derive one lazy-fault-PC variant; no memory checks, ABI fields, spills or status tests change."""
    folder=Path(folder).resolve();paths=derive_width(folder,clocked=clocked)
    accepted=(folder/'fast_image.nim').read_text();(folder/'width_image.nim').write_text(accepted)
    native=accepted
    for kind in ('Load','Store'):
        for width in (1,2,4,8):
            # The static production operation never uses this argument; only its failure path gains PC publication.
            first=native.index(f'proc checked{kind}{width}(');past=native.index('\nproc ',first+1)
            body=native[first:past]
            body=once(body,'width: uint64)','faultPc: uint64)')
            body=once(body,'    recordFailure(context,',
                '    context.pc = faultPc # Publish exact source metadata only for the real checked-memory failure.\n    recordFailure(context,')
            native=native[:first]+body+native[past:]
    first=native.index('proc emitMemory(');past=native.index('\nproc enter(',first)
    emitter=native[first:past]
    emitter=once(emitter,'  setPc(builder.words, uint64(item.address))\n','')
    emitter=once(emitter,'emitImmediate(builder.words, 2, uint64(access.width))',
        'emitImmediate(builder.words, 2, uint64(item.address))')
    emitter=once(emitter,'emitImmediate(builder.words, 3, uint64(access.width))',
        'emitImmediate(builder.words, 3, uint64(item.address))')
    native=native[:first]+emitter+native[past:]
    (folder/'fast_image.nim').write_text(native)
    for guest in ('pinky','sieve'):
        variant=(folder/(guest+'.nim')).read_text()
        baseline=once(variant,'import ./fast_image','import ./width_image')
        baseline_size=416152 if guest=='pinky' else 1697128
        for arm,text in (('baseline',baseline),('fast',variant)):
            # Static memory sites disclose the exact twelve-byte/site code-footprint reduction separately from timing.
            marker='let compileCpuElapsed = cpuNs()-compileCpu' if clocked else "let compileCpuElapsed = 0'u64-compileCpu"
            shape='var memorySites = 0\'u64\nfor opcode in 0..<256:\n  if opcode in {30..33, 52..62, 70..73, 120..130}: memorySites += image.opcodes[opcode]\n'
            shape+=f'assert image.codeBytes'+(' + memorySites*12' if arm=='fast' else '')+f' == {baseline_size}\n'
            shape+='echo "WHOLE_BRIDGE_SHAPE,", memorySites, ",", image.codeBytes, ",", '+str(baseline_size)+'\n'
            text=once(text,marker,marker+'\n'+shape)
            (folder/((guest if arm=='fast' else 'baseline_'+guest)+'.nim')).write_text(text)
    controls=(folder/'controls.nim').read_text()
    controls=once(controls,'let counts = allocationCounts()',
        'include "../../tests/performance/pvm_whole_fault_pc_controls.nim.inc"\nlet counts = allocationCounts()')
    (folder/'controls.nim').write_text(controls)
    return paths
