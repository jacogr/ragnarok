# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Literal account equations and full-width arithmetic boundaries refuse before Nimony can wrap.
import std/assertions
import std/syncio
import ../../../src/state/account_footprint as state_account_footprint
import ../../../src/codec/state_accounts as codec_state_accounts
proc main() =
  ## Independent literal observations distinguish request reservation from unrelated preimage payloads.
  let zero = calculateAccountFootprint(AccountFootprintShape()).value
  assert uint32(zero.items) == 0 and uint64(zero.bytes) == 0
  let mixed = calculateAccountFootprint(AccountFootprintShape(storage: 2, requests: 3,
    storageKeyBytes: 5, storageValueBytes: 7, requestBytes: 11)).value
  assert uint32(mixed.items) == 8 and uint64(mixed.bytes) == 334
  let fixture = calculateAccountFootprint(AccountFootprintShape(storage: 1, requests: 1,
    storageKeyBytes: 2, storageValueBytes: 1, requestBytes: 3)).value
  assert uint32(fixture.items) == 3 and uint64(fixture.bytes) == 121
  let maximalItems = calculateAccountFootprint(AccountFootprintShape(storage: 1,
    requests: 2147483647'u64)).value
  assert uint32(maximalItems.items) == high(uint32)
  assert uint64(maximalItems.bytes) == 173946175441'u64
  assert calculateAccountFootprint(AccountFootprintShape(storage: 2,
    requests: 2147483647'u64)).error == AccountFootprintError.Overflow
  assert calculateAccountFootprint(AccountFootprintShape(storage: 4294967296'u64)).error ==
      AccountFootprintError.Overflow
  assert calculateAccountFootprint(AccountFootprintShape(requests: high(uint64))).error ==
      AccountFootprintError.Overflow
  let maximalBytes = calculateAccountFootprint(AccountFootprintShape(storage: 1,
    storageValueBytes: high(uint64)-34)).value
  assert uint64(maximalBytes.bytes) == high(uint64)
  assert calculateAccountFootprint(AccountFootprintShape(storage: 1,
    storageValueBytes: high(uint64)-33)).error == AccountFootprintError.Overflow
  assert calculateAccountFootprint(AccountFootprintShape(storageKeyBytes: high(uint64),
    storageValueBytes: 1)).error == AccountFootprintError.Overflow
  let requestMax = calculateAccountFootprint(AccountFootprintShape(requests: 1,
    requestBytes: high(uint64)-81)).value
  assert uint64(requestMax.bytes) == high(uint64)
  assert calculateAccountFootprint(AccountFootprintShape(requests: 1,
    requestBytes: high(uint64)-80)).error == AccountFootprintError.Overflow
  for count in 0..64:
    let prior = calculateAccountFootprint(AccountFootprintShape(storage: uint64(count),
      storageKeyBytes: uint64(count*2), storageValueBytes: uint64(count*3))).value
    let next = calculateAccountFootprint(AccountFootprintShape(storage: uint64(count),
      storageKeyBytes: uint64(count*2), storageValueBytes: uint64(count*3+1))).value
    assert uint32(prior.items) == uint32(next.items)
    assert uint64(next.bytes) == uint64(prior.bytes)+1 # A one-byte payload increase changes no item counts or overhead.
  let untouched = default(AccountFootprintResult)
  assert untouched.error == AccountFootprintError.Uninitialized
  echo "state-account-footprint: ok"
main()
