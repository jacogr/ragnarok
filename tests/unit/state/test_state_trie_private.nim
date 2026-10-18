# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## White-box topology arithmetic and scratch-release tests use only project code and public
## allocator occupancy.
##
## Provides a standalone Hastur test executable; assertions and expected output form its harness
## interface.

import std/[assertions, syncio]
import ../../support/arc_evidence
include ../../../src/codec/state_trie

# Sequential observer counters distinguish preflight rejection from a primitive refusal.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
# Refuse after completed child work so ARC cleanup is exercised beyond the first native call.
proc failAfter(successful: cint) {.importc: "ro_blake_after", cdecl.}
# Observe copied call counts without retaining any native or ARC owner.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}

# Create independent values and reverse-key source order; the calculator must leave both untouched.
proc entries(): seq[StateEntry] =
  result = newSeq[StateEntry](16)
  # Distinct first octets force multiple committed children while keeping fixtures small and bounded.
  for i in 0..<result.len:
    var key = default(array[31, byte])
    key[0] = byte(15-i)
    result[i] = StateEntry(key: StateKey(key), value: newSeq[byte](33))
    result[i].value[0] = byte(i)

# Validate each early policy path without letting a failing backend conceal accidental cryptographic work.
proc preflight(source: seq[StateEntry], limits: StateTrieLimits, expected: StateTrieError) =
  fail(1)
  assert stateTrieRoot(source, limits).error == expected
  assert hashCalls() == 0

# Every invocation must release sorting scratch after success, early failure and failure after completed child hashes.
proc cycle(source: seq[StateEntry], limits: StateTrieLimits) =
  fail(0)
  let complete = stateTrieRoot(source, limits)
  assert complete.error == StateTrieError.None
  let root = array[32, byte](complete.value.root)
  fail(1)
  assert stateTrieRoot(source, limits).error == StateTrieError.BackendFailure
  assert hashCalls() == 1
  failAfter(3)
  assert stateTrieRoot(source, limits).error == StateTrieError.BackendFailure
  assert hashCalls() == 4
  fail(0)
  let recovered = stateTrieRoot(source, limits)
  assert recovered.error == StateTrieError.None
  assert array[32, byte](recovered.value.root) == root
  var short = limits
  short.nodes = TrieNodeLimit(0)
  preflight(source, short, StateTrieError.LimitExceeded)
  preflight(@[source[0], source[0]], limits, StateTrieError.DuplicateKey)
  fail(0)

let source = entries()
let limits = StateTrieLimits(items: ElementLimit(16), perValue: ByteLimit(33),
  totalValueBytes: ByteLimit(528), nodes: TrieNodeLimit(1024))
var short = limits
short.items = ElementLimit(15)
preflight(source, short, StateTrieError.LimitExceeded)
short = limits
short.perValue = ByteLimit(32)
preflight(source, short, StateTrieError.LimitExceeded)
short = limits
short.totalValueBytes = ByteLimit(527)
preflight(source, short, StateTrieError.LimitExceeded)
short = limits
short.nodes = TrieNodeLimit(0)
preflight(source, short, StateTrieError.LimitExceeded)
preflight(@[source[0], source[0]], limits, StateTrieError.DuplicateKey)
# Empty mappings need neither scratch nodes nor a primitive call, even if the backend is refusing.
fail(1)
let empty = stateTrieRoot([], default(StateTrieLimits))
assert empty.error == StateTrieError.None and empty.value.nodes == 0
assert hashCalls() == 0
fail(0)
# Exercise uint64 budget boundaries without fabricating an unsafe enormous sequence descriptor.
let keys = @[KeyIndex(key: source[0].key, index: 0)]
var used = high(uint64)
assert countNodes(keys, 0, 1, 0, TrieNodeLimit(high(uint64)), used) == StateTrieError.LimitExceeded
assert used == high(uint64)
used = high(uint64)-1
assert countNodes(keys, 0, 1, 0, TrieNodeLimit(high(uint64)), used) == StateTrieError.None
assert used == high(uint64)
assert countNodes(keys, 0, 0, 248, TrieNodeLimit(0), used) == StateTrieError.None
assert used == high(uint64)
# The final-depth defense rejects an invalid repeated range before split can read bit 248.
let repeated = @[keys[0], keys[0]]
used = 0
assert countNodes(repeated, 0, 2, 248, TrieNodeLimit(1), used) == StateTrieError.DuplicateKey
# Warmup excludes allocator initialization from the isolated live-occupancy comparison.
for i in 0..<100: cycle(source, limits)
let beforeRelease = getOccupiedMem()
# Source values stay live outside every temporary sorting/recursive result scope.
for i in 0..<1000: cycle(source, limits)
let afterRelease = getOccupiedMem()
assert beforeRelease == afterRelease
# Source order and long payload bytes remain unchanged on all success/error paths.
for i in 0..<source.len:
  assert array[31, byte](source[i].key)[0] == byte(15-i)
  assert source[i].value[0] == byte(i) and source[i].value.len == 33
# Preserve fresh numeric observations independently of portable expected output.
recordArcRelease("state_trie_private", 1000, beforeRelease, afterRelease)
echo "TRIE_ARC_RELEASE cycles=1000 unchanged"
echo "Nimony state trie: preflight before hashing, early/late refusal recovery, arithmetic and ARC release passed"
