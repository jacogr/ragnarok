# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default and actual invalid-policy authentication cannot publish entropy or a retained
## authenticated header.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/[assertions, cmdline, syncio]
import ../../src/state/safrole_authentication
import ../../src/codec/[header, state_safrole]
if paramStr(1) == "forge":
  let reason = if paramStr(2) == "none": SafroleAuthError.None else: SafroleAuthError.InvalidConfig # Runtime-selected input cannot authorize manufactured success.
  discard safroleAuthFailure(reason)
  quit(0) # Reaching this line means the required failure-only factory contract was bypassed.
let outcome = if paramStr(1) == "default": default(SafroleAuthResult) else:
  authenticateSafroleSeal(default(OwnedHeader), [], [], StateTime(0), default(StateEntropy),
      default(SafroleAuthConfig)) # Actual zero-epoch refusal precedes header extraction.
assert paramStr(1) in ["default", "error"] # Unknown selectors cannot substitute for extraction protection.
assert outcome.error == (if paramStr(1) == "default": SafroleAuthError.Uninitialized else: SafroleAuthError.InvalidConfig)
echo outcome.value.ticketed
