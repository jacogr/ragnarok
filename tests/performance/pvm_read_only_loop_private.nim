# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Direct source-bound proof for a frozen initialization read-only loop.

import std/[assertions, envvars, syncio]
import ../../src/pvm/[program, machine]
import ../../src/pvm/internal/[handler_stream, native_mixed_loop, native_platform]

proc word(data: string, offset, width: int): uint64 =
  ## Read one bounded little-endian fixture field independently of the program decoder.
  assert width in 1..8 and offset >= 0 and offset <= data.len-width
  result = 0
  for lane in 0..<width:
    result = result or (uint64(byte(data[offset+lane])) shl (8*lane))

var input = ""
try:
  # The controller verifies the complete frozen file digest before launching this main.
  input = readFile(getEnv("RAGNAROK_PVM_READ_ONLY_SOURCE"))
except:
  quit 2
assert input.len >= 152 and input[0..7] == "PVMDOM01"
let size = int(word(input, 8, 4))
assert size > 0 and size <= 4*1024*1024 and size <= input.len-152
var wire = newSeq[byte](size)
for index in 0..<size:
  wire[index] = byte(input[152+index])
let decoded = decodeJamProgram(wire, CodeAddress(word(input, 12, 4)),
  ProgramByteLimit(4*1024*1024), JumpCountLimit(1048576))
assert decoded.error == ProgramError.None
let proof = witnessFlatReadOnlyMixedSource(decoded.value, 471839)
assert proof.span == 5 and proof.count == 4
assert proof.operations[0].opcode == 129 and proof.operations[1].opcode == 200 and
  proof.operations[2].opcode == 149 and proof.operations[3].opcode == 173
var refused = false
let image = lowerNativeMixedLoop(proof, refused)
assert image.ready and not refused
echo "READ_ONLY_SOURCE,", proof.header, ",", proof.first, ",", proof.terminal, ",",
  proof.exitHeader, ",", proof.price, ",", proof.span, ",", proof.count, ",", image.codeBytes
for index in 0..<int(proof.count):
  # Source operands are copied after the original cached node and branch-arm checks.
  let operation = proof.operations[index]
  echo "READ_ONLY_OPERATION,", index, ",", operation.opcode, ",", operation.slots.aIndex,
    ",", operation.slots.bIndex, ",", operation.slots.dIndex, ",",
    operation.slots.destinationIndex, ",", operation.immediate

witnessFlatReadOnlyMixedFrames(decoded.value, 471839)

when defined(pvmSharedAsyncWitness):
  # The observer must restore signed173 through a saved quota barrier before stream retention.
  witnessFlatMixedProbeBarrier(decoded.value, 471839, readOnly = true)
  echo "READ_ONLY_PROBE_BARRIER_OK"

when defined(pvmSharedAsyncWitness):
  import ../support/pvm_register_ring
  import ../../src/pvm/internal/native_pipeline
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
  witnessFlatReadOnlyScheduling(decoded.value, 471839, session, 2, false)
  witnessFlatReadOnlyScheduling(decoded.value, 471839, session, 901, false, stale = true)
  assert runtimeInfo(runtime).submitted == initial.submitted
  finishNativeInvocation(session, NativeInvocationFloor)
  beginNativeInvocation(session, NativeInvocationFloor-1)
  witnessFlatReadOnlyScheduling(decoded.value, 471839, session, 901, false)
  assert runtimeInfo(runtime).submitted == initial.submitted
  finishNativeInvocation(session, NativeInvocationFloor)
  beginNativeInvocation(session, NativeInvocationFloor)
  witnessFlatReadOnlyScheduling(decoded.value, 471839, session, 901, true)
  assert runtimeInfo(runtime).submitted == initial.submitted+1
  finishNativeInvocation(session, NativeInvocationFloor)
  pauseNativeCompiler(runtime, false)
  waitNativeCompiler(runtime)
  beginNativeInvocation(session, NativeInvocationFloor)
  let shared = borrowNativeMixedLoop(session, proof)
  let sharedImage = shared.image
  assert sharedImage != nil and shared.mask == 1
  when defined(pvmMixedLoopArenaWitness):
    when defined(pvmX86Jit):
      import ../../src/pvm/internal/x86_jit
      let expected = x86MixedLoopInstructions(proof.operations.toOpenArray(0, int(proof.count)-1))
    else:
      import ../../src/pvm/internal/arm64_jit
      var expected: seq[byte] = @[]
      for word in armMixedLoopInstructions(proof.operations.toOpenArray(0, int(proof.count)-1)):
        for lane in 0..<4: expected.add(byte((word shr (lane*8)) and 255'u32))
    let rx = witnessNativeMixedLoopImage(sharedImage[], 0, expected)
    echo "READ_ONLY_RING_RX_OK,", rx.offset, ",", rx.length
  returnNativeMixedLoop(session)
  finishNativeInvocation(session, NativeInvocationFloor)
  invalidateNativeStream(session)
  assert runtimeInfo(runtime).registered == 0 and close(runtime)
  echo "READ_ONLY_RING_ORDERING_OK,901,3"

for pc in [471839'u32, 461066, 462062, 461614]:
  # All real signed predicates certify separately, including a loaded value on either side.
  witnessFlatReadOnlyDiscovery(decoded.value, [pc], 1)
  let copied = witnessFlatReadOnlyMixedSource(decoded.value, pc)
  let codeBytes = witnessFlatReadOnlyOrientation(decoded.value, pc)
  echo "READ_ONLY_FAMILY_LEAF,", pc, ",", copied.span, ",", copied.count, ",", codeBytes
witnessFlatReadOnlyDiscovery(decoded.value, [471839'u32, 461066, 462062, 461614], 1)
witnessFlatReadOnlyDiscovery(decoded.value, [461066'u32, 471839], 1)
echo "READ_ONLY_DISCOVERY_FAMILY_OK,4,1"
