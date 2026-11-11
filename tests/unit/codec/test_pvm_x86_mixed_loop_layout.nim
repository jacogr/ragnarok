# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Preserve every x86 mixed-loop edge through signed-width changes and fixed-point cascades.

import std/[assertions, syncio]
import ../../../src/pvm/internal/[native_ir, x86_jit]

when NativeReadCycleEnabled:
  # Unsupported hosts retain the portable output contract; Linux x86 executes the exact cases.
  for condition in 0..16:
    # Include every signed/unsigned Jcc condition and the unconditional form.
    let encoded = if condition == 0: 0'u8 else: byte(0x7f+condition)
    let shortOpcode = if condition == 0: 0xeb'u8 else: encoded-0x10
    for padding in [0, 125, 126, 127, 128, 129, 255, 256]:
      for backward in [false, true]:
        # Literal expected displacements include both limits and their nearest misses.
        let shortDelta = if backward: -(padding+2) else: padding
        let short = shortDelta >= -128 and shortDelta <= 127
        let longLength = if condition == 0: 5 else: 6
        let edgeLength = if short: 2 else: longLength
        let image = x86MixedLoopRelaxProof(padding, backward, encoded)
        assert image.len == padding+edgeLength+1
        let at = if backward: padding else: 0
        assert image[image.len-1] == 0xc3
        for index in 0..<padding:
          # No scalar byte may move into a branch or change while positions contract.
          assert image[(if backward: index else: edgeLength+index)] == 0x90
        if short:
          assert image[at] == shortOpcode
          assert image[at+1] == byte(cast[uint32](int32(shortDelta)) and 255)
        else:
          if condition == 0: assert image[at] == 0xe9
          else: assert image[at] == 0x0f and image[at+1] == encoded
          let delta = if backward: -(padding+longLength) else: padding
          for shift in 0..<4:
            assert image[at+edgeLength-4+shift] ==
              byte((cast[uint32](int32(delta)) shr (shift*8)) and 255)
  let cascade = x86MixedLoopRelaxCascadeProof()
  assert cascade.len == 129 and cascade[0] == 0x75 and cascade[1] == 126
  for index in 2..<126: assert cascade[index] == 0x90
  assert cascade[126] == 0xeb and cascade[127] == 0 and cascade[128] == 0xc3
echo "PASS x86 mixed-loop branch layout"
