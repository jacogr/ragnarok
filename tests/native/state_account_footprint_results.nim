# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Arithmetic extraction guards require linked assertions and a genuine representable control.
import std/[assertions, cmdline, syncio]
import ../../src/state/account/footprint as account_footprint
import ../../src/codec/state/accounts as state_accounts
proc extract(outcome: AccountFootprintResult): AccountFootprint {.noinline.} =
  ## Keep default/refused payload extraction dynamic in the checked native binary.
  outcome.value
case paramStr(1)
of "default": discard extract(default(AccountFootprintResult)) # No default arithmetic observation.
of "overflow":
  let refused = calculateAccountFootprint(AccountFootprintShape(storage: high(uint64)))
  assert refused.error == AccountFootprintError.Overflow
  discard extract(refused) # No wrapped E4 count can escape.
of "ok":
  let value = extract(calculateAccountFootprint(AccountFootprintShape(storage: 1)))
  assert uint32(value.items) == 1 and uint64(value.bytes) == 34
  echo "state-account-footprint-results: ok"
else: quit(2) # Unknown selectors cannot satisfy successful controls.
