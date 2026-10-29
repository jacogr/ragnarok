# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independent golden selections and anchors reject schema confusion, malformed metadata and provider failures.
# @@Verification={"arc":"storage_light_journal_manifest_arc_release"}
import std/[assertions, syncio]
import ../../support/arc_evidence
import ../../../src/storage/light/journal/manifest as light_journal_manifest
import ../../../src/storage/light/[snapshot as light_snapshot, delta as light_delta,
    state_cache as light_state_cache]
import ../../../src/storage/[state_proof, database_identity]
import ../../../src/storage/managed/manifest as managed_manifest
import ../../../src/storage/node/repository as node_repository
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc resetHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Provider refusal and no-provider preflight cases use the maintained observer.
proc calls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Structural and identity refusals precede cryptographic work.
proc hex(input: string): seq[byte] =
  ## Decode fixed independent Python hashlib/struct golden bytes without reusing production codecs.
  result = newSeq[byte](input.len div 2)
  for index in 0..<result.len:
    # The test-only literal alphabet is independently bounded to hexadecimal characters.
    var number = 0
    for slot in 0..<2:
      let value = input[index*2+slot]
      let digit = if value >= '0' and value <= '9': ord(value)-ord('0') else: ord(value)-ord('a')+10
      assert digit >= 0 and digit < 16
      number = number*16+digit
    result[index] = byte(number)
proc first(input: seq[byte], size: int): seq[byte] =
  ## Copy a proved proper prefix without invoking the pinned compiler's unsupported sequence slicing helper.
  assert size >= 0 and size <= input.len
  result = newSeq[byte](size)
  for index in 0..<size: result[index] = input[index]
proc cycle(image: PreparedLightSnapshot, golden, anchor: seq[byte]) =
  ## Retire detached bytes and scalar handles together, including failed and successful decode paths.
  let selected = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0),
      ByteLimit(171)).value
  let retained = selected
  var output = selected.bytes
  output[0] = 0
  assert retained.bytes == golden
  assert decodeLightJournalManifest(output, image.chainId, image.root, ByteLimit(171)).error ==
      LightSelectionError.InvalidFormat
  let decoded = decodeLightJournalManifest(golden, image.chainId, image.root, ByteLimit(171)).value
  assert decoded.bytes == golden
  assert encodeLightJournalAnchor(decoded, ByteLimit(98)).value == anchor
  assert validateLightJournalAnchor(anchor, retained, ByteLimit(98)) == LightSelectionError.None
