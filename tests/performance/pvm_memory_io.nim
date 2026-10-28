# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Measure native byte-range, page capture and image APIs; validate complete copied results outside both clocks.
import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import ../../src/pvm/machine as pvm_machine
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
let blank = captureMemory([], PageLimit(32)).value
for ordinal in 0..<11:
  # Reversing the bounded case order checks simple first/last bias in a separate process.
  let identity = if getEnv("RAGNAROK_PVM_MEMORY_REVERSE") == "1": 10-ordinal else: ordinal
  let sizes = [512, 512, 4096, 4096, 65536, 65536, 4096, 65536, 4096, 131072, 131072]
  let kinds = ["read", "write", "read", "write", "read", "write", "capture", "capture", "image",
      "reserve", "clear"]
  let size = sizes[identity]
  let kind = kinds[identity]
  var input = newSeq[byte](size)
  for index in 0..<size: input[index] = byte((index*17+41) mod 251)
  for sample in 0..<13:
    # Fresh result slots are initialized outside timing; each call retains its independently owned result.
    var reads = default(array[128, MachineResult[seq[byte]]])
    var writes = default(array[128, MachineResult[Memory]])
    var observed = default(array[128, MachineResult[PageImage]])
    let wall = getMonoTime().ticks
    let cpu = cpuNanoseconds()
    if kind == "write":
      for repeat in 0..<128:
        writes[repeat] = writeBytes(source, MemoryAddress(65553), input, MemoryByteLimit(uint64(size)))
    elif kind == "read":
      # Retain every independent copied byte result until validation and untimed retirement.
      for repeat in 0..<128:
        reads[repeat] = readBytes(source, MemoryAddress(65553), MemoryLength(uint64(size)),
            MemoryByteLimit(uint64(size)))
    elif kind == "capture":
      # Capture an explicitly bounded borrowed prefix; no caller-owned PageImage storage may escape.
      for repeat in 0..<128:
        writes[repeat] = captureMemory(images.toOpenArray(0, size div 4096-1), PageLimit(uint32(
            size div 4096)))
    elif kind == "reserve":
      # Materialize an initially absent32-page interval without including empty-source preparation in timing.
      for repeat in 0..<128:
        writes[repeat] = withWritablePages(blank, PageIndex(16), PageIndex(48))
    elif kind == "clear":
      # Clear retained nonzero pages through the same immutable trusted range boundary used by host paging.
      for repeat in 0..<128:
        writes[repeat] = withPageRange(source, PageIndex(16), PageIndex(48), PageAccess.ReadWrite,
            PageContent.Zeroed)
    else:
      # Materialize one complete independently copied image, including all eight private chunks.
      assert kind == "image"
      for repeat in 0..<128:
        observed[repeat] = pageImage(source, PageIndex(16))
    let cpuElapsed = cpuNanoseconds()-cpu
    let elapsed = getMonoTime().ticks-wall
    for repeat in 0..<128:
      if kind == "write":
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
      elif kind == "read":
        # Every returned byte has an independent original-address expectation.
        assert reads[repeat].error == MachineError.None
        let bytes = reads[repeat].value
        assert bytes.len == size
        for index in 0..<size: assert bytes[index] == byte((65553+index) mod 251)
      elif kind == "capture":
        # Validate every captured page and prove the borrowed prefix did not capture its neighboring source page.
        assert writes[repeat].error == MachineError.None
        for side in 0..<size div 4096:
          let image = pageImage(writes[repeat].value, PageIndex(uint32(16+side))).value
          assert image.access == PageAccess.ReadWrite
          for index in 0..<4096: assert image.bytes[index] == byte((65536+side*4096+index) mod 251)
        let absent = pageImage(writes[repeat].value, PageIndex(uint32(16+size div 4096))).value
        assert absent.access == PageAccess.Inaccessible
        for octet in absent.bytes: assert octet == 0
      elif kind == "reserve" or kind == "clear":
        # Observe every mapped zero byte and access mode, including pages sharing underlying immutable zero storage.
        assert writes[repeat].error == MachineError.None
        assert uint32(writablePageCount(writes[repeat].value, PageIndex(16), PageIndex(
            48)).value) == 32
        for side in 0..<32:
          let image = pageImage(writes[repeat].value, PageIndex(uint32(16+side))).value
          assert image.access == PageAccess.ReadWrite
          for octet in image.bytes: assert octet == 0
      else:
        # Public image materialization must copy both metadata and every byte exactly.
        assert kind == "image" and observed[repeat].error == MachineError.None
        let image = observed[repeat].value
        assert uint32(image.index) == 16 and image.access == PageAccess.ReadWrite
        for index in 0..<4096: assert image.bytes[index] == byte((65536+index) mod 251)
    for side in 0..<32:
      let image = pageImage(source, PageIndex(uint32(16+side))).value
      for index in 0..<4096: assert image.bytes[index] == byte((65536+side*4096+index) mod 251)
    assert uint32(writablePageCount(blank, PageIndex(16), PageIndex(48)).value) == 0
    echo "RANGE,", kind, ",", size, ",", sample, ",", elapsed, ",", cpuElapsed
