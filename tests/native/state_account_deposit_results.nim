# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Checked minimum-balance payload guards require a representable independent positive control.
import std/assertions
import std/cmdline
import std/syncio
import ../../src/state/account_deposit as state_account_deposit
import ../../src/state/account_footprint as state_account_footprint
import ../../src/codec/state_accounts as codec_state_accounts
proc extract(outcome: AccountDepositResult): AccountBalance {.noinline.} =
  ## Dynamic failed/default arithmetic must never expose wrapped minimums.
  outcome.value
case paramStr(1)
of "default": discard extract(default(AccountDepositResult)) # Default grants no computed balance.
of "overflow":
  let result = calculateAccountMinimum(AccountFootprint(bytes: AccountStorageBytes(high(uint64))),
      AccountBalance(0), AccountDepositSchedule(octet: AccountBalance(2)))
  assert result.error == AccountDepositError.Overflow
  discard extract(result) # A mathematically overflowing threshold grants no truncated balance.
of "ok":
  let result = calculateAccountMinimum(AccountFootprint(items: AccountStorageItems(3),
      bytes: AccountStorageBytes(121)), AccountBalance(20),
    AccountDepositSchedule(base: AccountBalance(100), item: AccountBalance(2),
        octet: AccountBalance(3)))
  assert uint64(extract(result)) == 449
  echo "state-account-deposit-results: ok"
else: quit(2) # Unknown modes cannot pass controls.