proc main() =
  ## Exercise complete metadata, exact bounds, schema separation and every proper prefix before ARC stress.
  let policy = LightSnapshotLimits(bytes: ByteLimit(4096), cache: LightCacheLimits(
      items: ElementLimit(4),
    writes: ElementLimit(4), proof: StateProofLimits(nodes: ElementLimit(249),
        valueBytes: ByteLimit(256))))
  let image = prepareLightSnapshot(default(StorageChainId), default(StateRoot), [], policy).value
  let golden = hex("5241474e41524f4b2d4c494748542d4d414e49464553542d56310a0000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000001000000000000000000000000000000b0062d2eceea5d0d77cc73cf089516b5c93da78a780306862793f28089f268350e4c5b30436cc32df0d44fd1c72520ef85bb09034ad0e82c190884b3d15bf53d")
  let anchor = hex("5241474e41524f4b2d4c494748542d4a4f55524e414c2d56310a0e4c5b30436cc32df0d44fd1c72520ef85bb09034ad0e82c190884b3d15bf53d0000000000000000759fa19f7a95895a29f46cc0d07ff109672655c7a1cc86931119f6b03ebaa0f4")
  assert LightJournalManifestBytes == 171 and LightJournalAnchorBytes == 98
  assert not default(LightJournalManifest).initialized
  let selected = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0),
      ByteLimit(171)).value
  assert selected.initialized and uint64(selected.epoch) == 1 and uint64(selected.baseSequence) == 0
  assert array[32, byte](selected.chainId) == array[32, byte](image.chainId)
  assert array[32, byte](selected.root) == array[32, byte](image.root)
  assert array[32, byte](selected.snapshotChecksum) == array[32, byte](image.checksum)
  assert selected.bytes == golden
  assert encodeLightJournalAnchor(selected, ByteLimit(98)).value == anchor
  for size in 0..<golden.len:
    # No partial CURRENT selection is admitted or interpreted using another schema.
    let input = first(golden, size)
    assert decodeLightJournalManifest(input, image.chainId, image.root, ByteLimit(171)).error ==
        LightSelectionError.InvalidFormat
  for size in 0..<anchor.len:
    # Even an otherwise matching partial anchor grants no replay or repair authority.
    let input = first(anchor, size)
    assert validateLightJournalAnchor(input, selected, ByteLimit(98)) ==
        LightSelectionError.InvalidFormat
  var extra = golden
  extra.add(0)
  assert decodeLightJournalManifest(extra, image.chainId, image.root, ByteLimit(172)).error ==
      LightSelectionError.InvalidFormat
  extra = anchor
  extra.add(0)
  assert validateLightJournalAnchor(extra, selected, ByteLimit(99)) ==
      LightSelectionError.InvalidFormat
  var chain = default(array[32, byte])
  chain[0] = 1
  resetHash(0)
  let wrongChain = decodeLightJournalManifest(golden, StorageChainId(chain), image.root, ByteLimit(171))
  let wrongRoot = decodeLightJournalManifest(golden, image.chainId, StateRoot(chain), ByteLimit(171))
  assert wrongChain.error == LightSelectionError.WrongChain and wrongRoot.error ==
      LightSelectionError.WrongRoot
  var malformed = golden
  malformed[91] = 0
  assert decodeLightJournalManifest(malformed, image.chainId, image.root, ByteLimit(171)).error ==
      LightSelectionError.InvalidFormat
  let zero = prepareLightJournalManifest(image, ManagedEpoch(0), LightDeltaSequence(0), ByteLimit(171))
  let short = prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0), ByteLimit(170))
  assert zero.error == LightSelectionError.InvalidFormat and short.error ==
      LightSelectionError.LimitExceeded
  assert decodeLightJournalManifest(golden, image.chainId, image.root, ByteLimit(170)).error ==
      LightSelectionError.LimitExceeded
  assert encodeLightJournalAnchor(selected, ByteLimit(97)).error ==
      LightSelectionError.LimitExceeded
  assert validateLightJournalAnchor(anchor, selected, ByteLimit(97)) ==
      LightSelectionError.LimitExceeded
  assert calls() == 0
  malformed = golden
  malformed[malformed.len-1] = malformed[malformed.len-1] xor 1
  assert decodeLightJournalManifest(malformed, image.chainId, image.root, ByteLimit(171)).error ==
      LightSelectionError.ChecksumMismatch
  malformed = anchor
  malformed[malformed.len-1] = malformed[malformed.len-1] xor 1
  assert validateLightJournalAnchor(malformed, selected, ByteLimit(98)) ==
      LightSelectionError.ChecksumMismatch
  for offset in [26, 58]:
    # Either a different selected manifest or a different baseline fails before provider work.
    malformed = anchor
    malformed[offset] = malformed[offset] xor 1
    resetHash(0)
    assert validateLightJournalAnchor(malformed, selected, ByteLimit(98)) ==
        LightSelectionError.WrongAnchor
    assert calls() == 0
  let maximum = prepareLightJournalManifest(image, ManagedEpoch(high(uint64)), LightDeltaSequence(
      high(uint64)), ByteLimit(171)).value
  let restored = decodeLightJournalManifest(maximum.bytes, image.chainId, image.root, ByteLimit(171)).value
  assert uint64(restored.epoch) == high(uint64) and uint64(restored.baseSequence) == high(uint64)
  assert validateLightJournalAnchor(anchor, maximum, ByteLimit(98)) ==
      LightSelectionError.WrongAnchor
  let full = encodeManagedManifest(image.chainId, StorageSchema.FullNodesV1, ManagedEpoch(1),
      RepositoryGeneration(1), image.root, image.checksum, ByteLimit(4096)).value
  let fullInput = decodeLightJournalManifest(full.bytes, image.chainId, image.root, ByteLimit(4096))
  let imageInput = decodeLightJournalManifest(image.bytes, image.chainId, image.root, ByteLimit(4096))
  assert fullInput.error == LightSelectionError.InvalidFormat and imageInput.error ==
      LightSelectionError.InvalidFormat
  assert decodeManagedManifest(golden, image.chainId, StorageSchema.FullNodesV1, ByteLimit(
      4096)).error == ManifestError.InvalidFormat
  assert restoreLightSnapshot(golden, image.chainId, image.root, policy).error ==
      LightSnapshotError.InvalidFormat
  let defaultManifest = default(LightJournalManifest)
  assert encodeLightJournalAnchor(defaultManifest, ByteLimit(98)).error ==
      LightSelectionError.Uninitialized
  assert validateLightJournalAnchor(anchor, defaultManifest, ByteLimit(98)) ==
      LightSelectionError.Uninitialized
  assert prepareLightJournalManifest(default(PreparedLightSnapshot), ManagedEpoch(1),
      LightDeltaSequence(0), ByteLimit(171)).error == LightSelectionError.Uninitialized
  resetHash(1)
  assert prepareLightJournalManifest(image, ManagedEpoch(1), LightDeltaSequence(0), ByteLimit(
      171)).error == LightSelectionError.BackendFailure
  assert decodeLightJournalManifest(golden, image.chainId, image.root, ByteLimit(171)).error ==
      LightSelectionError.BackendFailure
  assert encodeLightJournalAnchor(selected, ByteLimit(98)).error ==
      LightSelectionError.BackendFailure
  assert validateLightJournalAnchor(anchor, selected, ByteLimit(98)) ==
      LightSelectionError.BackendFailure
  resetHash(0)
  let occupied = getOccupiedMem()
  for index in 0..<1000:
    # Each scope retires all temporary transport and checked scalar results before the next sample.
    cycle(image, golden, anchor)
  recordArcRelease("storage_light_journal_manifest", 1000, occupied, getOccupiedMem())
  echo "PASS light journal selections: independent manifest/anchor bytes, explicit schemas, identity and bounded ownership"
main()
