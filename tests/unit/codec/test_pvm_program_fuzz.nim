# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen valid fuzz seeds, every truncation and deterministic single-bit mutations replay the exact native target; retained lifetimes return to ARC baseline.
# @@Verification={"arc": "pvm_program_fuzz_arc_release"}
import std/[assertions, syncio, envvars]
import ../../fuzz/pvm_program_target
import ../../support/arc_evidence
proc main() {.raises.} =
  ## Fixture identities are checked by the source-owned native descriptor before deterministic replay.
  var inputs: seq[seq[byte]] = @[]
  for name in ["minimal-paper.bin", "literal-jam.bin", "zero-width-table.bin", "branch-loop.bin"]:
    let text = readFile(getEnv("RAGNAROK_PVM_PROGRAM_FUZZ") & "/" & name)
    var bytes = newSeq[byte](text.len)
    for index in 0..<bytes.len: bytes[index] = byte(text[index])
    assert exerciseProgramBytes(bytes) # Each original seed must reach complete decoder/property success.
    inputs.add(bytes)
    for count in 0..<bytes.len:
      var truncated = newSeq[byte](count)
      for index in 0..<count: truncated[index] = bytes[index]
      assert not exerciseProgramBytes(truncated)
    for index in 0..<bytes.len:
      for bit in 0..<8:
        var changed = newSeq[byte](bytes.len)
        for position in 0..<bytes.len: changed[position] = bytes[position]
        changed[index] = changed[index] xor (1'u8 shl bit)
        discard exerciseProgramBytes(changed) # A mutation may accept or refuse, but cannot violate successful snapshot properties.
  assert not exerciseProgramBytes([])
  assert not exerciseProgramBytes(newSeq[byte](ProgramFuzzBytes+1))
  let before = getOccupiedMem()
  for cycle in 0..<1000:
    for bytes in inputs: assert exerciseProgramBytes(
        bytes) # All decoder owners and copied observations retire inside each callback.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("pvm_program_fuzz", 1000, before, after)
  echo "PVM program fuzz target passed"
  echo "ARC_RELEASE cycles=1000 unchanged"
try: main()
except: quit(2) # Missing or unreadable frozen seeds must fail the suite, never skip properties.
