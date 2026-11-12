# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Initial engine wiring checks; independent execution corpus follows separately.

import std/assertions
import ../[engine, memory_layout]

proc smoke() =
  ## One host call, a register write, then return through the sentinel guest register.
  let framed = sharedBytes([0'u8, 0, 8, 10, 7, 51, 2, 42, 50, 0, 0, 0x25])
  let admitted = fromParts(ProgramParts(encodedCode: framed))
  assert admitted.ok
  let layout = buildLayout(4096, 0, 0, 0, 0, default(SharedBytes), default(SharedBytes))
  assert layout.ok
  let admission = newModule(admitted.blob, false)
  assert admission.ok
  let module = admission.module
  var instance = newInstance(module)
  instance.regs[0] = 0xffff0000'u64
  instance.gas = 1000000
  instance.setNextPc(0)
  let first = instance.run()
  assert first.kind == InterruptKind.Ecalli and first.hostcall == 7
  assert instance.pcValid and instance.pc == 0 and instance.nextPc == 2
  let cached = instance.cacheBytes
  let second = instance.run()
  assert second.kind == InterruptKind.Finished
  assert instance.regs[2] == 42
  assert instance.cacheBytes == cached
  instance.resetMemory()
  assert instance.cacheBytes == cached
  instance.setNextPc(0)
  instance.gas = 0
  assert instance.run().kind == InterruptKind.NotEnoughGas
  instance.gas = 1000000
  assert instance.run().kind == InterruptKind.Ecalli

smoke()
