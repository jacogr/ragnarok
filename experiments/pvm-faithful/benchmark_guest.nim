# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical sieve/minimal/memset/Pinky requests through the standalone mutable engine.
## Whole declared memory is compared to independent reference snapshots after each call.

import std/[assertions, envvars, syncio]
import ./[engine, buffer, benchmark_common]

proc artifactBytes(path: string): Bytes =
  ## File acquisition is external to both embeddings' cold-admission interval.
  let data = local(path)
  cloneBytes(data, 0, data.len)

if getEnv("RAGNAROK_PVM_SIEVE_ASSERT_PROBE") == "1":
  assert false, "pvm sieve native assertion control"
header()
let guest = getEnv("RAGNAROK_PVM_GUEST")
assert guest in ["sieve", "minimal", "memset", "pinky"]
let input = local(getEnv("RAGNAROK_PVM_SIEVE_INPUT"))
let expected = local(getEnv("RAGNAROK_PVM_SIEVE_EXPECTED"))
let artifact = getEnv("RAGNAROK_PVM_SIEVE_ARTIFACT")
var raw = artifactBytes(artifact)
assert raw.len > 0 and raw.len <= 4*1024*1024
let cold = begin()
let source = sharedBytes(move(raw))
let parsed = parse(source)
assert parsed.ok
let blob = parsed.blob
let entry = blob.findExport("run_checked")
assert entry.found
let admission = newModule(blob, false)
assert admission.ok
let module = admission.module
assert input.len >= 136 and input[0..7] == "PVMSIV01"
let wireLength = int(word(input, 8, 4))
let limit = word(input, 16, 4)
let pages = int(word(input, 20, 4))
assert word(input, 12, 4) == uint64(entry.pc)
assert pages > 0 and pages <= 4096 and input.len == 136+wireLength+pages*4101
var registers = default(array[13, uint64])
for index in 0..<13: registers[index] = word(input, 32+index*8, 8)
let gas = int64(word(input, 24, 8))
var instance = newInstance(module)
assert instance.cacheBytes == 0
for sample in 0..<13:
  let start = if sample == 0: cold else: begin()
  let cached = instance.cacheBytes
  instance.resetMemory()
  for index in 0..<13: instance.regs[index] = registers[index]
  instance.gas = gas
  instance.setNextPc(entry.pc)
  if guest == "pinky":
    # Only Pinky's initialized snapshot overrides module data, exactly as in the reference driver.
    for page in 0..<pages:
      let at = 136+wireLength+page*4101
      let address = uint32(word(input, at, 4))*4096
      let permission = word(input, at+4, 1)
      assert permission in [1'u64, 2]
      if permission == 2:
        let bytes = cast[ptr UncheckedArray[byte]](readRawData(input, at+5))
        assert instance.writeMemory(address, toOpenArray(bytes, 0, 4095)) == HostError.None
  assert instance.cacheBytes == cached
  let exit = instance.run()
  let outputGas = instance.gas
  let time = elapsed(start)
  assert exit.kind == InterruptKind.Finished
  assert outputGas >= 0
  # Compare all thirteen registers and every declared page, independently of candidate state shape.
  assert expected.len == 120+pages*4096 and expected[0..7] == "PVMSIE01"
  assert uint64(outputGas) == word(expected, 8, 8), "sieve terminal state mismatch"
  for index in 0..<13:
    assert instance.regs[index] == word(expected, 16+index*8, 8), "sieve terminal state mismatch"
  let layout = module.memoryLayout
  var pageCount = 0
  for size in [layout.roSize, layout.rwSize, layout.stackSize]: pageCount += int(size div 4096)
  assert pageCount == pages
  if sample == 0:
    assert blob.parts.encodedCode.len == wireLength
    let code = blob.parts.encodedCode.view()
    for index in 0..<wireLength: assert code[index] == byte(input[136+index])
  var bytes = default(array[4096, byte])
  for page in 0..<pages:
    let at = 136+wireLength+page*4101
    let address = uint32(word(input, at, 4))*4096
    let permission = word(input, at+4, 1)
    assert permission in [1'u64, 2]
    assert instance.readMemory(address, bytes) == HostError.None
    for index in 0..<4096:
      assert bytes[index] == byte(expected[120+page*4096+index]), "sieve terminal state mismatch"
      if permission == 1:
        assert bytes[index] == byte(input[at+5+index]), "sieve read-only input mismatch"
  assert instance.cacheBytes >= cached and instance.cacheBytes > 0
  report(guest & "-" & $limit, sample, time, instance.cacheBytes)
echo "FAITHFUL_OK,1,guest"
