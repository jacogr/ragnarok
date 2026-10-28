# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic native-result/receipt guards and live-owner destructor guards use real synchronized positive controls.
import std/assertions
import std/cmdline
import std/syncio
import ../support/storage_paged_native_fixture
import ../../src/storage/paged_store as storage_paged_store
import ../../src/storage/paged_io as storage_paged_io
import ../../src/storage/paged_stream as storage_paged_stream
import ../../src/storage/paged_codec as storage_paged_codec
import ../../src/storage/file_errors as storage_file_errors
import ../../src/storage/managed_manifest as storage_managed_manifest
import ../../src/storage/state_proof as storage_state_proof
import ../../src/storage/durability as storage_durability
proc pid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Each standalone probe has an isolated ignored namespace.
proc main() =
  ## Dynamic CLI origins keep guards on actual native runtime paths.
  let member = paramStr(1)
  let origin = paramStr(2)
  let directory = "build/paged-native-probe-" & $pid()
  let fixture = nativeFixture(7)
  var writer = default(PagedWriter)
  var candidate = default(PagedCandidate)
  var reader = default(PagedReader)
  let initialized = initializePagedWriter(writer, directory, fixture.config,
    fixture.records.nativeProducer, uint64(fixture.records.len), fixture.payload)
  assert initialized.error == PagedNativeError.None
  case member
  of "result":
    # Default and failed results never expose an inactive successful payload.
    let complete = openPagedReader(reader, directory, fixture.config)
    let outcome = if origin == "default": default(PagedNativeResult[bool])
      elif origin == "failed": openPagedReader(reader, directory, fixture.config)
      else: complete
    discard outcome.value
  of "file":
    # File causes exist only for the selected native refusal.
    let failed = openPagedReader(reader, directory & "-missing", fixture.config)
    let outcome = if origin == "default": default(PagedNativeResult[bool])
      elif origin == "failed": openPagedReader(reader, directory, fixture.config)
      else: failed
    discard outcome.fileError
  of "stream":
    # Quota failure is a genuine stream refusal, with no proof cause.
    assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
    let failed = reader.lookup(pagedKey(0), default(PagedWorkLimits))
    let outcome = if origin == "default": default(PagedNativeResult[VerifiedStateLookup])
      elif origin == "failed": reader.lookup(pagedKey(0), pagedPolicy().work)
      else: failed
    discard outcome.streamError
  of "proof":
    # Independently rooted false evidence reaches the real selected proof-failure branch.
    var bad = fixture.records
    bad[0].proof.value[0] = 99
    let failed = preparePagedReplacement(writer, candidate, bad.nativeProducer,
      uint64(bad.len), fixture.payload)
    assert failed.error == PagedNativeError.StreamFailure
    assert failed.streamError == PagedStreamError.ProofFailure
    let outcome = if origin == "default": default(PagedNativeResult[StorageDurability])
      elif origin == "failed": default(PagedNativeResult[StorageDurability])
      else: failed
    discard outcome.proofError
  of "proof_kind":
    # A selected stream quota refusal still carries no proof-specific cause.
    assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
    let outcome = reader.lookup(pagedKey(0), default(PagedWorkLimits))
    assert outcome.error == PagedNativeError.StreamFailure
    discard outcome.proofError
  of "publication":
    # Only confirmed file/directory barriers grant a publication receipt.
    let receipt = if origin == "default": default(PagedPublication) else: initialized.value
    discard receipt.durability
  of "reclamation":
    # Reclamation requires a captured, retired, exclusively pinned epoch.
    assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
    let old = reader.epochReceipt.value
    assert reader.close == FileError.None
    assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
      uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
    assert writer.publish(candidate).error == PagedNativeError.None
    let complete = writer.reclaim(old, writer.selected.value).value
    let receipt = if origin == "default": default(PagedReclamation) else: complete
    discard receipt.durability
  of "io":
    # Passive native outcomes do not grant default bytes or identity authority.
    let outcome = if origin == "default": default(PagedIoResult[string]) else: epochName(
        ManagedEpoch(1))
    discard outcome.value
  of "writer_live":
    # Returning with a live writer must trigger its explicit-close destructor requirement.
    if origin == "default": return
  of "candidate_live":
    # Sealed candidates retain native retirement authority even before selection.
    assert preparePagedReplacement(writer, candidate, fixture.records.nativeProducer,
      uint64(fixture.records.len), fixture.payload).error == PagedNativeError.None
    if origin == "default":
      assert writer.close == FileError.None
      return
  of "reader_live":
    # Independent reader lifetime also requires an explicit native close.
    assert openPagedReader(reader, directory, fixture.config).error == PagedNativeError.None
    if origin == "default":
      assert writer.close == FileError.None
      return
  of "directory_live", "file_live":
    # Lower-level owners cannot be silently dropped through internal IO helpers either.
    var borrowed = default(PagedDirectory)
    var file = default(PagedFile)
    assert openDirectory(borrowed, directory, false, false) == FileError.None
    if member == "file_live":
      assert openEpoch(file, borrowed, ManagedEpoch(1), PagedPin.Shared,
        pagedPolicy().dataset.bytes) == FileError.None
    if origin == "default":
      assert writer.close == FileError.None
      if member == "file_live": assert borrowed.close == FileError.None
      return
    if file.opened: assert file.close == FileError.None
    assert borrowed.close == FileError.None
  else: assert false, "unknown native storage probe"
  if reader.opened: assert reader.close == FileError.None
  if candidate.opened: assert candidate.close == FileError.None
  assert writer.close == FileError.None
  echo "0"
main()
