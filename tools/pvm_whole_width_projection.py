#!/usr/bin/env python3
# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
"""Select fixed-width production checked callbacks during private whole-image compilation.

No memory projection, pointer lease or production change: each helper calls the public static-width
writer API. Native save/restore, argument formation, fault publication and accounting stay intact.
"""
from pathlib import Path
from native_checks import ROOT
from pvm_whole_memory_projection import once


def derive(folder, *, clocked=False):
    """Derive one callback-specialization variant plus unchanged baseline and clocks-disabled gates."""
    folder=Path(folder).resolve()
    if folder.parent!=ROOT/'build':raise ValueError('private sources require direct build child')
    folder.mkdir(parents=True,exist_ok=True)
    original=(ROOT/'tests/performance/pvm_whole_image.nim').read_text()
    load_type='  LoadCallback = proc(raw: pointer, address, width: uint64): uint64 {.cdecl, raises: [].}\n'
    store_type='  StoreCallback = proc(raw: pointer, address, value, width: uint64) {.cdecl, raises: [].}\n'
    native=once(original,load_type+store_type,'')
    native=once(native,'type\n','type\n'+load_type+store_type)
    native=once(native,'    writer*: nil pointer',
        '    loadCallbacks: array[4, nil LoadCallback] ## Typed synchronous function capabilities.\n'
        '    storeCallbacks: array[4, nil StoreCallback] ## Cleared before returning a result.\n    writer*: nil pointer')
    # Preserve the original writer offset152 by placing the two typed tables after its complete line.
    a=native.index('    loadCallbacks:');b=native.index('    writer*:',a);end=native.index('\n',b)
    tables=native[a:b];native=native[:a]+native[b:end+1]+tables+native[end+1:]
    first=original.index('proc checkedLoad(');middle=original.index('proc checkedStore(',first)
    past=original.index('proc emitMemory(',middle)
    additions=[]
    for width in (1,2,4,8):
        # Clone only the callback boundary, then select the existing production constant-width API.
        load=once(original[first:middle],'proc checkedLoad(',f'proc checkedLoad{width}(')
        load=once(load,'load(writer, MemoryAddress(address), AccessWidth(byte(width)))',
            f'load[{width}](writer, MemoryAddress(address))')
        store=once(original[middle:past],'proc checkedStore(',f'proc checkedStore{width}(')
        store=once(store,'store(writer, MemoryAddress(address), AccessWidth(byte(width)), RegisterValue(value))',
            f'store[{width}](writer, MemoryAddress(address), RegisterValue(value))')
        additions.extend((load,store))
    native=once(native,'proc emitMemory(',''.join(additions)+'proc emitMemory(')
    first=native.index('proc emitMemory(');past=native.index('\nproc enter(',first)
    emitter=native[first:past]
    emitter=once(emitter,'  setPc(builder.words, uint64(item.address))',
        '  let widthIndex = case access.width\n    of 1: 0\n    of 2: 1\n    of 4: 2\n    of 8: 3\n    else: -1\n  assert widthIndex >= 0 # Genuine decoded memory operands fix one supported width.\n  setPc(builder.words, uint64(item.address))')
    emitter=once(emitter,'    loadWord(builder.words, 12, 31, 104)',
        '    discard # The selected checked callback is loaded from the retained invocation below.')
    emitter=once(emitter,'    loadWord(builder.words, 12, 31, 112)',
        '    discard # Both callback kinds keep their original argument and spill contract.')
    emitter=once(emitter,'  loadWord(builder.words, 0, 31, 96)',
        '  loadWord(builder.words, 0, 31, 96)\n  loadWord(builder.words, 12, 0, 160+(widthIndex+(if access.isLoad: 0 else: 4))*8)')
    native=native[:first]+emitter+native[past:]
    initialization='\n'.join(f'  context.{kind.lower()}Callbacks[{i}] = checked{kind}{width}'
        for kind in ('Load','Store') for i,width in enumerate((1,2,4,8)))
    native=once(native,'  context.writer = cast[pointer](writer)',
        '  context.writer = cast[pointer](writer)\n'+initialization)
    native=once(native,'  context.writer = nil # No borrowed host pointer escapes a completed invocation.',
        '  for i in 0..<4:\n    context.loadCallbacks[i] = nil\n    context.storeCallbacks[i] = nil\n  context.writer = nil # No borrowed host pointer escapes a completed invocation.')
    native=once(native,'proc checkLayout(raw: pointer): cint',
        'proc checkLayout(raw: pointer, loads: ptr array[4, nil LoadCallback], stores: ptr array[4, nil StoreCallback]): cint')
    native=once(native,"  layout.status = 0x123456789abcdef0'u64",
        "  layout.status = 0x123456789abcdef0'u64\n"+initialization.replace('context.','layout.'))
    native=once(native,'checkLayout(addr layout) == 1',
        'checkLayout(addr layout, addr layout.loadCallbacks, addr layout.storeCallbacks) == 1')
    (folder/'fast_image.nim').write_text(native)
    header=(ROOT/'tests/performance/pvm_whole_image.h').read_text()
    load_type='typedef uint64_t (*pvm_whole_load_fn)(void *, uint64_t, uint64_t);\n'
    store_type='typedef void (*pvm_whole_store_fn)(void *, uint64_t, uint64_t, uint64_t);\n'
    header=once(header,load_type+store_type,'')
    header=once(header,'typedef struct {\n    uint64_t registers',load_type+store_type+'typedef struct {\n    uint64_t registers')
    header=once(header,'    void *writer;',
        '    void *writer;\n    pvm_whole_load_fn load_callbacks[4];\n    pvm_whole_store_fn store_callbacks[4];')
    header=once(header,'sizeof(pvm_whole_invocation) == 160','sizeof(pvm_whole_invocation) == 224')
    header=once(header,'static uint64_t pvm_whole_cpu_ns',
        '_Static_assert(offsetof(pvm_whole_invocation, load_callbacks) == 160, "load callbacks ABI");\n'
        '_Static_assert(offsetof(pvm_whole_invocation, store_callbacks) == 192, "store callbacks ABI");\nstatic uint64_t pvm_whole_cpu_ns')
    header=once(header,'pvm_whole_check_layout(const void *raw)',
        'pvm_whole_check_layout(const void *raw, const pvm_whole_load_fn *loads, const pvm_whole_store_fn *stores)')
    header=once(header,'    return 1;\n}\nstatic void *pvm_whole_publish',
        '    for (unsigned i = 0; i < 4; ++i) {\n'
        '        if (!loads[i] || !stores[i] || context->load_callbacks[i] != loads[i] ||\n'
        '            context->store_callbacks[i] != stores[i]) return 0;\n'
        '    }\n    return 1;\n}\nstatic void *pvm_whole_publish')
    (folder/'pvm_whole_image.h').write_text(header)
    for guest in ('pinky','sieve'):
        text=(ROOT/f'tests/performance/pvm_whole_{guest}.nim').read_text()
        for arm,imported in (('baseline','../../tests/performance/pvm_whole_image'),('fast','./fast_image')):
            driver=once(text,'import ./pvm_whole_image','import '+imported)
            if guest=='pinky':driver=once(driver,'include "./pvm_whole_frame.nim.inc"','include "../../tests/performance/pvm_whole_frame.nim.inc"')
            if not clocked:
                driver=driver.replace('cpuNs()',"0'u64").replace('wallNs()',"0'u64")
                driver=once(driver,'let inputCpuStart','echo "CORRECTNESS_ONLY_CLOCKS_DISABLED,1"\nlet inputCpuStart')
            (folder/((guest if arm=='fast' else 'baseline_'+guest)+'.nim')).write_text(driver)
    controls=once((ROOT/'tests/performance/pvm_whole_controls.nim').read_text(),
        'import ./pvm_whole_image','import ./fast_image')
    controls=once(controls,'let counts = allocationCounts()',
        'include "../../tests/performance/pvm_whole_width_controls.nim.inc"\nlet counts = allocationCounts()')
    (folder/'controls.nim').write_text(controls)
    return dict(fast={g:folder/(g+'.nim') for g in ('pinky','sieve')},
        baseline={g:folder/('baseline_'+g+'.nim') for g in ('pinky','sieve')},controls=folder/'controls.nim')
