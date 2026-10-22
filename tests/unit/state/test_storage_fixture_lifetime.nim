# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixture-only lifetime checks distinguish live prepared payloads from actual ARC-retired scopes.
import std/[assertions, syncio]
import ../../support/[storage_lifetime_samples, storage_allocations]

let before = occupiedStorageBytes()
for count in [1024, 8192]:
  # Both fixture extents release all graph owners before returning scalar observations.
  let observed = fixtureLifetime(count)
  assert observed.checks == count+64
  assert observed.owner == -1 and observed.held == -1 and observed.closed == -1
  assert observed.fixture > observed.baseline and observed.released == observed.baseline
assert occupiedStorageBytes() == before
echo "PASS storage fixture lifetime"
