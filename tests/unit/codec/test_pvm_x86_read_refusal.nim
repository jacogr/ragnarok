# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Invalid copied read requests decline before producing any native instructions.

import std/[assertions, syncio]
import ../../../src/pvm/program
import ../../../src/pvm/internal/[native_read_body, x86_jit]

for mask in [0x2000'u32, 0x7f, high(uint32)]:
  # A malformed mask never returns a partial bank or a callable byte prefix.
  let bank = x86ResidentAccess(mask)
  assert bank.error == X86EmissionError.InvalidRegister
  var code = default(X86Block)
  emitX86ResidentOperation(code, bank, 20, default(RegisterSlots), 42)
  assert code.error == X86EmissionError.InvalidRegister and takeX86Instructions(code).len == 0
let bank = x86ResidentAccess(0x3f)
assert bank.error == X86EmissionError.None
var control = default(X86Block)
emitX86ResidentOperation(control, bank, 20, default(RegisterSlots), 42)
assert control.error == X86EmissionError.None and takeX86Instructions(control).len > 0
# Ordinary native read qualification must not expose the assertion-based legacy cache owner.
when declared(newX86Jit):
  {.error: "legacy native owner leaked into the ordinary read profile".}

when NativeCheckedReadEnabled:
  # The production read ABI is selected only on Linux x86; portable mapping cases above still run elsewhere.
  assert x86CheckedReadInstructions(default(NativeReadBody)).len == 0
  witnessX86ReadGuards()
echo "PVM x86 read refusal passed"
