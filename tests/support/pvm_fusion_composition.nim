# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Build original combined-branch/adjacent-header programs for source binding and full-frame controls.

import std/assertions
import ../../src/codec/natural
import ../../src/pvm/[program, machine]
import ../../src/pvm/internal/[handler_stream, native_fusion, native_pipeline, native_platform]

when NativeReadCycleEnabled and defined(pvmSharedAsyncWitness):
  type CompositionFixture = object
    ## The second original block begins at the copied source PC, independent of stream placement.
    owner: Program
    second: uint32

  proc decodeFusionFixture(code: openArray[byte], starts: openArray[int]): Program =
    ## Keep the original instruction bitmap independent of the checked stream layout.
    var wire = @[0'u8, 0]
    let size = encode(JamNatural(uint64(code.len)))
    for index in 0..<size.len: wire.add(size.bytes[index])
    for value in code: wire.add(value)
    var mask = newSeq[byte]((code.len+7) div 8)
    for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
    for value in mask: wire.add(value)
    let loaded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(uint64(wire.len)),
        JumpCountLimit(1))
    assert loaded.error == ProgramError.None, "fusion fixture decoding"
    loaded.value

  proc compositionGuest(branch: byte, host: bool, leading: int = 0): CompositionFixture =
    ## Two separately priced source blocks retain a real halt/host successor outside the native graph.
    var code: seq[byte] = @[]
    var starts: seq[int] = @[]
    template emit(bytes: openArray[byte]) =
      ## Preserve the independent original instruction-start map.
      starts.add(code.len)
      for value in bytes: code.add(value)
    template jump(bytes: openArray[byte], destination: int) =
      ## Encode a widened signed displacement without relying on stream offsets.
      let delta = cast[uint32](int32(destination-code.len))
      starts.add(code.len)
      for value in bytes: code.add(value)
      for index in 0..<4: code.add(byte((delta shr (8*index)) and 255))
    for index in 0..<leading:
      # Literal boundary controls count folded noops in the original source span, not the dense body.
      emit([2'u8])
    if branch == 88:
      # A folded leading source fact keeps the whole header ordinary while the ADD/branch pair combines.
      emit([2'u8])
    emit([131'u8, 0x22, 1])
    let conditional = code.len
    jump([branch, 0x12, 3], 0)
    if host:
      # The untaken ADD branch has its own original host/exit continuation.
      emit([10'u8, 42])
    emit([50'u8, 3])
    let second = uint32(code.len)
    let forward = cast[uint32](int32(int(second)-conditional))
    for index in 0..<4: code[conditional+3+index] = byte((forward shr (8*index)) and 255)
    emit([132'u8, 0x24, 7])
    jump([81'u8, 0x14, 0], 0)
    if host:
      # An unsupported native terminal still exposes the exact original host boundary and successor.
      emit([10'u8, 42])
    emit([50'u8, 3])
    CompositionFixture(owner: decodeFusionFixture(code, starts), second: second)

  proc successorGuest(): Program =
    ## Two hot blocks connect through a cold block beyond the sample ranking.
    ## A second, entirely ranked path keeps dispatch entries available in the rank-only control.
    var code: seq[byte] = @[]
    var starts: seq[int] = @[]
    template emit(bytes: openArray[byte]) =
      ## Record each instruction before copying its exact bytes.
      starts.add(code.len)
      for value in bytes: code.add(value)
    const connector = NativeFusionBlockLimit
    const terminal = connector+1
    for index in 0..connector:
      let successor = case index
        of 0: connector
        of 1, 2: index+1
        of connector: 4
        else: terminal
      emit([131'u8, 0x22, 1])
      let delta = cast[uint16](int16(6*successor-code.len))
      emit([40'u8, byte(delta and 255), byte(delta shr 8)])
    emit([10'u8, 42])
    emit([0'u8])
    decodeFusionFixture(code, starts)

  proc runFusionComposition*() =
    ## Both original arithmetic/branch predicates and both external exits share the actual scoped bridge.
    witnessFlatFusionSampling()
    for leading in [30, 31]:
      # ADD plus branch makes exactly 32 or 33 original instructions despite the same dense body.
      let fixture = compositionGuest(83, false, leading)
      witnessFlatFusionSourceLimit(fixture.owner, leading == 30)
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "composition runtime failed to start"
    witnessFlatFusionSuccessorReserve(successorGuest(), runtime)
    for branch in [83'u8, 88]:
      for host in [false, true]:
        let fixture = compositionGuest(branch, host)
        witnessFlatFusionComposition(fixture.owner, fixture.second, branch, runtime)
    assert close(runtime)
