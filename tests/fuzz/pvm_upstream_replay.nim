# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Standalone bounded replay retains ordinary Nimony startup and fatal assertion semantics.
import std/[assertions, syncio, cmdline]
import ./pvm_upstream_target
if paramCount() == 0: quit(2)
for index in 1..paramCount():
  # Read at most the documented cap plus one byte; oversized/truncated files cannot pass.
  var file: File = nil
  if not open(file, paramStr(index), fmRead): quit(2)
  var bytes = newSeq[byte](UpstreamFrameBytes+1)
  let count = readBuffer(file, addr bytes[0], bytes.len)
  close(file)
  if count < 0 or count > UpstreamFrameBytes: quit(2)
  bytes.setLen(count)
  assert exerciseUpstreamFrame(bytes), "invalid upstream replay frame"
echo "PVM upstream replay passed: ", paramCount()
