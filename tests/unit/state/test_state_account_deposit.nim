# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent small-integer equations and full-width cancellation literals qualify exact deposit observations.
import std/[assertions, syncio]
import ../../../src/state/account/[deposit as account_deposit, footprint as account_footprint]
import ../../../src/codec/state/accounts as state_accounts
proc minimum(items: uint32, bytes, gratis, base, item, octet: uint64): AccountDepositResult =
  ## Pass explicit nominal mathematical inputs, independent of source or parameter authentication.
  calculateAccountMinimum(AccountFootprint(items: AccountStorageItems(items),
      bytes: AccountStorageBytes(bytes)), AccountBalance(gratis),
    AccountDepositSchedule(base: AccountBalance(base), item: AccountBalance(item),
        octet: AccountBalance(octet)))
let maximum = high(uint64)
assert uint64(minimum(0, 0, maximum, maximum, 0, 0).value) == 0
assert uint64(minimum(1, 0, maximum, maximum, maximum, 0).value) == maximum
assert uint64(minimum(2, 0, maximum, 0, maximum, 0).value) == maximum
assert minimum(3, 0, maximum, 0, maximum, 0).error == AccountDepositError.Overflow
assert uint64(minimum(1, 0, 1, maximum, 1, 0).value) == maximum
assert uint64(minimum(0, 2, maximum, 0, 0, maximum).value) == maximum
assert minimum(0, 3, maximum, 0, 0, maximum).error == AccountDepositError.Overflow
assert uint64(minimum(0, maximum, maximum, maximum, 0, 1).value) == maximum
assert minimum(high(uint32), maximum, maximum, maximum, maximum, maximum).error ==
    AccountDepositError.Overflow
assert uint64(minimum(3, 121, 20, 100, 2, 3).value) == 449
assert uint64(minimum(0, 0, maximum, 0, maximum, maximum).value) == 0
assert uint64(minimum(3, 121, maximum, 1, 2, 3).value) == 0
for count in 0'u64..10:
  for rate in 0'u64..10:
    for credit in 0'u64..31:
      let raw = 7 + 3 * rate + count * rate # Small independent direct equation cannot overflow.
      let expected = if raw > credit: raw-credit else: 0'u64
      assert uint64(minimum(3, count, credit, 7, rate, rate).value) ==
          expected # Compare a direct safe integer reference with cancellation implementation.
for liquid in 0'u64..8:
  for protected in 0'u64..8:
    for threshold in 0'u64..20:
      assert coversAccountMinimum(AccountBalance(liquid), AccountBalance(protected), AccountBalance(
          threshold)) == (liquid + protected >=
          threshold) # Small direct sum independently checks pool comparison.
assert coversAccountMinimum(AccountBalance(maximum), AccountBalance(maximum), AccountBalance(maximum))
assert coversAccountMinimum(AccountBalance(1), AccountBalance(maximum), AccountBalance(maximum))
assert not coversAccountMinimum(AccountBalance(1), AccountBalance(maximum-2), AccountBalance(maximum))
assert coversAccountMinimum(AccountBalance(0), AccountBalance(0), AccountBalance(0))
let untouched = default(AccountDepositResult)
assert untouched.error == AccountDepositError.Uninitialized
echo "state-account-deposit: ok"
