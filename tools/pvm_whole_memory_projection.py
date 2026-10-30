#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""ONE private structural checked-memory source projection; production sources stay unchanged.

Readable owned fragments avoid host-language indentation changing emitted Nim/C. The private module
uses the original backing/preflight/COW with explicit alias revocation and closed native chunk leases.
"""
from pathlib import Path
from native_checks import ROOT


def fragment(templates, name):
    """Drop only three verified license/purpose comment lines; preserve every remaining source byte."""
    lines=(templates/name).read_text().splitlines(keepends=True)
    if len(lines)<4 or 'Copyright (c) 2026' not in lines[0] or 'SPDX-License-Identifier' not in lines[1]:
        raise ValueError('unframed private source fragment: '+name)
    return ''.join(lines[3:])


def once(source, old, new):
    """Every source surgery has one exact reviewed anchor; future source drift is an explicit refusal."""
    if source.count(old)!=1:raise ValueError('private projection anchor drift: '+old[:70])
    return source.replace(old,new,1)


def derive(folder, *, clocked=False):
    """Generate the one variant and unchanged baseline; correctness clocks remain off unless explicitly gated."""
    root=ROOT;folder=Path(folder).resolve();templates=root/'tests/performance/pvm_whole_memory'
    if folder.parent!=root/'build':raise ValueError('private sources must remain in a direct build child')
    folder.mkdir(parents=True,exist_ok=True)
    for name in ('lease.nim.inc','probes.nim.inc'):(folder/name).write_bytes((templates/name).read_bytes())
    machine=(root/'src/pvm/machine.nim').read_text()
    machine=once(machine,'import ./program','import ../../src/pvm/program')
    machine=once(machine,'    base: Memory\n    pages: seq[PageData]',
        '    nativeEpoch: uint64 # Private projection only: saturating revocation, shared by every writer alias.\n    base: Memory\n    pages: seq[PageData]')
    machine=once(machine,'func error*[T]',fragment(templates,'revoke.nim.inc')+'func error*[T]')
    machine=once(machine,'ScalarMemoryWriter(base: memory,','ScalarMemoryWriter(nativeEpoch: 1, base: memory,')
    for old in ('  storeScalar[0](writer, address, width, value)',
                '  storeScalar[Width](writer, address, AccessWidth(byte(Width)), value)'):
        machine=once(machine,old,'  revokeNativeWindows(writer)\n'+old)
    old='  ## Seal the current epoch by transferring its private vector; all writer aliases resume from this immutable owner on later writes.'
    machine=once(machine,old,old+'\n  revokeNativeWindows(writer)')
    (folder/'private_machine.nim.inc').write_text(machine)
    native=(root/'tests/performance/pvm_whole_image.nim').read_text()
    native=once(native,'import ../../src/pvm/[program, machine]',
        'import ../../src/pvm/program\ninclude "./private_machine.nim.inc"')
    first=native.index('    writer*: nil pointer');past=native.index('  LoadCallback',first)
    native=native[:first]+fragment(templates,'invocation_fields.nim.inc')+native[past:]
    native=once(native,'proc checkedLoad(',(folder/'lease.nim.inc').read_text()+'\nproc checkedLoad(')
    native=once(native,'  inc context.loads\n','  inc context.loads\n  clearWindows(context)\n')
    native=once(native,'  uint64(read.value)\n','  seedWindows(context, address, width, false)\n  uint64(read.value)\n')
    native=once(native,'  inc context.stores\n','  inc context.stores\n  clearWindows(context)\n')
    native=once(native,'    recordFailure(context, written.error, page)\n\nproc emitMemory',
        '    recordFailure(context, written.error, page)\n  else:\n    seedWindows(context, address, width, true)\n\nproc emitMemory')
    first=native.index('proc emitMemory(');past=native.index('\nproc enter(',first);emitter=native[first:past]
    emitter=once(emitter,'  setPc(builder.words, uint64(item.address))',fragment(templates,'native_hit.nim.inc'))
    emitter=once(emitter,'  if access.isLoad:\n    if access.isSigned:',
        '  patchBranch(builder.words, directDone, builder.words.len)\n  if access.isLoad:\n    if access.isSigned:')
    native=native[:first]+emitter+native[past:]
    native=once(native,'  context.writer = nil # No borrowed host pointer escapes a completed invocation.',
        fragment(templates,'clear_result.nim.inc'))
    native=once(native,"  layout.status = 0x123456789abcdef0'u64",fragment(templates,'layout_markers.nim.inc'))
    native=once(native,'proc invoke*(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile): Invocation =',
        'proc invokeInternal(image: WholeImage, writer: ScalarMemoryWriter, registers: RegisterFile, probe: nil pointer): Invocation =')
    native=once(native,'  context.writer = cast[pointer](writer)',
        '  context.writer = cast[pointer](writer)\n  context.testProbe = probe')
    native+=fragment(templates,'invoke.nim.inc')
    (folder/'fast_image.nim').write_text(native)
    header=(root/'tests/performance/pvm_whole_image.h').read_text()
    header=once(header,'    void *writer;',fragment(templates,'invocation_fields.h.inc'))
    header=once(header,'sizeof(pvm_whole_invocation) == 160','sizeof(pvm_whole_invocation) == 256')
    header=once(header,'_Static_assert(sizeof(pvm_whole_invocation)',fragment(templates,'layout_asserts.h.inc'))
    header=once(header,'    return 1;\n}\nstatic void *pvm_whole_publish',fragment(templates,'layout_check.h.inc'))
    (folder/'pvm_whole_image.h').write_text(header)
    for guest in ('pinky','sieve'):
        original=(root/('tests/performance/pvm_whole_'+guest+'.nim')).read_text()
        fast=once(original,'import ../../src/pvm/[program, machine]','import ../../src/pvm/program')
        fast=once(fast,'import ./pvm_whole_image','import ./fast_image')
        fast=once(fast,'  assert done.status == 1',
            '  let paths = memoryPaths(done)\n  echo "WHOLE_MEMORY_PATH,", sample, ",", paths[0], ",", paths[1], ",", paths[2], ",", paths[3]\n  assert done.status == 1')
        baseline=once(original,'import ./pvm_whole_image','import ../../tests/performance/pvm_whole_image')
        for arm,text in (('fast',fast),('baseline',baseline)):
            if guest=='pinky':text=once(text,'include "./pvm_whole_frame.nim.inc"','include "../../tests/performance/pvm_whole_frame.nim.inc"')
            if not clocked:
                text=text.replace('cpuNs()',"0'u64").replace('wallNs()',"0'u64")
                text=once(text,'let inputCpuStart','echo "CORRECTNESS_ONLY_CLOCKS_DISABLED,1"\nlet inputCpuStart')
            (folder/((guest if arm=='fast' else 'baseline_'+guest)+'.nim')).write_text(text)
    controls=(root/'tests/performance/pvm_whole_controls.nim').read_text()
    controls=once(controls,'import ../../src/pvm/[program, machine]','import ../../src/pvm/program')
    controls=once(controls,'import ./pvm_whole_image','import ./fast_image')
    at=controls.index('let counts = allocationCounts()')
    controls=controls[:at]+(templates/'controls.nim.inc').read_text()+'\n'+(templates/'alias_edges.nim.inc').read_text()+'\n'+controls[at:]
    (folder/'controls.nim').write_text(controls)
    return dict(fast={g:folder/(g+'.nim') for g in ('pinky','sieve')},
                baseline={g:folder/('baseline_'+g+'.nim') for g in ('pinky','sieve')},controls=folder/'controls.nim')
