# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Measure complete native host byte-range calls; check all outcomes and original pages outside both clocks.
import std/[assertions, syncio, envvars, monotimes]
import ../../src/pvm/machine
proc cpuNanoseconds(): int64 {.importc: "pvm_sieve_cpu_nanoseconds", header: "pvm_sieve_clock.h".}
  ## Fail closed on unavailable process CPU accounting through the maintained OS wrapper.
if getEnv("RAGNAROK_PVM_MEMORY_ASSERT_PROBE") == "1":
  assert false, "pvm memory range assertion control"
var images: seq[PageImage] = @[]
for side in 0..<32:
  var image = PageImage(index: PageIndex(uint32(16+side)), access: PageAccess.ReadWrite,
    bytes: default(array[4096, byte]))
  for i in 0..<4096: image.bytes[i] = byte((65536+side*4096+i) mod 251)
  images.add(image)
let source = captureMemory(images, PageLimit(32)).value
for ordinal in 0..<6:
  # Reversing the bounded case order checks simple first/last bias in a separate process.
  let identity = if getEnv("RAGNAROK_PVM_MEMORY_REVERSE") == "1": 5-ordinal else: ordinal
  let sizes = [512, 4096, 65536]
  let size = sizes[identity div 2]
  let writing = identity mod 2 == 1
  var input = newSeq[byte](size)
  for index in 0..<size: input[index] = byte((index*17+41) mod 251)
  for sample in 0..<13:
    # Fresh result slots are initialized outside timing; each call retains its independently owned result.
    var reads = default(array[128, MachineResult[seq[byte]]])
    var writes = default(array[128, MachineResult[Memory]])
    let wall = getMonoTime().ticks
    let cpu = cpuNanoseconds()
    if writing:
      for repeat in 0..<128:
        writes[repeat] = writeBytes(source, MemoryAddress(65553), input, MemoryByteLimit(uint64(size)))
    else:
      for repeat in 0..<128:
        reads[repeat] = readBytes(source, MemoryAddress(65553), MemoryLength(uint64(size)),
            MemoryByteLimit(uint64(size)))
    let cpuElapsed = cpuNanoseconds()-cpu
    let elapsed = getMonoTime().ticks-wall
    for repeat in 0..<128:
      if writing:
        assert writes[repeat].error == MachineError.None
        for side in 0..<32:
          let image = pageImage(writes[repeat].value, PageIndex(uint32(16+side))).value
          assert image.access == PageAccess.ReadWrite
          for index in 0..<4096:
            # Complete pages independently expose missing, shifted and unintended neighbor writes.
            let position = side*4096+index
            let expected = if position >= 17 and position-17 < size: byte(((
                position-17)*17+41) mod 251)
              else: byte((65536+position) mod 251)
            assert image.bytes[index] == expected
      else:
        assert reads[repeat].error == MachineError.None
        let bytes = reads[repeat].value
        assert bytes.len == size
        for index in 0..<size: assert bytes[index] == byte((65553+index) mod 251)
    for side in 0..<32:
      let image = pageImage(source, PageIndex(uint32(16+side))).value
      for index in 0..<4096: assert image.bytes[index] == byte((65536+side*4096+index) mod 251)
    echo "RANGE,", (if writing: "write" else: "read"), ",", size, ",", sample, ",", elapsed, ",", cpuElapsed
