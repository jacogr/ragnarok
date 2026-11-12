# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Full-machine differential replay: arbitrary opcode bytes, gas, host resumes,
## page faults, all registers, both PC options, code cache size and memory windows.

import std/[assertions, syncio, envvars]
import ../[engine, memory_layout, decode]

proc word(data: string, at, width: int): uint64 =
  ## Oracle scalar input is framed independently of candidate state.
  assert at >= 0 and width >= 0 and at <= data.len and width <= data.len-at
  result = 0
  for index in 0..<width: result = result or (uint64(byte(data[at+index])) shl (8*index))

proc check(actual, expected: uint64, sample, phase, step: int, field: string) =
  ## Print enough independent context to reproduce any state mismatch.
  if actual != expected:
    echo "execution sample=", sample, " phase=", phase, " step=", step,
      " field=", field, " actual=", actual, " expected=", expected
  assert actual == expected, "faithful execution state mismatch"

var data = ""
try:
  data = readFile("build/pvm-faithful/execution.bin")
except:
  quit 2
assert data.len >= 12 and data[0..7] == "PVFEXE01"
let count = int(word(data, 8, 4))
assert count == 4368
let corrupt = getEnv("RAGNAROK_FAITHFUL_CORRUPT") == "1"
var cursor = 12
var steps = 0
for sample in 0..<count:
  let length = int(word(data, cursor, 4))
  cursor += 4
  var wire = newSeq[byte](length)
  for index in 0..<length: wire[index] = byte(data[cursor+index])
  cursor += length
  let dynamic = byte(data[cursor]) == 1
  cursor += 1
  let ro = sharedBytes([1'u8, 2, 3, 4])
  let rw = sharedBytes([5'u8, 6, 7, 8])
  let admitted = fromParts(ProgramParts(encodedCode: sharedBytes(wire), roSize: 4096,
    rwSize: 4096, stackSize: 4096, ro: ro, rw: rw))
  assert admitted.ok
  let validated = validateCode(admitted.blob.code.view(), admitted.blob.mask.view())
  check(uint64(validated), word(data, cursor, 4), sample, 0, 0, "module validation")
  cursor += 4
  if validated != high(uint32): continue
  var addresses = default(array[3, uint32])
  for index in 0..<3:
    addresses[index] = uint32(word(data, cursor, 4))
    cursor += 4
  let layout = buildLayout(4096, 4096, 4096, 4096, 0, ro, rw)
  assert layout.ok
  let admission = newModule(admitted.blob, dynamic)
  assert admission.ok
  let module = admission.module
  var instance = newInstance(module)
  for phase in 0..<4:
    instance.resetMemory()
    if dynamic:
      assert instance.dynamic.mapZero(65536, 4096, false)
      assert instance.dynamic.write(65536, [1'u8, 2, 3, 4])
    for index in 0..<13:
      instance.regs[index] = word(data, cursor, 8)
      cursor += 8
    instance.gas = cast[int64](word(data, cursor, 8))
    cursor += 8
    instance.setNextPc(uint32(word(data, cursor, 4)))
    cursor += 4
    let count = int(byte(data[cursor]))
    cursor += 1
    assert count >= 1 and count <= 8
    for step in 0..<count:
      let exit = instance.run()
      let expectedKind = byte(data[cursor])
      check(uint64(ord(exit.kind)), uint64(expectedKind), sample, phase, step, "interrupt")
      check(uint64(exit.hostcall), word(data, cursor+1, 4), sample, phase, step, "hostcall")
      check(uint64(exit.page), word(data, cursor+5, 4), sample, phase, step, "page")
      check(uint64(exit.pageSize), word(data, cursor+9, 4), sample, phase, step, "page size")
      check(uint64(exit.readOnly), word(data, cursor+13, 1), sample, phase, step, "write protection")
      check(uint64(instance.pcValid), word(data, cursor+14, 1), sample, phase, step, "pc presence")
      if instance.pcValid: check(uint64(instance.pc), word(data, cursor+15, 4), sample, phase, step, "pc")
      check(uint64(instance.nextPcValid), word(data, cursor+19, 1), sample, phase, step, "next pc presence")
      if instance.nextPcValid: check(uint64(instance.nextPc), word(data, cursor+20, 4), sample,
          phase, step, "next pc")
      check(cast[uint64](instance.gas), word(data, cursor+24, 8), sample, phase, step, "gas")
      check(instance.cacheBytes, word(data, cursor+32, 8), sample, phase, step, "cache bytes")
      for index in 0..<13:
        var expected = word(data, cursor+40+index*8, 8)
        if corrupt and sample == 0 and phase == 0 and step == 0 and index ==
            0: expected = expected xor 1
        check(instance.regs[index], expected, sample, phase, step, "register")
      cursor += 144
      steps += 1
      if exit.kind == InterruptKind.Ecalli:
        instance.regs[12] = uint64(step+17)
      elif exit.kind == InterruptKind.NotEnoughGas and step == 0:
        instance.gas = 2048
      elif exit.kind == InterruptKind.Segfault and step < 3:
        assert instance.dynamic.mapZero(exit.page, exit.pageSize, false)
    for address in addresses:
      var bytes = default(array[64, byte])
      let readable = if dynamic: instance.dynamic.read(address, bytes)
        else: instance.standard.read(address, bytes)
      assert readable
      for index in 0..<64:
        check(uint64(bytes[index]), word(data, cursor+index, 1), sample, phase, 8, "memory byte")
      cursor += 64
assert cursor == data.len
echo "faithful execution reference passed: ", count, " modules, ", steps, " interrupts"
