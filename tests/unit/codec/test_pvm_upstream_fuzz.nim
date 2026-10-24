# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen upstream-generated JAM cases replay in ordinary tests without Rust, libFuzzer or network.
import std/[assertions, syncio, envvars]
import ../../fuzz/pvm_upstream_target

proc main() {.raises.} =
  ## Source-owned fixture hashes bind each original raw Arbitrary input to its two public reference frames.
  for name in ["fault", "halt", "loop-gas", "mapped-store", "trap-register"]:
    # The original generated operations run with zeroed and mapped-memory register profiles.
    for profile in ["0", "1"]:
      let text = readFile(getEnv("RAGNAROK_PVM_UPSTREAM_FUZZ") & "/" & name & "-" & profile & ".bin")
      var data = newSeq[byte](text.len)
      for index in 0..<text.len:
        # Byte conversion is test framing only; the production decoder receives the original JAM wire bytes.
        data[index] = byte(text[index])
      assert exerciseUpstreamFrame(data)
      for count in [0, 8, 248, data.len-1]:
        # Truncation cannot become a silently successful replay comparison.
        var truncated = newSeq[byte](count)
        for index in 0..<count:
          truncated[index] = data[index]
        assert not exerciseUpstreamFrame(truncated)
      data[0] = 0
      assert not exerciseUpstreamFrame(data)
  assert not exerciseUpstreamFrame(newSeq[byte](UpstreamFrameBytes+1))
  echo "PVM upstream frozen execution passed: 10"
try: main()
except: quit(2) # Missing fixture input is a setup failure; semantic assertion failures remain fatal.
