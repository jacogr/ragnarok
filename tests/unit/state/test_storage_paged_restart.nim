# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Whole-index capture, restart-safe retirement and real durability barriers retain partial-state authority.
# @@Verification={"arc":"storage_paged_restart_arc_release"}
import std/[assertions, syncio]
import ../../support/[arc_evidence, storage_io, paged_reference, paged_native_fixture]
import ../../../src/storage/paged/[stream as paged_stream, codec as paged_codec,
    store as paged_store, io as paged_io]
import ../../../src/storage/state_proof
import ../../../src/storage/full/state_trie as full_state_trie
import ../../../src/storage/light/state_cache as light_state_cache
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/light/delta as light_delta
import ../../../src/storage/durability
import ../../../src/storage/file/errors as file_errors
import ../../../src/codec/bounded
import ../../../src/codec/state/[layout as state_layout, trie as state_trie]
import ../../../src/state/paged/proof_view as transport
import ../../../src/state/proof/view as partial
type Memory = ref object ## Independent test transport owns bytes and deterministic callback refusal.
  bytes: seq[byte]
  calls, failAt: int
proc input(memory: Memory): PagedInput =
  ## Exact callbacks never retain the mutable destination.
  proc read(offset: PagedOffset, output: var openArray[byte]): bool {.closure.} =
    ## Refuse the selected ordinal before copying any bytes.
    inc memory.calls
    if memory.calls == memory.failAt: return false
    let start = uint64(offset)
    if start > uint64(memory.bytes.len) or uint64(output.len) > uint64(
        memory.bytes.len)-start: return false
    for index in 0..<output.len: output[index] = memory.bytes[int(start)+index] # Proven source extent.
    true
  proc extent(output: var uint64): bool {.closure.} =
    ## EOF is a failure boundary too, including the final check.
    inc memory.calls
    output = uint64(memory.bytes.len)
    memory.calls != memory.failAt
  PagedInput(read: read, extent: extent)
proc path(label: string): string =
  ## Every trial owns a fresh ignored namespace.
  "paged-restart-" & $storageProcessId() & "-" & label
proc config(source: PagedNativeFixture, v2: bool): PagedNativeConfig =
  ## V1/V2 selection remains explicit and independent of proof retention.
  result = source.config
  if v2: result.limits.contextBytes = ByteLimit(1024) # V2 has mandatory nonempty opaque context.
