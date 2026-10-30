# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
## Textually included frame checks use the caller's exact public Memory type, including archived JIT sources.
type FrameOracle = object ## Pinned external full-frame bytes and the real public getter's guest address.
  address: uint64
  bytes: string

proc readFrameOracle(): FrameOracle =
  ## Parse a bounded decimal pointer and exact 256x240 ABGR frame; all file work stays outside timers.
  var address = ""
  var bytes = ""
  try:
    address = readFile(getEnv("RAGNAROK_PVM_FRAME_ADDRESS"))
    bytes = readFile(getEnv("RAGNAROK_PVM_FRAME_BYTES"))
  except:
    assert false, "Pinky frame oracle read"
  assert address.len in 1..10 and bytes.len == 256*240*4
  var value = 0'u64
  for digit in address:
    # The pre-multiplication bound proves the decimal conversion remains a guest 32-bit address.
    assert digit >= '0' and digit <= '9'
    let part = uint64(byte(digit)-byte('0'))
    assert value <= (0xffffffff'u64-part) div 10
    value = value*10+part
  assert value >= 65536 and value <= 0x100000000'u64-uint64(bytes.len)
  FrameOracle(address: value, bytes: bytes)

proc checkFrame(memory: Memory, oracle: FrameOracle, sample: int) =
  ## Check actual published framebuffer bytes after full-state validation; never execute a guest getter here.
  var checked = 0
  while checked < oracle.bytes.len:
    # Each genuine page image retains its real permission/access proof and bounded byte extent.
    let address = oracle.address+uint64(checked)
    let found = pageImage(memory, PageIndex(uint32(address shr 12)))
    assert found.error == MachineError.None
    let page = found.value
    let start = int(address and 4095)
    let extent = min(4096-start, oracle.bytes.len-checked)
    for i in 0..<extent:
      assert page.bytes[start+i] == byte(oracle.bytes[checked+i]), "Pinky rendered frame byte"
    checked += extent
  echo "PINKY_FRAME,", sample, ",", oracle.address, ",", checked
