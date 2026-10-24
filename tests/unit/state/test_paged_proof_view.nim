# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Native light witnesses become detached, root-bound partial state views without complete-map authority.
# @@Verification={"arc":"paged_proof_view_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, paged_native_fixture]
import ../../../src/state/[paged_proof_view, proof_view, trie_proof]
import ../../../src/storage/[paged_store, paged_stream, paged_codec, file_errors]
import ../../../src/codec/[bounded, state_layout, state_trie]
proc limits(): PagedProofViewLimits =
  ## Explicit independent batch retention and per-query native work policies bound the bridge.
  PagedProofViewLimits(proof: StateProofLimits(nodes: ElementLimit(249), valueBytes: ByteLimit(10000)),
    batch: StateProofBatchLimits(items: ElementLimit(3), nodes: ElementLimit(747),
        valueBytes: ByteLimit(10000)),
    view: ProofViewLimits(items: ElementLimit(3), valueBytes: ByteLimit(10000)), work: pagedPolicy().work)
proc path(label: string): string =
  ## Each suite process owns its native namespaces under the ignored runner directory.
  "paged-proof-view-" & $storageProcessId() & "-" & label
proc check(view: ProofView, first: byte) =
  ## Present-empty and authenticated absence remain different from unqueried evidence.
  assert view.valid and view.len == 3
  let found = view.lookup(pagedKey(0)).value
  assert found.present and found.bytes.len == 33 and found.bytes[0] == first
  let empty = view.lookup(pagedKey(128)).value
  assert empty.present and empty.bytes.len == 0
  assert not view.lookup(pagedKey(255)).value.present
  assert view.lookup(pagedKey(32)).error == ProofViewError.MissingWitness
proc extract(reader: var PagedReader, fixture: PagedNativeFixture): ProofView =
  ## Request deliberately unsorted identities; the normal immutable view provides sorted lookups.
  let captured = readPagedProofView(reader, fixture.config.root,
    [pagedKey(255), pagedKey(0), pagedKey(128)], limits())
  assert captured.error == PagedProofViewError.None
  captured.value
proc policyChecks(reader: var PagedReader, fixture: PagedNativeFixture) =
  ## Exact ceilings succeed while one-short independent ceilings expose no partial collection.
  let root = fixture.config.root
  let queries = [pagedKey(0), pagedKey(128), pagedKey(255)]
  var total = 0'u64
  var largest = 0'u64
  for record in fixture.records:
    # Counts come from independently constructed fixture paths, not the consumer's accounting.
    let count = uint64(record.proof.nodes.len)
    total += count
    if count > largest: largest = count
  var exact = limits()
  exact.proof.nodes = ElementLimit(largest)
  exact.proof.valueBytes = ByteLimit(33)
  exact.batch.nodes = ElementLimit(total)
  exact.batch.valueBytes = ByteLimit(33)
  exact.view.valueBytes = ByteLimit(33)
  assert readPagedProofView(reader, root, queries, exact).error == PagedProofViewError.None
  for channel in 0..<7:
    # Each independent reservation refuses before granting a completed batch.
    var short = exact
    case channel
    of 0: short.proof.nodes = ElementLimit(largest-1)
    of 1: short.proof.valueBytes = ByteLimit(32)
    of 2: short.batch.nodes = ElementLimit(total-1)
    of 3: short.batch.valueBytes = ByteLimit(32)
    of 4: short.view.valueBytes = ByteLimit(32)
    of 5: short.batch.items = ElementLimit(2)
    else: short.view.items = ElementLimit(2)
    assert readPagedProofView(reader, root, queries, short).error ==
        PagedProofViewError.LimitExceeded
  var noWork = limits()
  noWork.work.ioCalls = ElementLimit(0)
  let refused = readPagedProofView(reader, root, queries, noWork)
  assert refused.error == PagedProofViewError.NativeFailure
  assert refused.nativeFailure.error == PagedNativeError.StreamFailure
  assert refused.nativeFailure.streamError == PagedStreamError.LimitExceeded
  assert readPagedProofView(reader, root, [pagedKey(0), pagedKey(32)], limits()).error ==
    PagedProofViewError.MissingWitness
  resetIo()
  let duplicate = readPagedProofView(reader, root, [pagedKey(0), pagedKey(0)], limits())
  assert duplicate.error == PagedProofViewError.ProofFailure
  assert duplicate.proofError == StateProofError.DuplicateKey
  assert ioCalls(readIo) == 0
  var wrong = array[32, byte](root)
  wrong[0] = wrong[0] xor 1
  assert readPagedProofView(reader, StateRoot(wrong), queries, limits()).error ==
      PagedProofViewError.WrongRoot
  assert ioCalls(readIo) == 0
  let empty = readPagedProofView(reader, root, [], limits())
  assert empty.error == PagedProofViewError.None and empty.value.valid and empty.value.len == 0
  assert array[32, byte](empty.value.root) == array[32, byte](root)
