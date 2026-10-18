# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Each process must fail at its intended public result-access precondition.
import std/cmdline
import ../../src/pvm/machine
let selection = paramStr(1)
let empty = captureMemory([], PageLimit(0))
# Select an actual failed/default scalar result at runtime, preserving the compiler's checked path.
if selection == "default-value" or selection == "error-value" or selection == "fault-value":
  let outcome = if selection == "fault-value":
    load(empty.value, MemoryAddress(65536), AccessWidth(1))
  elif selection == "error-value":
    # A default owner is a local API failure and never contains a readable scalar.
    load(default(Memory), MemoryAddress(65536), AccessWidth(1))
  else:
    # Default results cannot manufacture zero-valued success.
    default(MachineResult[RegisterValue])
  discard outcome.value
elif selection == "panic-page":
  # A panic carries no page-fault address even though it arose from a memory access.
  let outcome = load(empty.value, MemoryAddress(0), AccessWidth(1))
  discard outcome.faultPage
else:
  # A successful owner has no failure address; this must fail the Fault-only contract.
  discard empty.faultPage
