# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Seal metadata-complete local branches for bounded x86 Read-cycle and mixed-loop leaves.
## Included after X86CycleFixup; callers retain admission, ABI and pre-relaxation size checks.

when declared(X86Block) and declared(X86CycleFixup):
  func x86LocalPosition(fixes: openArray[X86CycleFixup], savings: openArray[byte],
      original: int): int =
    ## Map an original boundary after selected, disjoint branch contractions.
    assert fixes.len == savings.len
    result = original
    for index in 0..<fixes.len:
      # A boundary before this displacement retains every byte of this edge.
      if fixes[index].at+4 <= original: result -= int(savings[index])

  proc sealX86LocalEdges(code: var X86Block, fixes: openArray[X86CycleFixup],
      labels: openArray[int]): seq[byte] =
    ## Record all relative fields as sorted disjoint rel32 edges with instruction-boundary labels.
    ## Each edge contracts once; distances never grow, so the monotone fixed point is finite.
    ## Preserve other bytes and entry zero; retain the caller's conservative pre-relax 4 KiB cap.
    var savings = newSeq[byte](fixes.len)
    var starts = newSeq[int](fixes.len)
    var shortOpcodes = newSeq[byte](fixes.len)
    var previousEnd = 0
    for index in 0..<fixes.len:
      # Fixups describe complete original rel32 instructions in emission order.
      let fix = fixes[index]
      assert fix.at >= 1 and fix.at+4 <= code.bytes.len
      if code.bytes[fix.at-1] == 0xe9:
        starts[index] = fix.at-1
        shortOpcodes[index] = 0xeb
      else:
        assert fix.at >= 2 and code.bytes[fix.at-2] == 0x0f
        assert code.bytes[fix.at-1] >= 0x80 and code.bytes[fix.at-1] <= 0x8f
        starts[index] = fix.at-2
        shortOpcodes[index] = code.bytes[fix.at-1]-0x10
      assert starts[index] >= previousEnd
      previousEnd = fix.at+4
      let target = labels[int(fix.target)]
      assert target >= 0 and target < code.bytes.len
    for fix in fixes:
      # No recorded target may land within any instruction being contracted.
      let target = labels[int(fix.target)]
      for index in 0..<fixes.len:
        assert target <= starts[index] or target >= fixes[index].at+4

    var changed = true
    while changed:
      # At most one transition per edge is possible; no selected edge widens again.
      changed = false
      for index in 0..<fixes.len:
        if savings[index] != 0: continue
        let fix = fixes[index]
        let saved = byte(fix.at+4-starts[index]-2)
        let start = x86LocalPosition(fixes, savings, starts[index])
        var target = x86LocalPosition(fixes, savings, labels[int(fix.target)])
        if labels[int(fix.target)] >= fix.at+4:
          # A forward target also moves when this same edge becomes shorter.
          target -= int(saved)
        let delta = target-(start+2)
        if delta >= -128 and delta <= 127:
          savings[index] = saved
          changed = true

    result = @[]
    var cursor = 0
    for index in 0..<fixes.len:
      # Preserve every nonbranch byte, including all guards and memory operations.
      let fix = fixes[index]
      while cursor < starts[index]:
        result.add(code.bytes[cursor])
        inc cursor
      assert result.len == x86LocalPosition(fixes, savings, starts[index])
      let target = x86LocalPosition(fixes, savings, labels[int(fix.target)])
      if savings[index] != 0:
        let delta = target-(result.len+2)
        assert delta >= -128 and delta <= 127
        result.add(shortOpcodes[index])
        result.add(byte(cast[uint32](int32(delta)) and 255))
      else:
        # A remaining long edge keeps its condition and exact mapped target.
        while cursor < fix.at:
          result.add(code.bytes[cursor])
          inc cursor
        let delta = cast[uint32](int32(target-(result.len+4)))
        for shift in 0..<4: result.add(byte((delta shr (shift*8)) and 255))
      cursor = fix.at+4
    while cursor < code.bytes.len:
      result.add(code.bytes[cursor])
      inc cursor
    assert result.len == x86LocalPosition(fixes, savings, code.bytes.len)
