# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Canonical DOOM init/tick embedding: the same five host imports, owned output
## payloads, retained interpreter and complete warmup-1320 state/event validation.

import std/[assertions, envvars, syncio]
import ./[engine, buffer, decode, benchmark_common]

type
  Event = object
    ## Each output owns its byte vector; host collection does not serialize or hash payloads.
    kind: byte
    bytes: Bytes
  Events = object
    ## The source bounded event vector and total encoded length, retained until post-clock validation.
    records: seq[Event]
    length: int

proc artifactBytes(path: string): Bytes =
  ## Both embeddings acquire files before their encompassing cold-admission clock.
  let data = local(path)
  cloneBytes(data, 0, data.len)

proc runDoom(instance: var Instance, hosts: array[5, uint32], rom: string): Events {.noinline.} =
  ## Apply exactly the source five host operations; unexpected exits or more than 4096 calls fail.
  var events = default(Events)
  for hostStep in 0..<4096:
    let exit = instance.run()
    if exit.kind == InterruptKind.Finished: return move(events)
    assert exit.kind == InterruptKind.Ecalli
    var kind = -1
    for index in 0..<hosts.len:
      if hosts[index] == exit.hostcall:
        kind = index
        break
    assert kind >= 0
    let a = instance.regs[7]
    let b = instance.regs[8]
    let c = instance.regs[9]
    assert a <= uint64(high(uint32))
    let address = uint32(a)
    case kind
    of 2:
      # ROM host input is borrowed and copied directly to the retained guest allocation.
      assert b <= uint64(rom.len) and c <= uint64(rom.len)-b
      if c == 0:
        assert instance.writeMemory(address, []) == HostError.None
      else:
        let bytes = cast[ptr UncheckedArray[byte]](readRawData(rom, int(b)))
        assert instance.writeMemory(address, toOpenArray(bytes, 0, int(c)-1)) == HostError.None
    of 3:
      instance.regs[7] = uint64(rom.len)
    of 0, 1, 4:
      let length = if kind == 0:
          assert b <= high(uint64) div 4
          b*4
        elif kind == 1:
          assert b == 640 and c == 400
          b*c*4
        else: b
      assert length <= 1048576
      # Rust read_memory allocates uninitialized storage and fills it; do not add a zero-fill pass.
      var payload = default(Bytes)
      payload.reserveExact(int(length))
      payload.len = int(length)
      if length != 0:
        let bytes = payload.data
        assert bytes != nil
        var output = toOpenArray(bytes, 0, int(length)-1)
        assert instance.readMemory(address, output) == HostError.None
      else:
        var empty = default(array[0, byte])
        assert instance.readMemory(address, empty) == HostError.None
      assert events.length <= 4*1024*1024-5-int(length)
      events.length += 5+int(length)
      events.records.add(Event(kind: byte(kind), bytes: move(payload)))
      if kind == 4: instance.regs[7] = b
    else:
      assert false, "foreign DOOM host"
  assert false, "DOOM host budget exhausted"
  move(events)

proc validate(events: Events, expected: string) =
  ## Compare exact framing and every payload byte after timing; no framebuffer-only shortcut.
  assert events.length == expected.len, "DOOM event mismatch"
  var at = 0
  for index in 0..<events.records.len:
    assert word(expected, at, 1) == uint64(events.records[index].kind), "DOOM event mismatch"
    let length = events.records[index].bytes.len
    assert word(expected, at+1, 4) == uint64(length), "DOOM event mismatch"
    at += 5
    for byteIndex in 0..<length:
      assert events.records[index].bytes.readByte(byteIndex) == byte(expected[at+byteIndex]), "DOOM event mismatch"
    at += length
  assert at == expected.len

if getEnv("RAGNAROK_PVM_DOOM_ASSERT") == "1":
  assert false, "doom native assertion control"
