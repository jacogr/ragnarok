# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact constant-work account deposit observations preserve gratis cancellation before representability refusal.
## Explicit arithmetic inputs are not authenticated state, protocol configuration or a global funding invariant.
import ../../codec/state/accounts as state_accounts
import ./footprint as account_footprint

type
  AccountDepositSchedule* = object ## Explicit nonnegative rates are mathematical inputs, not validated network parameters.
    base*, item*, octet*: AccountBalance
  AccountDepositError* {.pure.} = enum ## Default or mathematically unrepresentable thresholds carry no wrapped balance.
    Uninitialized, None, Overflow
  AccountDepositResult* = object ## Private alternatives expose only a checked E8 minimum balance.
    case status: AccountDepositError
    of None:
      completed: AccountBalance
    else:
      discard

func error*(outcome: AccountDepositResult): AccountDepositError =
  ## Inspect arithmetic success/refusal without exposing the discriminator.
  outcome.status

func value*(outcome: AccountDepositResult): AccountBalance {.inline,
    requires: outcome.status == AccountDepositError.None.} =
  ## Only a representable mathematical threshold can be extracted.
  outcome.completed

func calculateAccountMinimum*(footprint: AccountFootprint, gratis: AccountBalance,
    schedule: AccountDepositSchedule): AccountDepositResult =
  ## Compute max(0, base + item*items + octet*bytes - gratis) without premature product overflow.
  var credit = uint64(gratis)
  var minimum = 0'u64
  template cost(count, rate: uint64) =
    if count != 0 and rate != 0:
      let whole = credit div rate
      let paid = if count < whole: count else: whole
      credit -= paid * rate # Quotient proves this product never exceeds the remaining full-width credit.
      let unpaid = count-paid
      if unpaid != 0:
        let first = rate-credit # Unpaid work proves remaining credit is strictly below rate.
        credit = 0
        if first > high(uint64)-minimum:
          return AccountDepositResult(status: AccountDepositError.Overflow)
        minimum += first # Consume partial credit before deciding E8 representability.
        let rest = unpaid-1
        if rest > (high(uint64)-minimum) div rate:
          return AccountDepositResult(status: AccountDepositError.Overflow)
        minimum += rest * rate # Prove residual multiplication and addition together; later nonnegative terms cannot repair overflow.
  cost(1'u64, uint64(schedule.base))
  cost(uint64(footprint.items), uint64(schedule.item))
  cost(uint64(footprint.bytes), uint64(schedule.octet))
  AccountDepositResult(status: AccountDepositError.None, completed: AccountBalance(minimum))

func coversAccountMinimum*(liquid, protected, minimum: AccountBalance): bool =
  ## Compare both allowed balance pools with a representable threshold without forming an overflowing sum.
  uint64(liquid) >= uint64(minimum) or uint64(protected) >= uint64(minimum)-uint64(liquid)
