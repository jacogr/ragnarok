# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Initial membership never substitutes for missing actual child-root evidence; immutable contexts remain branch-local.
import std/[assertions, syncio]
import ../../support/fuzz_ancestry_context
import ../../../src/state/[fuzz_ancestry, fuzz_protocol]
import ../../../src/codec/[bounded, header, assurances]
proc main() =
  ## Direct semantic witnesses cover exact budgets, sparse historical evidence and sibling restoration.
  let missing = default(FuzzAncestryResult[FuzzAncestry])
  let absent = default(FuzzAncestry)
  assert missing.error == FuzzAncestryError.Uninitialized
  assert absent.fuzzAncestryInfo.error == FuzzAncestryError.Uninitialized
  let olderHash = FuzzHeaderHash(ancestryWord(2))
  let oldestHash = FuzzHeaderHash(ancestryWord(1))
  let prior = PriorStateRoot(ancestryWord(17))
  let posterior = PriorStateRoot(ancestryWord(31))
  let seed = ancestryHeader(HeaderSlot(4), olderHash, prior)
  let seedHash = ancestryHash(seed)
  var declared = @[FuzzAncestor(slot: HeaderSlot(1), hash: oldestHash),
    FuzzAncestor(slot: HeaderSlot(4), hash: seedHash), FuzzAncestor(slot: HeaderSlot(2),
        hash: olderHash)]
  var exact = fuzzAncestryTestLimits()
  exact.records = ElementLimit(3)
  exact.bytes = ByteLimit(405)
  assert captureFuzzAncestry(default(OwnedHeader), declared, exact).error ==
      FuzzAncestryError.InvalidHeader
  let made = captureFuzzAncestry(seed, declared, exact)
  assert made.error == FuzzAncestryError.None
  let context = made.value
  let info = context.fuzzAncestryInfo.value
  assert info.records == 3 and info.knownHeaders == 1 and info.bytes == 405
  assert context.fuzzAncestorAt(FuzzAncestorIndex(0)).value.slot == HeaderSlot(4)
  assert uint32(context.fuzzAncestorAt(FuzzAncestorIndex(1)).value.slot) == 2
  assert uint32(context.fuzzAncestorAt(FuzzAncestorIndex(2)).value.slot) == 1
  assert context.fuzzAncestorAt(FuzzAncestorIndex(3)).error == FuzzAncestryError.InvalidIndex
  assert context.fuzzAncestorAt(FuzzAncestorIndex(-1)).error == FuzzAncestryError.InvalidIndex
  declared[0] = FuzzAncestor(slot: HeaderSlot(99), hash: seedHash)
  assert uint32(context.fuzzAncestorAt(FuzzAncestorIndex(2)).value.slot) == 1
  assert context.validateFuzzParent(seed, exact) == FuzzAncestryError.None
  assert context.findFuzzLookup(olderHash, HeaderSlot(2), prior).error == FuzzAncestryError.None
  assert context.findFuzzLookup(olderHash, HeaderSlot(2), posterior).error ==
      FuzzAncestryError.WrongLookupState
  assert context.findFuzzLookup(olderHash, HeaderSlot(3), prior).error ==
      FuzzAncestryError.WrongLookupSlot
  assert context.findFuzzLookup(oldestHash, HeaderSlot(1), prior).error ==
      FuzzAncestryError.MissingLookupChild
  assert context.findFuzzLookup(seedHash, HeaderSlot(4), posterior).error ==
      FuzzAncestryError.MissingLookupChild
  assert context.findFuzzLookup(FuzzHeaderHash(ancestryWord(99)), HeaderSlot(0), prior).error ==
      FuzzAncestryError.MissingLookupAnchor
  var smaller = exact
  smaller.bytes = ByteLimit(404)
  assert captureFuzzAncestry(seed, @[FuzzAncestor(slot: HeaderSlot(1), hash: oldestHash),
      FuzzAncestor(slot: HeaderSlot(2), hash: olderHash)], smaller).error ==
      FuzzAncestryError.LimitExceeded
  assert context.validateFuzzParent(seed, smaller) == FuzzAncestryError.LimitExceeded
  smaller = exact
  smaller.records = ElementLimit(2)
  assert captureFuzzAncestry(seed, @[FuzzAncestor(slot: HeaderSlot(1), hash: oldestHash),
      FuzzAncestor(slot: HeaderSlot(2), hash: olderHash)], smaller).error ==
      FuzzAncestryError.LimitExceeded
  var invalid = exact
  invalid.records = ElementLimit(0)
  assert captureFuzzAncestry(seed, [], invalid).error == FuzzAncestryError.InvalidConfig
  for facts in [@[FuzzAncestor(slot: HeaderSlot(2), hash: olderHash), FuzzAncestor(slot: HeaderSlot(
      1), hash: olderHash)], @[FuzzAncestor(slot: HeaderSlot(2), hash: olderHash), FuzzAncestor(
          slot: HeaderSlot(2), hash: oldestHash)]]:
    assert captureFuzzAncestry(seed, facts, exact).error == FuzzAncestryError.ConflictingRecord
  assert captureFuzzAncestry(seed, @[FuzzAncestor(slot: HeaderSlot(3), hash: seedHash)],
      exact).error == FuzzAncestryError.InvalidSlot
  assert captureFuzzAncestry(seed, @[FuzzAncestor(slot: HeaderSlot(4), hash: olderHash)],
      exact).error == FuzzAncestryError.InvalidSlot
  assert captureFuzzAncestry(seed, @[FuzzAncestor(slot: HeaderSlot(5), hash: olderHash)],
      exact).error == FuzzAncestryError.InvalidSlot
  assert captureFuzzAncestry(seed, newSeq[FuzzAncestor](25), exact).error ==
      FuzzAncestryError.LimitExceeded
  var budget = exact
  budget.bytes = ByteLimit(4096)
  let child = ancestryHeader(HeaderSlot(5), seedHash, posterior)
  let extended = extendFuzzAncestry(context, child, budget)
  assert extended.error == FuzzAncestryError.None
  assert extended.value.fuzzAncestryInfo.value.records == 3
  assert extended.value.fuzzAncestryInfo.value.knownHeaders == 2
  assert extended.value.findFuzzLookup(seedHash, HeaderSlot(4), posterior).error ==
      FuzzAncestryError.None
  assert extended.value.findFuzzLookup(oldestHash, HeaderSlot(1), prior).error ==
      FuzzAncestryError.MissingLookupAnchor
  assert context.findFuzzLookup(seedHash, HeaderSlot(4), posterior).error ==
      FuzzAncestryError.MissingLookupChild
  let otherRoot = PriorStateRoot(ancestryWord(32))
  let sibling = ancestryHeader(HeaderSlot(5), seedHash, otherRoot)
  let branch = extendFuzzAncestry(context, sibling, budget).value
  assert branch.findFuzzLookup(seedHash, HeaderSlot(4), otherRoot).error == FuzzAncestryError.None
  assert extended.value.findFuzzLookup(seedHash, HeaderSlot(4), otherRoot).error ==
      FuzzAncestryError.WrongLookupState
  assert extended.value.validateFuzzParent(child, budget) == FuzzAncestryError.None
  assert extended.value.validateFuzzParent(sibling, budget) == FuzzAncestryError.WrongParent
  let wrongParent = ancestryHeader(HeaderSlot(5), olderHash, posterior)
  assert extendFuzzAncestry(context, wrongParent, budget).error == FuzzAncestryError.WrongParent
  let backward = ancestryHeader(HeaderSlot(4), seedHash, posterior)
  assert extendFuzzAncestry(context, backward, budget).error == FuzzAncestryError.InvalidSlot
  var incompatible = budget
  incompatible.header.cores = CoreCount(3)
  assert context.validateFuzzParent(seed, incompatible) == FuzzAncestryError.InvalidConfig
  var narrow = budget
  narrow.records = ElementLimit(1)
  narrow.bytes = ByteLimit(333)
  let one = captureFuzzAncestry(seed, [], narrow).value
  let latest = extendFuzzAncestry(one, child, narrow).value
  assert latest.fuzzAncestryInfo.value.records == 1 and latest.fuzzAncestryInfo.value.bytes == 333
  assert latest.findFuzzLookup(seedHash, HeaderSlot(4), posterior).error ==
      FuzzAncestryError.MissingLookupAnchor
  echo "PASS JAM fuzzer ancestry: immutable membership, actual child roots and bounded branch evidence"
main()