header()
let phase = getEnv("RAGNAROK_PVM_DOOM_PHASE")
assert phase in ["init", "tick"]
let folder = getEnv("RAGNAROK_PVM_DOOM_INPUT")
let input = local(folder & "/" & phase & ".input")
let expected = local(folder & "/" & phase & ".expected")
let expectedEvents = local(folder & "/" & phase & ".events")
let rom = local(getEnv("RAGNAROK_PVM_DOOM_ROM"))
assert rom.len == 4196020
var raw = artifactBytes(getEnv("RAGNAROK_PVM_DOOM_ARTIFACT"))
let cold = begin()
let source = sharedBytes(move(raw))
let parsed = parse(source)
assert parsed.ok
let blob = parsed.blob
assert validateCode(blob.code.view(), blob.mask.view()) == high(uint32)
const names = ["ext_output_audio", "ext_output_video", "ext_rom_read", "ext_rom_size", "ext_stdout"]
var hosts = default(array[5, uint32])
for index in 0..<hosts.len:
  let found = blob.findImport(names[index])
  assert found.found
  hosts[index] = found.index
assert blob.parts.importOffsets.len div 4 == hosts.len
let entryInit = blob.findExport("ext_initialize")
let entryTick = blob.findExport("ext_tick")
assert entryInit.found and entryTick.found
let entry = if phase == "init": entryInit.pc else: entryTick.pc
let admission = newModule(blob, false)
assert admission.ok
let module = admission.module
assert input.len >= 152 and input[0..7] == "PVMDOM01"
let wireLength = int(word(input, 8, 4))
let pages = int(word(input, 16, 4))
assert wireLength <= 4*1024*1024 and pages > 0 and pages <= 8192
assert input.len == 152+wireLength+pages*4101 and word(input, 12, 4) == uint64(entry)
var registers = default(array[13, uint64])
for index in 0..<13: registers[index] = word(input, 48+index*8, 8)
let gas = int64(word(input, 40, 8))
var instance = newInstance(module)
assert instance.cacheBytes == 0
for sample in 0..<13:
  let start = if sample == 0: cold else: begin()
  let cached = instance.cacheBytes
  instance.resetMemory()
  for index in 0..<13: instance.regs[index] = registers[index]
  instance.setNextPc(entry)
  instance.gas = gas
  for page in 0..<pages:
    let at = 152+wireLength+page*4101
    let address = uint32(word(input, at, 4))*4096
    let permission = word(input, at+4, 1)
    assert permission in [1'u64, 2]
    if permission == 2:
      let bytes = cast[ptr UncheckedArray[byte]](readRawData(input, at+5))
      assert instance.writeMemory(address, toOpenArray(bytes, 0, 4095)) == HostError.None
  assert instance.cacheBytes == cached
  let events = runDoom(instance, hosts, rom)
  let outputGas = instance.gas
  let time = elapsed(start)
  assert outputGas >= 0 and not instance.pcValid
  if sample == 0:
    assert blob.parts.encodedCode.len == wireLength
    let code = blob.parts.encodedCode.view()
    for index in 0..<wireLength: assert code[index] == byte(input[152+index])
    for index in 0..<hosts.len: assert uint64(hosts[index]) == word(input, 20+index*4, 4)
  assert expected.len == 120+pages*4096 and expected[0..7] == "PVMDOME1"
  assert uint64(outputGas) == word(expected, 8, 8), "DOOM terminal state mismatch"
  for index in 0..<13:
    assert instance.regs[index] == word(expected, 16+index*8, 8), "DOOM terminal state mismatch"
  var bytes = default(array[4096, byte])
  for page in 0..<pages:
    let at = 152+wireLength+page*4101
    let address = uint32(word(input, at, 4))*4096
    let permission = word(input, at+4, 1)
    assert instance.readMemory(address, bytes) == HostError.None
    for index in 0..<4096:
      assert bytes[index] == byte(expected[120+page*4096+index]), "DOOM terminal state mismatch"
      if permission == 1: assert bytes[index] == byte(input[at+5+index]), "DOOM read-only input mismatch"
  events.validate(expectedEvents)
  assert instance.cacheBytes >= cached and instance.cacheBytes > 0
  report("doom-" & phase, sample, time, instance.cacheBytes)
echo "FAITHFUL_OK,1,doom"
