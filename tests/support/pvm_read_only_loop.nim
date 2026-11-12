# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Maintained decoded signed-loop source, frame, discovery and shared-worker regressions.

import std/[assertions, syncio]
import ../../src/codec/natural
import ../../src/pvm/program
import ../../src/pvm/internal/native_ir
when NativeReadCycleEnabled and defined(pvmReadOnlyMixedLoopWitness):
  import ../../src/pvm/internal/[handler_stream, native_mixed_loop, native_pipeline, native_platform]
  import ./pvm_register_ring
  when defined(pvmMixedLoopArenaWitness):
    when defined(pvmX86Jit):
      import ../../src/pvm/internal/x86_jit
    else:
      import ../../src/pvm/internal/arm64_jit

  proc runReadOnlyLoopScheduling*(program: Program, pc: uint32, report = false) =
    ## Exercise the explicit loop-only scheduler with a signed source proof and an exact Ring.
    let proof = witnessFlatReadOnlyMixedSource(program, pc)
    let runtime = newNativeRuntime()
    try:
      assert start(runtime)
    except:
      assert false, "read-only ordering worker startup failed"
    let session = newNativeSession(runtime)
    beginNativeInvocation(session, NativeInvocationFloor)
    nominateNativeRing(session, registerRingFixture([3'u64, 2, 5]), nativeEpoch(session))
    finishNativeInvocation(session, NativeInvocationFloor)
    waitNativeCompiler(runtime)
    beginNativeInvocation(session, NativeInvocationFloor)
    assert mixedLoopPrimaryReady(session)
    let exact = nativeInstalledKey(session)
    var wrong = exact
    wrong.epoch += 1
    assert not matchesNativeImage(session, wrong, NativeKind.RegisterRing)
    assert not matchesNativeImage(session, exact, NativeKind.ConnectedReadCycle)
    pauseNativeCompiler(runtime, true)
    let initial = runtimeInfo(runtime)
    witnessFlatReadOnlyScheduling(program, pc, session, 2, false)
    witnessFlatReadOnlyScheduling(program, pc, session, 901, false, stale = true)
    assert runtimeInfo(runtime).submitted == initial.submitted
    finishNativeInvocation(session, NativeInvocationFloor)
    beginNativeInvocation(session, NativeInvocationFloor-1)
    witnessFlatReadOnlyScheduling(program, pc, session, 901, false)
    assert runtimeInfo(runtime).submitted == initial.submitted
    finishNativeInvocation(session, NativeInvocationFloor)
    beginNativeInvocation(session, NativeInvocationFloor)
    witnessFlatReadOnlyScheduling(program, pc, session, 901, true)
    assert runtimeInfo(runtime).submitted == initial.submitted+1
    finishNativeInvocation(session, NativeInvocationFloor)
    pauseNativeCompiler(runtime, false)
    waitNativeCompiler(runtime)
    beginNativeInvocation(session, NativeInvocationFloor)
    var lease = default(NativeAuxiliaryLease)
    let shared = borrowNativeMixedLoops(session, singleNativeMixedLoop(proof), lease)
    assert lease.ready and shared.mask == 1
    when defined(pvmMixedLoopArenaWitness):
      when defined(pvmX86Jit):
        let expected = x86MixedLoopInstructions(proof.operations.toOpenArray(0, int(proof.count)-1))
      else:
        var expected: seq[byte] = @[]
        for word in armMixedLoopInstructions(proof.operations.toOpenArray(0, int(proof.count)-1)):
          for lane in 0..<4: expected.add(byte((word shr (lane*8)) and 255'u32))
      let rx = witnessBorrowedAuxiliaryImage(lease, 0, expected)
      if report: echo "READ_ONLY_RING_RX_OK,", rx.offset, ",", rx.length
    returnNativeAuxiliary(lease)
    finishNativeInvocation(session, NativeInvocationFloor)
    invalidateNativeStream(session)
    assert runtimeInfo(runtime).registered == 0 and close(runtime)
    if report: echo "READ_ONLY_RING_ORDERING_OK,901,3"

  proc readOnlyFixture(): tuple[program: Program, pcs: array[4, uint32]] =
    ## Four tiny original loops vary loaded operand polarity, stride and relative load offset.
    var code: seq[byte] = @[]
    var starts: seq[int] = @[]
    var pcs = default(array[4, uint32])
    template emit(bytes: openArray[byte]) =
      starts.add(code.len)
      for value in bytes: code.add(value)
    # The independently decoded primary Ring protects original facts 0..7.
    # Keep the auxiliary fixture disjoint in source coordinates as well as cached headers.
    for _ in 0..<32: emit([0'u8])
    for index in 0..<4:
      pcs[index] = uint32(code.len)
      emit([2'u8]) # Leading original noop remains in price/span after physical folding.
      emit([129'u8, 0xc6, byte(if index >= 2: 4 else: 0)]) # S32 R6,[R12+offset].
      emit([200'u8, 0xab, 11]) # R11 += R10.
      emit([149'u8, 0xcc, byte(if index >= 2: 8 else: 4)]) # Advance the source address.
      let displacement = cast[uint32](int32(pcs[index])-int32(code.len))
      emit([173'u8, (if index mod 2 == 0: 0x67'u8 else: 0x76'u8),
        byte(displacement and 255), byte((displacement shr 8) and 255),
        byte((displacement shr 16) and 255), byte(displacement shr 24)])
      emit([0'u8]) # Independent outside header, intercepted before unrelated work.
    var wire = @[0'u8, 0]
    let length = encode(JamNatural(uint64(code.len)))
    for index in 0..<length.len: wire.add(length.bytes[index])
    for value in code: wire.add(value)
    var mask = newSeq[byte]((code.len+7) div 8)
    for start in starts: mask[start div 8] = mask[start div 8] or (1'u8 shl (start mod 8))
    for value in mask: wire.add(value)
    let decoded = decodeProgram(wire, CodeAddress(0), ProgramByteLimit(256), JumpCountLimit(0))
    assert decoded.error == ProgramError.None
    (decoded.value, pcs)

proc runReadOnlyLoops*() =
  ## Run thirteen exact frame/receipt cases, two repaired retries and all signed scheduling controls.
  when NativeReadCycleEnabled and defined(pvmReadOnlyMixedLoopWitness):
    let fixture = readOnlyFixture()
    let program = fixture.program
    let pcs = fixture.pcs
    witnessFlatReadOnlyMixedFrames(program, pcs[0], report = false)
    witnessFlatMixedProbeBarrier(program, pcs[0], readOnly = true)
    runReadOnlyLoopScheduling(program, pcs[0])
    for pc in pcs:
      witnessFlatReadOnlyDiscovery(program, [pc], 1)
      assert witnessFlatReadOnlyOrientation(program, pc) > 0
    witnessFlatReadOnlyDiscovery(program, pcs, 1)
    witnessFlatReadOnlyDiscovery(program, [pcs[1], pcs[0]], 1)
  echo "PVM read-only loops passed"