proc context(v2: bool): seq[byte] =
  ## V1 never receives an inferred application context.
  if v2: @[7'u8, 8, 9, 10]
  else: @[] # Absence is an explicitly selected V1 contract.
proc initialize(writer: var PagedWriter, directory: string, source: PagedNativeFixture, v2: bool) =
  ## Both publication barriers precede all lifecycle tests.
  let made = initializePagedWriter(writer, directory, config(source, v2),
    source.records.nativeProducer, uint64(source.records.len), source.payload, context(v2))
  assert made.error == PagedNativeError.None
  assert made.value.durability == StorageDurability.FileAndDirectorySynced
proc many(): PagedNativeFixture =
  ## One complete two-leaf oracle generates 130 independent queries, never 130 complete-map entries.
  result = nativeFixture(7)
  var raw = newSeq[byte](33)
  raw[0] = 7
  let entries = @[StateEntry(key: pagedKey(0), value: raw), StateEntry(key: pagedKey(128), value: @[])]
  let limits = StateTrieLimits(items: ElementLimit(4), perValue: ByteLimit(10000),
    totalValueBytes: ByteLimit(20000), nodes: TrieNodeLimit(1000))
  let trie = newFullStateTrie(entries, FullStateTrieLimits(trie: limits)).value
  assert array[32, byte](result.config.root) == array[32, byte](trie.commitment.root)
  result.records = @[]
  result.payload = 0
  for ordinal in 0..<130:
    # The final sparse query is 255; unrecorded 254 must remain unknown.
    let key = pagedKey(if ordinal == 129: 255'u8 else: byte(ordinal))
    let proof = trie.prove(key, result.config.limits.proof).value
    result.payload += 41+uint64(proof.nodes.len)*64+uint64(proof.value.len)
    result.records.add(LightStateProof(key: key, proof: proof))
proc lowLevel() =
  ## Authentication shares a cumulative budget across every descriptor, with all-or-none ownership.
  let source = many()
  let reference = pagedReference(source.config.chain, source.config.root, source.records)
  for cache in 0..1:
    # Fresh admission under each cache policy cannot inherit successful extraction scratch.
    var policy = source.config.limits
    policy.cachePages = ElementLimit(cache)
    policy.workingBytes = ByteLimit(PagedStreamFixedBytes+256'u64+4'u64*31*130)
    let selected = decodePagedManifest(reference.manifest, source.config.chain, source.config.root,
      policy.dataset, ByteLimit(PagedManifestBytes)).value
    let memory = Memory(bytes: reference.bytes)
    let checked = validatePagedArtifact(memory.input, selected, policy).value
    memory.calls = 0
    let captured = readPagedQueries(memory.input, checked, ElementLimit(130), policy.work)
    assert captured.error == PagedStreamError.None
    let inventory = captured.value
    assert inventory.initialized and inventory.len == 130 and inventory.manifest.bytes ==
        reference.manifest
    let calls = memory.calls
    let keys = inventory.keys
    for ordinal in 0..<129: assert array[31, byte](keys[ordinal]) == array[31, byte](pagedKey(byte(
        ordinal))) # Canonical independent key order.
    assert array[31, byte](keys[129]) == array[31, byte](pagedKey(255))
    var detached = inventory.keys
    detached[0] = pagedKey(42)
    assert array[31, byte](inventory.keys[0]) == array[31, byte](pagedKey(0))
    var exact = policy.work
    exact.ioCalls = ElementLimit(inventory.counts.ioCalls)
    exact.pageHashes = ElementLimit(inventory.counts.pageHashes)
    exact.readBytes = ByteLimit(inventory.counts.readBytes)
    assert readPagedQueries(memory.input, checked, ElementLimit(130), exact).error ==
        PagedStreamError.None
    for channel in 0..<3:
      # Shorten each observed channel without resetting its allowance for each row.
      var short = exact
      case channel
      of 0: short.ioCalls = ElementLimit(inventory.counts.ioCalls-1)
      of 1: short.pageHashes = ElementLimit(inventory.counts.pageHashes-1)
      else: short.readBytes = ByteLimit(inventory.counts.readBytes-1) # Read bytes include digest authentication.
      assert readPagedQueries(memory.input, checked, ElementLimit(130), short).error ==
          PagedStreamError.LimitExceeded
    for ordinal in 1..calls:
      # Every logical callback failure, including final EOF, refuses the entire owned result.
      memory.calls = 0
      memory.failAt = ordinal
      assert readPagedQueries(memory.input, checked, ElementLimit(130), policy.work).error !=
          PagedStreamError.None
    memory.failAt = 0
    memory.calls = 0
    assert readPagedQueries(memory.input, checked, ElementLimit(129), policy.work).error ==
        PagedStreamError.LimitExceeded
    assert memory.calls == 0
    assert readPagedQueries(memory.input, checked, ElementLimit(130), default(
        PagedWorkLimits)).error == PagedStreamError.LimitExceeded
    assert memory.calls == 0
    policy.workingBytes = ByteLimit(uint64(policy.workingBytes)-1)
    let small = validatePagedArtifact(memory.input, selected, policy).value
    memory.calls = 0
    assert readPagedQueries(memory.input, small, ElementLimit(130), policy.work).error ==
        PagedStreamError.LimitExceeded
    assert memory.calls == 0
    memory.bytes[4096] = memory.bytes[4096] xor 1
    assert readPagedQueries(memory.input, checked, ElementLimit(130), policy.work).error ==
        PagedStreamError.ChecksumMismatch
proc viewLimits(selected: PagedNativeConfig): transport.PagedProofViewLimits =
  ## State-layer per-query verification and retained view limits remain independent of inventory work.
  result = default(transport.PagedProofViewLimits)
  result.proof.nodes = ElementLimit(249)
  result.proof.valueBytes = ByteLimit(10000)
  result.batch.items = ElementLimit(256)
  result.batch.nodes = ElementLimit(64000)
  result.batch.valueBytes = ByteLimit(10000)
  result.view.items = ElementLimit(256)
  result.view.valueBytes = ByteLimit(10000)
  result.work = selected.limits.work
proc capture(reader: var PagedReader, selected: PagedNativeConfig) =
  ## Missing evidence, authenticated absence and present-empty are observably distinct after materialization.
  let inventory = reader.queryInventory(ElementLimit(3), selected.limits.work).value
  assert inventory.len == 3
  let view = transport.readAllPagedProofView(reader, selected.root, viewLimits(selected),
      selected.limits.work).value
  assert view.lookup(pagedKey(0)).value.bytes[0] == 7
  assert view.lookup(pagedKey(128)).value.present and view.lookup(pagedKey(128)).value.bytes.len == 0
  assert not view.lookup(pagedKey(255)).value.present
  assert view.lookup(pagedKey(254)).error == partial.ProofViewError.MissingWitness
proc nativeInventory(source: PagedNativeFixture) =
  ## Restart uses independent expected root; native read uncertainty latches until close/reopen.
  let directory = path("inventory")
  let selected = config(source, true)
  var writer = default(PagedWriter)
  var reader = default(PagedReader)
  initialize(writer, directory, source, true)
  assert writer.close == FileError.None
  assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
  capture(reader, selected)
  assert transport.readAllPagedProofView(reader, nativeFixture(9).config.root,
    viewLimits(selected), selected.limits.work).error == transport.PagedProofViewError.WrongRoot
  var tight = viewLimits(selected)
  tight.view.items = ElementLimit(2)
  assert transport.readAllPagedProofView(reader, selected.root, tight,
    selected.limits.work).error == transport.PagedProofViewError.NativeFailure
  resetIo()
  let retained = reader.queryInventory(ElementLimit(3), selected.limits.work).value
  let reads = ioCalls(readIo)
  assert reads > 0
  for skip in 0..<int(reads):
    # Each observed read is failed once; no successful key prefix escapes or remains usable as a native owner.
    armIo(readIo, cint(skip), 1, failedIo)
    assert reader.queryInventory(ElementLimit(3), selected.limits.work).error !=
        PagedNativeError.None
    assert pendingIo() == 0
    resetIo()
    assert reader.queryInventory(ElementLimit(3), selected.limits.work).error ==
        PagedNativeError.RecoveryRequired
    assert reader.close == FileError.None
    assert openPagedReader(reader, directory, selected).error == PagedNativeError.None
  capture(reader, selected)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    # Detached keys, canonical state proofs and the immutable view all release within each activation.
    capture(reader, selected)
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("storage_paged_restart", 1000, before, after)
  assert reader.close == FileError.None
  assert retained.len == 3 and retained.keys.len == 3
proc advance(writer: var PagedWriter, fresh: PagedNativeFixture, v2: bool) =
  ## Different-root advancement preserves ordinary sequence, independently of physical epoch growth.
  var candidate = default(PagedCandidate)
  assert preparePagedAdvance(writer, candidate, fresh.config.root, fresh.records.nativeProducer,
    uint64(fresh.records.len), fresh.payload, context(v2)).error == PagedNativeError.None
  assert writer.publish(candidate).error == PagedNativeError.None
  assert uint64(writer.selected.value.sequence) == 0
proc retirement(old, fresh: PagedNativeFixture) =
  ## Persisted exact content authority works across restart while the stronger live pin contract remains enforced.
  for v2 in [false, true]:
    # V1 and V2 never infer each other's context policy.
    let directory = path("retire-" & $v2)
    var writer = default(PagedWriter)
    var reader = default(PagedReader)
    initialize(writer, directory, old, v2)
    let previous = writer.selected.value
    assert openPagedReader(reader, directory, config(old, v2)).error == PagedNativeError.None
    let receipt = reader.epochReceipt.value
    advance(writer, fresh, v2)
    let current = writer.selected.value
    assert writer.reclaimExpectedEpoch(previous, current).fileError == FileError.Busy
    assert reader.close == FileError.None
    assert writer.close == FileError.None
    assert openPagedWriter(writer, directory, config(fresh, v2)).error == PagedNativeError.None
    assert writer.reclaimExpectedEpoch(current, current).error != PagedNativeError.None
    assert writer.reclaimExpectedEpoch(previous, previous).error != PagedNativeError.None
    assert writer.reclaimExpectedEpoch(default(PagedManifest), current).error !=
        PagedNativeError.None
    let reclaimed = writer.reclaimExpectedEpoch(previous, current)
    assert reclaimed.error == PagedNativeError.None
    assert reclaimed.value.durability == StorageDurability.FileAndDirectorySynced
    assert not reclaimed.value.alreadyAbsent and reclaimed.value.retirementError == FileError.None
    assert writer.reclaim(receipt, current).value.alreadyAbsent
    assert writer.close == FileError.None
    assert openPagedWriter(writer, directory, config(fresh, v2)).error == PagedNativeError.None
    assert writer.reclaimExpectedEpoch(previous, current).value.alreadyAbsent
    resetIo()
    assert writer.synchronize.value == StorageDurability.FileAndDirectorySynced
    assert ioCalls(syncIo) == 2
    assert writer.close == FileError.None
proc read(path: string): string =
  ## Fixture transport cannot silently replace a failed native artifact read.
  try: result = readFile(path)
  except: assert false # Missing fixture bytes invalidate the control.
proc write(path, bytes: string) =
  ## Only test-owned closed old artifacts are replaced or corrupted.
  try: writeFile(path, bytes)
  except: assert false # Fixture mutation must actually reach the filesystem.
proc renameNative(source, target: cstring): cint {.importc: "rename", cdecl, header: "<stdio.h>".}
  ## Test-only equal-byte replacement changes the inode without changing expected content.
proc identities(old, fresh: PagedNativeFixture) =
  ## Content expectations survive restart; captured receipts continue to reject equal-byte inode substitution.
  for corrupt in [false, true]:
    # Independent namespaces keep corruption evidence separate from a successful content-authorized deletion.
    let directory = path("identity-" & $corrupt)
    var writer = default(PagedWriter)
    var reader = default(PagedReader)
    initialize(writer, directory, old, true)
    let previous = writer.selected.value
    assert openPagedReader(reader, directory, config(old, true)).error == PagedNativeError.None
    let receipt = reader.epochReceipt.value
    assert reader.close == FileError.None
    advance(writer, fresh, true)
    assert writer.close == FileError.None
    var destination = directory & "/" & epochName(previous.epoch).value
    var bytes = read(destination)
    if corrupt:
      # A matching header cannot hide a modified authenticated descriptor page.
      bytes[4096] = char(byte(bytes[4096]) xor 1)
      write(destination, bytes)
    else:
      # Native rename creates a genuinely different inode with exact original bytes.
      var replacement = directory & "/replacement"
      write(replacement, bytes)
      assert renameNative(replacement.toCString(), destination.toCString()) == 0
    assert openPagedWriter(writer, directory, config(fresh, true)).error == PagedNativeError.None
    let current = writer.selected.value
    let currentBytes = read(directory & "/CURRENT")
    if corrupt:
      # Refusal preserves both the corrupt forensic file and the current trusted root selection.
      assert writer.reclaimExpectedEpoch(previous, current).error != PagedNativeError.None
      assert read(destination) == bytes and read(directory & "/CURRENT") == currentBytes
    else:
      # Captured physical authority is deliberately stronger than expected-content authority.
      let refused = writer.reclaim(receipt, current)
      assert refused.error == PagedNativeError.FileFailure and refused.fileError ==
          FileError.RecoveryMismatch
      assert writer.reclaimExpectedEpoch(previous, current).error == PagedNativeError.None
    assert writer.close == FileError.None
proc faults(old, fresh: PagedNativeFixture) =
  ## Every actually reached retirement syscall and each explicit durability barrier receives a fresh fault trial.
  for operation in [readIo, lockIo, closeIo, syncIo, unlinkIo]:
    # Measure successful retirement first rather than guessing native call counts.
    var writer = default(PagedWriter)
    let directory = path("count-" & $operation)
    initialize(writer, directory, old, true)
    let previous = writer.selected.value
    advance(writer, fresh, true)
    let current = writer.selected.value
    resetIo()
    assert writer.reclaimExpectedEpoch(previous, current).error == PagedNativeError.None
    let calls = ioCalls(operation)
    assert calls > 0
    assert writer.close == FileError.None
    for skip in 0..<int(calls):
      # Independent namespaces preserve every late-unlink outcome for explicit reopen resolution.
      let trial = path("fault-" & $operation & "-" & $skip)
      initialize(writer, trial, old, true)
      let before = writer.selected.value
      advance(writer, fresh, true)
      let selected = writer.selected.value
      armIo(operation, cint(skip), 1, failedIo)
      let failed = writer.reclaimExpectedEpoch(before, selected)
      assert pendingIo() == 0
      assert failed.error != PagedNativeError.None or failed.value.retirementError != FileError.None
      resetIo()
      discard writer.close
      assert openPagedWriter(writer, trial, config(fresh, true)).error == PagedNativeError.None
      assert writer.selected.value.bytes == selected.bytes
      assert writer.reclaimExpectedEpoch(before, selected).error == PagedNativeError.None
      assert writer.close == FileError.None
  for skip in 0..<2:
    # File and directory synchronization are separately observable and both poison an uncertain owner.
    let directory = path("sync-fault-" & $skip)
    var writer = default(PagedWriter)
    initialize(writer, directory, old, true)
    armIo(syncIo, cint(skip), 1, failedIo)
    assert writer.synchronize.error != PagedNativeError.None and pendingIo() == 0
    resetIo()
    assert writer.selected.error == PagedNativeError.RecoveryRequired
    discard writer.close
    assert openPagedWriter(writer, directory, config(old, true)).error == PagedNativeError.None
    assert writer.synchronize.value == StorageDurability.FileAndDirectorySynced
    assert writer.close == FileError.None
proc main() =
  ## Checked ARC and real syscall observers qualify lifecycle behavior without manufacturing complete state.
  let old = nativeFixture(7)
  let fresh = nativeFixture(9)
  lowLevel()
  nativeInventory(old)
  retirement(old, fresh)
  identities(old, fresh)
  faults(old, fresh)
  echo "storage paged restart PASS"
main()
