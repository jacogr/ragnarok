# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual provide-local failures cannot expose a charged CPU or partially accumulated implication pair.

import std/cmdline
import ../../src/state/accumulation_dispatch
import ../support/pvm_accumulation_provision

## Inject backend refusal only after the complete guest/source fixture exists.
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
let argument = paramStr(1)
let call = ProvisionGuestCall(id: 27, r7: high(uint64), r8: 65536, r9: 3)
var source = provisionMachine([call])
if argument == "gas":
  source = provisionMachine([ProvisionGuestCall(id: 27, r9: high(uint64))], credit = high(
      uint64)) # Actual unrepresentable terminal debt.
if argument == "malformed":
  source = provisionMachine([call], history = @[4'u8]) # Canonical query rejects an impossible request count.
if argument == "backend":
  failHash(1) # Guest reaches the payload hash only after successful memory validation.
var outcome = runProvision(source)
if argument == "local":
  outcome = runProvision(source, provisionPolicy(items = 0)) # No capacity for the requested pair.
case argument
of "backend":
  discard outcome.effects
of "gas":
  discard outcome.effects
of "malformed":
  discard outcome.value
else:
  discard outcome.value
