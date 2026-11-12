# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen eleven synthetic workloads through a real retained mutable PolkaVM-style instance.
## Cold admission and every reset/restoration/host response are inside full-invocation-v1.

import std/[assertions, envvars, syncio]
import ./[engine, benchmark_common]

if getEnv("RAGNAROK_PVM_BENCH_ASSERT_PROBE") == "1":
  assert false, "pvm synthetic native assertion control"
header()
let data = local(getEnv("RAGNAROK_PVM_BENCHMARK", "tests/fixtures/pvm-benchmark.bin"))
assert data.len >= 12 and data[0..7] == "PVMBEN01" and word(data, 8, 4) == 11
var cursor = 12
for row in 0..<11:
  assert data.len-cursor >= 273
  let at = cursor
  let length = int(word(data, at, 4))
  let kind = word(data, at+4, 1)
  let iterations = word(data, at+5, 4)
  let address = word(data, at+9, 4)
  let initial = word(data, at+13, 8)
  let price = word(data, at+29, 8)
  let haltPrice = word(data, at+49, 8)
  let secondPrice = if kind == 5: initial else: 0'u64
  assert kind <= 5 and iterations > 0 and iterations <= 10000
  assert price > 0 and price < 1000 and haltPrice > 0 and haltPrice < 1000
  cursor += 273
  assert length >= 4 and length <= 128 and length <= data.len-cursor
  let cold = begin()
  let admitted = fromParts(ProgramParts(encodedCode: sharedBytes(data, cursor, length)))
  assert admitted.ok
  let admission = newModule(admitted.blob, kind in [1'u64, 2, 4])
  assert admission.ok
  let module = admission.module
  var instance = newInstance(module)
  assert instance.cacheBytes == 0
  cursor += length
  for sample in 0..<13:
    let start = if sample == 0: cold else: begin()
    # Rust constructs this invocation's original region inside the same primary window.
    var original = newSeq[byte](8192)
    for index in 0..<original.len: original[index] = 33
    let pairs = if kind == 4: 64 else: 1
    if kind in [1'u64, 2, 4]:
      assert address in [0x10000'u64, 0x10fff]
      let at = int(address-65536)
      for index in 0..<8: original[at+index] = byte(initial shr (8*index))
    let cached = instance.cacheBytes
    instance.resetMemory()
    assert instance.cacheBytes == cached
    if kind in [1'u64, 2, 4]:
      for pair in 0..<pairs:
        let base = 0x10000'u32 + uint32(pair)*16384
        assert instance.mapZeroMemory(base, 8192, false) == HostError.None
        if pair == 0:
          assert instance.writeMemory(base, original) == HostError.None
        else:
          var canary = default(array[8192, byte])
          for index in 0..<canary.len: canary[index] = 33
          assert instance.writeMemory(base, canary) == HostError.None
    for index in 0..<13: instance.regs[index] = word(data, at+65+index*8, 8)
    instance.gas = int64(iterations*(price+secondPrice)+haltPrice+7)
    instance.setNextPc(0)
    var calls = 0'u64
    while true:
      let exit = instance.run()
      if exit.kind == InterruptKind.Finished: break
      assert exit.kind == InterruptKind.Ecalli
      if exit.hostcall == 13: instance.regs[7] += 1
      else:
        assert exit.hostcall == 14
        instance.regs[8] += instance.regs[7]
      calls += 1
    let outputGas = instance.gas
    let outputRegisters = instance.regs
    let time = elapsed(start)
    # Every byte/state check is outside the timing window and precedes accepted output.
    assert outputGas == 7
    assert calls == (if kind == 2: iterations*2 else: 0'u64)
    for index in 0..<13:
      assert outputRegisters[index] == word(data, at+169+index*8, 8), "pvm synthetic terminal register mismatch"
    if kind in [1'u64, 2, 4]:
      let at = int(address-65536)
      let expected = word(data, cursor-length-273+21, 8)
      for index in 0..<8: original[at+index] = byte(expected shr (8*index))
      var actual = newSeq[byte](8192)
      assert instance.readMemory(65536, actual) == HostError.None
      assert actual == original, "pvm synthetic terminal memory mismatch"
      for pair in 1..<pairs:
        assert instance.readMemory(0x10000'u32+uint32(pair)*16384, actual) == HostError.None
        for value in actual: assert value == 33
    if kind == 4:
      var hole = default(array[4096, byte])
      for pair in 0..<64:
        assert instance.readMemory(0x12000'u32+uint32(pair)*16384, hole) == HostError.OutOfRange
    assert instance.cacheBytes >= cached and instance.cacheBytes > 0
    report("synthetic-" & $row, sample, time, instance.cacheBytes)
assert cursor == data.len
echo "FAITHFUL_OK,1,synthetic"
