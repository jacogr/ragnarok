# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exercise recoverable heap exhaustion during complete JAM blob initialization.

import std/[assertions, syncio]
import ../../../src/pvm/[initialize, machine, program]

const PayloadBytes = 1024 * 1024
# Static input leaves the recoverable heap available for the owners created by initialization.
var blob = default(array[PayloadBytes + 21, byte])
blob[3] = 16 # E3 read-only length starts after the empty metadata prefix.
blob[PayloadBytes + 12] = 5 # E4 embedded program length.
blob[PayloadBytes + 18] = 1 # One instruction byte, followed by its start mask.
blob[PayloadBytes + 20] = 1

let limits = InitializationLimits(envelope: InitializationByteLimit(blob.len),
  program: ProgramByteLimit(5), jumps: JumpCountLimit(0), pages: PageLimit(256))
let small = [0'u8, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 5, 0, 0, 0, 0, 0, 1, 0, 1]

proc initialize(input: openArray[byte]): InitializationError =
  initializeJamProgram(input, [], CodeAddress(0), MachineGas(100), limits).error

assert initialize(small) == InitializationError.None
let occupied = getOccupiedMem()
for attempt in 0..<2:
  # The admitted payload and its page owners exceed the heap cap after some pages have been copied.
  assert initialize(blob) == InitializationError.LimitExceeded
  assert getOccupiedMem() == occupied
assert initialize(small) == InitializationError.None

# A full heap also refuses the directory allocation before any page payload is copied.
let regions = [InitializationRegion(first: PageIndex(16), past: PageIndex(17),
  access: PageAccess.ReadOnly, source: InitializationSource.First)]
let filler = alloc(PayloadBytes - getOccupiedMem())
assert filler != nil and getOccupiedMem() + sizeof(pointer) > PayloadBytes
let refused = captureInitializationMemory(regions, [], [], PageLimit(1))
dealloc(filler)
assert refused.error == MachineError.LimitExceeded
assert captureInitializationMemory(regions, [], [], PageLimit(1)).error == MachineError.None

echo "PVM initialization allocation refusal passed"
