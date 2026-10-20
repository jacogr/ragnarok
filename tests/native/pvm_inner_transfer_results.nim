# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized response-access guards preserve explicit local failures for both inner transfer directions.

import std/[assertions, cmdline]
import ../../src/pvm/[inner_machines, machine]
import ../support/pvm_inner_transfer

proc check(outcome: InnerMachineResult[InnerMachineTransition], expected: InnerMachineError) =
  ## Confirm the selected alternative without exposing caller-static proof to the intentional misuse branch.
  assert outcome.error == expected
let memory = transferMemory()
let source = transferMachines()
let peek = innerPeekResponse(source, MachineGas(10000), transferRegisters(caller = 200702), memory,
    MemoryByteLimit(4))
let poke = innerPokeResponse(source, MachineGas(10000), transferRegisters(), memory,
    MemoryByteLimit(4))
check(peek, InnerMachineError.None)
check(poke, InnerMachineError.None)
assert uint64(peek.value.response.registers[7]) == 0 and uint64(poke.value.response.registers[7]) == 0
let peekCap = innerPeekResponse(source, MachineGas(10000), transferRegisters(caller = 200702),
    memory, MemoryByteLimit(3))
let pokeCap = innerPokeResponse(source, MachineGas(10000), transferRegisters(), memory,
    MemoryByteLimit(3))
check(peekCap, InnerMachineError.LimitExceeded)
check(pokeCap, InnerMachineError.LimitExceeded)
let peekDefault = innerPeekResponse(default(InnerMachines), MachineGas(10000), transferRegisters(),
    memory, MemoryByteLimit(4))
let pokeDefault = innerPokeResponse(default(InnerMachines), MachineGas(10000), transferRegisters(),
    memory, MemoryByteLimit(4))
check(peekDefault, InnerMachineError.InvalidContext)
check(pokeDefault, InnerMachineError.InvalidContext)
let peekMemory = innerPeekResponse(source, MachineGas(10000), transferRegisters(), default(Memory),
    MemoryByteLimit(4))
let pokeMemory = innerPokeResponse(source, MachineGas(10000), transferRegisters(), default(Memory),
    MemoryByteLimit(4))
check(peekMemory, InnerMachineError.InvalidMemory)
check(pokeMemory, InnerMachineError.InvalidMemory)
case paramStr(1)
of "peek-cap": discard peekCap.value # Local copy policy carries no partially written caller memory.
of "poke-cap": discard pokeCap.value # Local copy policy carries no partially written inner map.
of "peek-default": discard peekDefault.value # Invalid map ownership cannot fabricate a charged response.
of "poke-default": discard pokeDefault.value # Invalid map ownership cannot fabricate a charged response.
of "peek-memory": discard peekMemory.value # Invalid caller memory is a local API refusal.
else: discard pokeMemory.value # Invalid caller memory is a local API refusal.
