#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""ONE private structural checked-memory experiment; no production source edits or pointer-layout casts.

The private module textually consumes the original production backing and scalar implementation,
adds a saturating alias/snapshot revocation generation, and keeps raw chunk leases invocation-local.
Generated ARM64 hits retain all span/permission/private-epoch checks; misses use original helpers.
Correctness images have clocks disabled. Timing requires exact-head independent source/correctness proof.
"""
import pathlib
from native_checks import ROOT


def derive(folder, *, clocked=False):
    """Generate one concrete variant from owned pinned sources; no tuning knobs or alternate memory strategies."""
    root=ROOT
    folder=pathlib.Path(folder).resolve()
    if folder.parent != root/'build':raise ValueError('private generated sources must remain in a direct build child')
    folder.mkdir(parents=True,exist_ok=True)
    templates=root/'tests/performance/pvm_whole_memory'
    for name in ('lease.nim.inc','probes.nim.inc'):
        (folder/name).write_bytes((templates/name).read_bytes())
    machine=(root/'src/pvm/machine.nim').read_text()
    machine=machine.replace('import ./program','import ../../src/pvm/program')
    machine=machine.replace('    base: Memory\n    pages: seq[PageData]', '    nativeEpoch: uint64 # Private projection only: saturating revocation, shared by every writer alias.\n    base: Memory\n    pages: seq[PageData]')
    revoke='''proc revokeNativeWindows(writer: nil ScalarMemoryWriter) {.inline.} =
      ## Every public writer store and seal invalidates raw leases before COW or publication, including failures/unchanged seals.
      if writer != nil and writer.nativeEpoch != high(uint64): inc writer.nativeEpoch

    '''
    machine=machine.replace('func error*[T]',revoke+'func error*[T]')
    machine=machine.replace('ScalarMemoryWriter(base: memory,','ScalarMemoryWriter(nativeEpoch: 1, base: memory,')
    machine=machine.replace('  storeScalar[0](writer, address, width, value)','  revokeNativeWindows(writer)\n  storeScalar[0](writer, address, width, value)')
    machine=machine.replace('  storeScalar[Width](writer, address, AccessWidth(byte(Width)), value)','  revokeNativeWindows(writer)\n  storeScalar[Width](writer, address, AccessWidth(byte(Width)), value)')
    machine=machine.replace('  ## Seal the current epoch by transferring its private vector; all writer aliases resume from this immutable owner on later writes.','  ## Seal the current epoch by transferring its private vector; all writer aliases resume from this immutable owner on later writes.\n  revokeNativeWindows(writer)')
    assert machine.count('  revokeNativeWindows(writer)')==3
    (folder/'private_machine.nim.inc').write_text(machine)
    text=(root/'tests/performance/pvm_whole_image.nim').read_text().replace('import ../../src/pvm/[program, machine]','import ../../src/pvm/program\ninclude "./private_machine.nim.inc"')
    text=text.replace('    writer*: nil pointer', '''    readTag: uint64
        readPointer: nil pointer
        writeTag: uint64
        writePointer: nil pointer
        epochPointer: nil pointer
        readEpoch, writeEpoch, fastLoads, fastStores, slowLoads, slowStores: uint64
        testProbe: nil pointer
        writer*: nil pointer''')
    # The ABI must keep the original writer offset152; append all private fields after it.
    a=text.index('    readTag: uint64');b=text.index('  LoadCallback',a)
    text=text[:a]+'''    writer*: nil pointer ## Borrowed writer, retained throughout the synchronous native invocation.
        readTag: uint64
        readPointer: nil pointer
        writeTag: uint64
        writePointer: nil pointer
        epochPointer: nil pointer
        readEpoch, writeEpoch, fastLoads, fastStores, slowLoads, slowStores: uint64
        testProbe: nil pointer
    '''+text[b:]
    text=text.replace('proc checkedLoad(', (folder/'lease.nim.inc').read_text()+'\nproc checkedLoad(')
    text=text.replace('  inc context.loads\n', '  inc context.loads\n  clearWindows(context)\n')
    text=text.replace('  uint64(read.value)\n', '  seedWindows(context, address, width, false)\n  uint64(read.value)\n')
    text=text.replace('  inc context.stores\n', '  inc context.stores\n  clearWindows(context)\n')
    text=text.replace('    recordFailure(context, written.error, page)\n\nproc emitMemory', '    recordFailure(context, written.error, page)\n  else:\n    seedWindows(context, address, width, true)\n\nproc emitMemory')
    # Guarded direct memory performs no spill, callback, ownership mutation or publication on a hit.
    start=text.index('proc emitMemory(');end=text.index('\nproc enter(',start);old=text[start:end]
    old=old.replace('  setPc(builder.words, uint64(item.address))', '''  # Common native access uses only real writer chunks admitted by the original checked helper.
      var misses: seq[int] = @[]
      emitImmediate(builder.words, 1, uint64(item.x) and 0xffffffff'u64)
      case access.base
      of MemoryBase.A: builder.words.add(0x0b010001'u32 or (reg(slots.aIndex) shl 5))
      of MemoryBase.B: builder.words.add(0x0b010001'u32 or (reg(slots.bIndex) shl 5))
      else: discard
      if not access.isLoad:
        if access.usesImmediate: emitImmediate(builder.words, 2, uint64(item.y))
        else: builder.words.add(0xaa0003e2'u32 or (reg(slots.aIndex) shl 16))
      emitImmediate(builder.words, 3, 65536)
      builder.words.add(0xeb03003f'u32) # CMP X1,X3; protected-prefix refusals always use original ordering.
      misses.add(conditional(builder.words, 3))
      emitImmediate(builder.words, 3, 0xffffffff'u64-uint64(access.width))
      builder.words.add(0xeb03003f'u32)
      misses.add(conditional(builder.words, 8))
      emitImmediate(builder.words, 3, 511)
      builder.words.add(0x8a030023'u32) # AND X3,X1,X3 supplies the complete chunk offset.
      builder.words.add(0xf100007f'u32 or (uint32(512-int(access.width)) shl 10))
      misses.add(conditional(builder.words, 8))
      loadWord(builder.words, 12, 31, 96)
      builder.words.add(0xd349fc2d'u32) # LSR X13,X1,#9: exact physical page/chunk key.
      loadWord(builder.words, 14, 12, (if access.isLoad: 160 else: 176))
      builder.words.add(0xeb0e01bf'u32) # CMP X13,X14.
      misses.add(conditional(builder.words, 1))
      loadWord(builder.words, 14, 12, (if access.isLoad: 168 else: 184))
      builder.words.add(0xf10001df'u32) # CMP X14,#0; a retired pointer never conveys authority.
      misses.add(conditional(builder.words, 0))
      loadWord(builder.words, 13, 12, 192)
      builder.words.add(0xf10001bf'u32)
      misses.add(conditional(builder.words, 0))
      loadWord(builder.words, 13, 13, 0) # Current shared alias/snapshot revocation generation.
      loadWord(builder.words, 0, 12, (if access.isLoad: 200 else: 208))
      builder.words.add(0xeb0001bf'u32) # CMP X13,X0 precedes every chunk-pointer dereference.
      misses.add(conditional(builder.words, 1))
      builder.words.add(0x8b0301ce'u32) # ADD X14,X14,X3, after full-span and epoch guards.
      let operation = if access.isLoad:
        (if access.width == 1: 0x39400000'u32 elif access.width == 2: 0x79400000'u32
         elif access.width == 4: 0xb9400000'u32 else: 0xf9400000'u32)
        else:
          (if access.width == 1: 0x39000000'u32 elif access.width == 2: 0x79000000'u32
           elif access.width == 4: 0xb9000000'u32 else: 0xf9000000'u32)
      builder.words.add(operation or (14'u32 shl 5) or (if access.isLoad: 0'u32 else: 2'u32))
      let counter = if access.isLoad: 216 else: 224
      loadWord(builder.words, 13, 12, counter)
      builder.words.add(0x910005ad'u32) # ADD X13,X13,#1 counts a real native direct access.
      storeWord(builder.words, 13, 12, counter)
      let directDone = branch(builder.words)
      for miss in misses: patchBranch(builder.words, miss, builder.words.len)
      # Every miss retains the unchanged original complete helper/preflight/COW/failure path.
      setPc(builder.words, uint64(item.address))''')
    old=old.replace('  if access.isLoad:\n    if access.isSigned:', '  patchBranch(builder.words, directDone, builder.words.len)\n  if access.isLoad:\n    if access.isSigned:')
    text=text[:start]+old+text[end:]
    text=text.replace('  context.writer = nil # No borrowed host pointer escapes a completed invocation.', '''  context.slowLoads = context.loads
      context.slowStores = context.stores
      context.loads += context.fastLoads
      context.stores += context.fastStores
      clearWindows(addr context)
      context.epochPointer = nil
      context.testProbe = nil
      context.writer = nil # No borrowed authority or host pointer escapes a completed invocation.''')
    text=text.replace('  layout.status = 0x123456789abcdef0\'u64', "  layout.readTag = 11\n  layout.readPointer = cast[pointer](0x1010'u64)\n  layout.writeTag = 22\n  layout.writePointer = cast[pointer](0x2020'u64)\n  layout.epochPointer = cast[pointer](0x3030'u64)\n  layout.readEpoch = 33\n  layout.writeEpoch = 44\n  layout.fastLoads = 55\n  layout.fastStores = 66\n  layout.slowLoads = 77\n  layout.slowStores = 88\n  layout.testProbe = cast[pointer](0x4040'u64)\n  layout.status = 0x123456789abcdef0'u64")
    text=text.replace('proc invoke*(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile): Invocation =', 'proc invokeInternal(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile, probe: nil pointer): Invocation =')
    text=text.replace('  context.writer = cast[pointer](writer)', '  context.writer = cast[pointer](writer)\n  context.testProbe = probe')
    text += '\nproc invoke*(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile): Invocation =\n  ## Ordinary callers have no probe/callback injection surface; all raw lease state is invocation-local.\n  invokeInternal(image, writer, registers, nil)\n\nwhen defined(pvmWholeNativeLeaseControls):\n  proc invokeLeaseProbe*(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile,\n      mode: LeaseProbe, replacement: uint64): (Invocation, Memory, bool) =\n    ## Correctness-only owned alias can seal/COW mid-call; returned values expose no lease or raw pointer.\n    let probe = ProbeState(mode: mode, alias: writer, replacement: replacement, fired: false, saved: default(Memory))\n    if mode in [LeaseProbe.Saturated, LeaseProbe.ReadThenSaturatingCow]:\n      writer.nativeEpoch = high(uint64)-1\n      probe.fired = mode == LeaseProbe.Saturated\n    let done = invokeInternal(image, writer, registers, cast[pointer](probe))\n    assert done.readPointer == nil and done.writePointer == nil and done.epochPointer == nil\n    assert done.writer == nil and done.testProbe == nil\n    if mode in [LeaseProbe.Saturated, LeaseProbe.ReadThenSaturatingCow]: assert writer.nativeEpoch == high(uint64)\n    (done, probe.saved, probe.fired)\n'
    (folder/'fast_image.nim').write_text(text)
    header=(root/'tests/performance/pvm_whole_image.h').read_text().replace('    void *writer;','''    void *writer;
        uint64_t read_tag; void *read_pointer;
        uint64_t write_tag; void *write_pointer;
        void *epoch_pointer;
        uint64_t read_epoch, write_epoch, fast_loads, fast_stores, slow_loads, slow_stores;
        void *test_probe;''').replace('sizeof(pvm_whole_invocation) == 160','sizeof(pvm_whole_invocation) == 256')
    header=header.replace('_Static_assert(sizeof(pvm_whole_invocation)', '_Static_assert(offsetof(pvm_whole_invocation, read_tag) == 160, "read lease ABI");\n_Static_assert(offsetof(pvm_whole_invocation, epoch_pointer) == 192, "epoch ABI");\n_Static_assert(offsetof(pvm_whole_invocation, fast_loads) == 216, "native count ABI");\n_Static_assert(offsetof(pvm_whole_invocation, test_probe) == 248, "probe ABI");\n_Static_assert(sizeof(pvm_whole_invocation)')
    header=header.replace('    return 1;\n}\nstatic void *pvm_whole_publish','    if (context->read_tag != 11 || (uintptr_t)context->read_pointer != 0x1010 ||\n        context->write_tag != 22 || (uintptr_t)context->write_pointer != 0x2020 ||\n        (uintptr_t)context->epoch_pointer != 0x3030 || context->read_epoch != 33 ||\n        context->write_epoch != 44 || context->fast_loads != 55 || context->fast_stores != 66 ||\n        context->slow_loads != 77 || context->slow_stores != 88 ||\n        (uintptr_t)context->test_probe != 0x4040) return 0;\n    return 1;\n}\nstatic void *pvm_whole_publish')
    (folder/'pvm_whole_image.h').write_text(header)
    for guest in ('pinky','sieve'):
     driver=(root/f'tests/performance/pvm_whole_{guest}.nim').read_text().replace('import ../../src/pvm/[program, machine]','import ../../src/pvm/program').replace('import ./pvm_whole_image','import ./fast_image').replace('include "./pvm_whole_frame.nim.inc"','include "../../tests/performance/pvm_whole_frame.nim.inc"')
     driver=driver.replace('  assert done.status == 1', '  let paths = memoryPaths(done)\n  echo "WHOLE_MEMORY_PATH,", sample, ",", paths[0], ",", paths[1], ",", paths[2], ",", paths[3]\n  assert done.status == 1')
     if not clocked:
      driver=driver.replace('cpuNs()', "0'u64").replace('wallNs()', "0'u64")
      driver=driver.replace('let inputCpuStart', 'echo \"CORRECTNESS_ONLY_CLOCKS_DISABLED,1\"\nlet inputCpuStart',1)
     (folder/(guest+'.nim')).write_text(driver)

    # Keep baseline consumers on the unchanged real production module/header; only guest clocks differ by phase.
    for guest in ('pinky','sieve'):
        baseline=(root/('tests/performance/pvm_whole_'+guest+'.nim')).read_text()
        baseline=baseline.replace('import ./pvm_whole_image','import ../../tests/performance/pvm_whole_image')
        baseline=baseline.replace('include "./pvm_whole_frame.nim.inc"','include "../../tests/performance/pvm_whole_frame.nim.inc"')
        if not clocked:
            baseline=baseline.replace('cpuNs()', "0'u64").replace('wallNs()', "0'u64")
            baseline=baseline.replace('let inputCpuStart','echo "CORRECTNESS_ONLY_CLOCKS_DISABLED,1"\nlet inputCpuStart',1)
        (folder/('baseline_'+guest+'.nim')).write_text(baseline)
    controls=(root/'tests/performance/pvm_whole_controls.nim').read_text()
    controls=controls.replace('import ../../src/pvm/[program, machine]','import ../../src/pvm/program')
    controls=controls.replace('import ./pvm_whole_image','import ./fast_image')
    at=controls.index('let counts = allocationCounts()')
    controls=controls[:at]+(templates/'controls.nim.inc').read_text()+'\n'+(templates/'alias_edges.nim.inc').read_text()+'\n'+controls[at:]
    (folder/'controls.nim').write_text(controls)
    return dict(fast={g:folder/(g+'.nim') for g in ('pinky','sieve')},
                baseline={g:folder/('baseline_'+g+'.nim') for g in ('pinky','sieve')},controls=folder/'controls.nim')
