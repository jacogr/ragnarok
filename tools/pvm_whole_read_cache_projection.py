#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""One bounded helper-owned read-page cache, behind all accepted checked writer fast paths.

Retain typed page owners only. Original complete preflight admits entries; COW and every alias
snapshot retire them. No native data lease, new permission authority or production source edit.
"""
from pathlib import Path
from native_checks import ROOT
from pvm_whole_memory_projection import once
from pvm_whole_fault_pc_projection import derive as derive_compact


def derive(folder, *, clocked=False):
    """Derive the compact accepted baseline and one64-entry backup read-cache private machine."""
    folder=Path(folder).resolve();paths=derive_compact(folder,clocked=clocked)
    accepted=(folder/'fast_image.nim').read_text()
    machine=(ROOT/'src/pvm/machine.nim').read_text()
    machine=once(machine,'import ./program','import ../../src/pvm/program')
    (folder/'baseline_machine.nim.inc').write_text(machine)
    baseline_core=once(accepted,'import ../../src/pvm/[program, machine]',
        'import ../../src/pvm/program\ninclude "./baseline_machine.nim.inc"')
    (folder/'compact_image.nim').write_text(baseline_core)
    anchor='  MachineInfo* = object'
    machine=once(machine,anchor,
        '    readCache: array[64, nil PageData] # Typed admitted owners, shared by all aliases of this writer.\n'
        '    readCacheHits, readCacheAdmissions, readCacheInvalidations: uint64 # Actual path counters only.\n'+anchor)
    machine=once(machine,'proc cloneWriterChunk',
        'func readCacheBucket(tag: uint64): int {.inline.} =\n'
        '  ## Reuse the existing bounded slot-hint hash; collisions are exact-tag misses, never authority.\n'
        "  int((tag xor (tag shr 8)) and 63'u64)\n\nproc cloneWriterChunk")
    machine=once(machine,'  writer.readPage = nil # A prior readable header may be the immutable page being replaced.',
        '  let bucket = readCacheBucket(uint64(uint32(writer.pages[slot].index)))\n'
        '  if writer.readCache[bucket] != nil:\n'
        '    inc writer.readCacheInvalidations\n'
        '    writer.readCache[bucket] = nil # Retire any colliding owner before replacing the header/chunk.\n'
        '  writer.readPage = nil # A prior readable header may be the immutable page being replaced.')
    machine=once(machine,'    else: writer.readPage = source.pages[span.first]\n',
        '    else: writer.readPage = source.pages[span.first]\n'
        '    writer.readCache[readCacheBucket(writer.readTag)] = writer.readPage\n'
        '    inc writer.readCacheAdmissions # Only original successful single-page preflight admits an owner.\n')
    first=machine.index('proc loadScalar[');past=machine.index('\nproc load*',first);body=machine[first:past]
    body=once(body,'  loadWriterMiss(writer, source, address, width)',
        '    let cached {.cursor.} = writer.readCache[readCacheBucket(tag)]\n'
        '    if cached != nil and uint64(uint32(cached.index)) == tag:\n'
        '      # Original owner/prefix/end/width/within-page checks above remain mandatory on every hit.\n'
        '      # Admission proved readability; COW and snapshot invalidation preserve this current owner.\n'
        '      writer.readTag = tag\n'
        '      writer.readPage = cached # Match original miss promotion without resolving its span again.\n'
        '      inc writer.readCacheHits\n'
        '      return MachineResult[RegisterValue](status: MachineError.None,\n'
        '        completed: RegisterValue(pageScalar(cached, within, count)))\n'
        '  loadWriterMiss(writer, source, address, width)')
    machine=machine[:first]+body+machine[past:]
    machine=once(machine,'  writer.readPage = nil # All cached aliases retire before an immutable snapshot becomes observable.',
        '  for bucket in 0..<64:\n'
        '    writer.readCache[bucket] = nil # Every shared alias observes the same retirement, even unchanged seals.\n'
        '  writer.readPage = nil # All cached aliases retire before an immutable snapshot becomes observable.')
    machine+='\nproc readCacheCounters*(writer: ScalarMemoryWriter): array[3, uint64] =\n'
    machine+='  ## Copied path observations retain no mutable memory or private page owner.\n'
    machine+='  [writer.readCacheHits, writer.readCacheAdmissions, writer.readCacheInvalidations]\n'
    (folder/'private_machine.nim.inc').write_text(machine)
    native=once(accepted,'import ../../src/pvm/[program, machine]',
        'import ../../src/pvm/program\ninclude "./private_machine.nim.inc"')
    (folder/'fast_image.nim').write_text(native)
    for guest in ('pinky','sieve'):
        original=(folder/(guest+'.nim')).read_text()
        baseline=once(original,'import ./fast_image','import ./compact_image')
        baseline=once(baseline,'import ../../src/pvm/[program, machine]','import ../../src/pvm/program')
        fast=once(original,'import ../../src/pvm/[program, machine]','import ../../src/pvm/program')
        marker='  let publishCpu = cpuNs()' if clocked else "  let publishCpu = 0'u64"
        fast=once(fast,marker,
            '  let cache = readCacheCounters(writer)\n'
            '  echo "WHOLE_READ_CACHE,", sample, ",", cache[0], ",", cache[1], ",", cache[2]\n'+marker)
        (folder/('baseline_'+guest+'.nim')).write_text(baseline)
        (folder/(guest+'.nim')).write_text(fast)
    controls=once((folder/'controls.nim').read_text(),'import ../../src/pvm/[program, machine]',
        'import ../../src/pvm/program')
    controls=once(controls,'let counts = allocationCounts()',
        'include "../../tests/performance/pvm_whole_read_cache_controls.nim.inc"\nlet counts = allocationCounts()')
    (folder/'controls.nim').write_text(controls)
    return paths
