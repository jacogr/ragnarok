# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Source-free bounded CE141 candidates retain verified signatures and all original roster positions; a block builder must independently apply its post-judgment admission rules.

import std/assertions
import ./services
import ../jamnp-s/assurance_distribution
import ../codec/assurances

const MaxPendingAssurances* = 1023 ## Full GP validator coverage fits a production quorum; a hostile backlog still cannot exceed the protocol population.

type
  AssurancePool* = object ## Rows and expanded validator positions have independent explicit admission ceilings; no canonical graph or key owner is retained.
    entries: array[MaxPendingAssurances, CheckedAssurance]
    limit, indexLimit, count, indices: int

func len*(pool: AssurancePool): int =
  ## Distinct authenticated identity rows are separate from repeated original positions.
  pool.count

func candidateCount*(pool: AssurancePool): int =
  ## Every original roster index counts toward the eventual canonical extrinsic budget.
  pool.indices

proc configure*(pool: var AssurancePool, entries: range[1..MaxPendingAssurances],
    indices: range[1..1023]): bool =
  ## Omission/default leaves zero capacity; policy cannot be replaced while candidates exist.
  if pool.limit != 0: return false
  pool.limit = entries
  pool.indexLimit = indices
  true

proc clear*(pool: var AssurancePool) =
  ## All retained candidates are source-free host ownership and need no foreign join.
  pool = default(AssurancePool)

proc refresh*(pool: var AssurancePool, services: Services) =
  ## An occupied canonical lease postpones refresh; it cannot be interpreted as evidence of a changed source.
  if not services.stateProofAvailable: return
  for index in 0..<pool.limit:
    # Complete root and anchor revocation remove stale candidates without cryptographic or archive work on the host.
    let checked = pool.entries[index]
    if checked.valid and not services.assuranceDistributionCurrent(checked):
      pool.indices -= checked.distributionInfo.value.duty.localIndices
      dec pool.count
      pool.entries[index] = default(CheckedAssurance)

proc remember*(pool: var AssurancePool, checked: CheckedAssurance): bool =
  ## Only privately verified capabilities enter; whole expanded-index capacity is checked before replacing a same-key candidate.
  let described = checked.distributionInfo
  if pool.limit == 0 or described.error != AssuranceDistributionError.None: return false
  let info = described.value.duty
  if info.localIndices < 1 or info.localIndices > 1023: return false
  var found = -1
  var empty = -1
  var prior = 0
  for index in 0..<pool.limit:
    # Preserve every other identity's retained candidate; overload never evicts a useful row.
    if pool.entries[index].valid:
      let old = pool.entries[index].distributionInfo.value.duty
      if array[32, byte](old.local) == array[32, byte](info.local):
        found = index
        prior = old.localIndices
    elif empty < 0: empty = index
  if found < 0 and (pool.count >= pool.limit or empty < 0): return false
  if info.localIndices > pool.indexLimit-(pool.indices-prior): return false
  if found < 0:
    found = empty
    inc pool.count
  pool.indices = pool.indices-prior+info.localIndices
  pool.entries[found] = checked
  true

proc candidateAt*(pool: AssurancePool, ordinal: int): Assurance {.requires: ordinal >= 0 and
    ordinal < pool.indices.} =
  ## Return an independent candidate in retention order; block assembly must sort original indices and freshly validate the complete post-judgment context.
  var remaining = ordinal
  for index in 0..<pool.limit:
    # Expanded candidates preserve original null gaps and repeated-key positions.
    if pool.entries[index].valid:
      let count = pool.entries[index].distributionInfo.value.duty.localIndices
      if remaining < count: return pool.entries[index].assuranceAt(remaining).value
      remaining -= count
  assert false # The required whole occupancy invariant makes this branch unreachable.