proc sameNodes(left, right: openArray[EncodedStateNode]): bool =
  ## Compare canonical bytes explicitly across the nominal fixed-width node boundary.
  if left.len != right.len: return false # Different path lengths cannot encode the same witness.
  for index in 0..<left.len:
    # Distinct node wrappers are compared through their complete canonical array representation.
    if array[64, byte](left[index]) != array[64, byte](right[index]): return false
  true
proc detached(reader: var PagedReader, fixture: PagedNativeFixture) =
  ## The public raw transport getter owns independent node/value arrays even across repeated calls.
  let captured = reader.readProof(pagedKey(0), pagedPolicy().work)
  assert captured.error == PagedNativeError.None
  var raw = captured.value.proof
  assert raw.proof.value == fixture.records[0].proof.value, "raw value"
  assert sameNodes(raw.proof.nodes, fixture.records[0].proof.nodes), "raw nodes"
  raw.proof.value[0] = 99
  var changed = array[64, byte](raw.proof.nodes[0])
  changed[0] = changed[0] xor 1
  raw.proof.nodes[0] = EncodedStateNode(changed)
  assert captured.value.proof.proof.value[0] == 7, "value isolation"
  assert sameNodes(captured.value.proof.proof.nodes, fixture.records[0].proof.nodes), "node isolation"
  assert reader.readProof(pagedKey(32), pagedPolicy().work).error == PagedNativeError.UnknownKey
proc normal(old, fresh: PagedNativeFixture) =
  ## A retained old reader and captured view survive root advancement and all native owners closing.
  let directory = path("normal")
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  var newest = default(PagedReader)
  var candidate = default(PagedCandidate)
  defer:
    # All ordinary and failure paths retire explicit owners without retrying poisoned operations.
    resetIo()
    if newest.opened: discard newest.close
    if reader.opened: discard reader.close
    if candidate.opened: discard candidate.close
    if writer.opened: discard writer.close
  assert initializePagedWriter(writer, directory, old.config, old.records.nativeProducer,
    uint64(old.records.len), old.payload).error == PagedNativeError.None
  assert openPagedReader(reader, directory, old.config).error == PagedNativeError.None
  policyChecks(reader, old)
  detached(reader, old)
  let raw = reader.readProof(pagedKey(0), pagedPolicy().work).value
  let view = extract(reader, old)
  assert preparePagedAdvance(writer, candidate, fresh.config.root, fresh.records.nativeProducer,
    uint64(fresh.records.len), fresh.payload).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert openPagedReader(newest, directory, fresh.config).error == PagedNativeError.None
  let newer = extract(newest, fresh)
  extract(reader, old).check(7)
  assert readPagedProofView(newest, old.config.root, [pagedKey(0)], limits()).error ==
    PagedProofViewError.WrongRoot
  assert writer.close == FileError.None
  assert reader.close == FileError.None
  assert newest.close == FileError.None
  assert raw.proof.proof.value == old.records[0].proof.value
  assert sameNodes(raw.proof.proof.nodes, old.records[0].proof.nodes)
  view.check(7)
  newer.check(9)
  let closed = readPagedProofView(reader, old.config.root, [pagedKey(0)], limits())
  assert closed.error == PagedProofViewError.NativeFailure
  assert closed.nativeFailure.error == PagedNativeError.Uninitialized
proc faultsAndCycles(fixture: PagedNativeFixture) =
  ## Every observed source read refuses atomically; fresh reopen is mandatory after native IO poison.
  let directory = path("faults")
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  assert initializePagedWriter(writer, directory, fixture.config, fixture.records.nativeProducer,
    uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
  assert writer.close == FileError.None
  assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  resetIo()
  extract(reader, fixture).check(7)
  let reads = ioCalls(readIo)
  assert reads > 0 and ioCalls(writeIo) == 0
  for skip in 0..<int(reads):
    # Inject one real SDK read failure at each independently observed successful-call boundary.
    resetIo()
    armIo(readIo, cint(skip), 1, failedIo)
    let refused = readPagedProofView(reader, fixture.config.root,
      [pagedKey(255), pagedKey(0), pagedKey(128)], limits())
    assert refused.error == PagedProofViewError.NativeFailure
    assert refused.nativeFailure.error == PagedNativeError.StreamFailure
    assert refused.nativeFailure.streamError == PagedStreamError.IOFailure
    assert pendingIo() == 0
    assert readPagedProofView(reader, fixture.config.root, [pagedKey(0)], limits()).error ==
      PagedProofViewError.NativeFailure
    resetIo()
    assert reader.close == FileError.None
    assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
  extract(reader, fixture).check(7)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Each complete copied proof batch and immutable view retires before the next iteration.
    extract(reader, fixture).check(7)
    detached(reader, fixture)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("paged_proof_view", 1000, before, after)
  assert reader.close == FileError.None
proc main() =
  ## Checked ARC and genuine SDK calls cover partial authority, ownership, policies and poisoned-reader lifetimes.
  let old = nativeFixture(7)
  let fresh = nativeFixture(9)
  var absent = default(PagedReader)
  assert readPagedProofView(absent, old.config.root, [], limits()).nativeFailure.error ==
      PagedNativeError.Uninitialized
  normal(old, fresh)
  faultsAndCycles(old)
  echo "paged proof view PASS"
main()
