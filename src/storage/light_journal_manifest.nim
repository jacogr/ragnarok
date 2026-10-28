# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A distinct local selection schema anchors light journal epochs without full-image or full-state fallback.
import std/assertions
import ./light_snapshot as storage_light_snapshot
import ./light_delta as storage_light_delta
import ./database_identity as storage_database_identity
import ./managed_manifest as storage_managed_manifest
import ../codec/bounded as codec_bounded
import ../codec/state_trie as codec_state_trie
import ../crypto/primitives as crypto_primitives
const
  Magic = "RAGNAROK-LIGHT-MANIFEST-V1\n"
  AnchorMagic = "RAGNAROK-LIGHT-JOURNAL-V1\n"
  LightJournalManifestBytes* = Magic.len+144 ## Fixed chain/root/epoch/baseline/image/checksum fields.
  LightJournalAnchorBytes* = AnchorMagic.len+72 ## Fixed selected manifest checksum, sequence and own checksum.
type
  LightSelectionError* {.pure.} = enum ## Neither default nor failed operations expose a selected physical epoch.
    Uninitialized, None, InvalidFormat, LimitExceeded, WrongChain, WrongRoot, WrongAnchor,
    ChecksumMismatch, BackendFailure
  LightJournalManifest* = object ## Private checked scalar authority has no mutable encoded backing or unchecked constructor.
    ready: bool
    chain: StorageChainId
    stateRoot: StateRoot
    selectedEpoch: ManagedEpoch
    baseline: LightDeltaSequence
    imageChecksum: StorageChecksum
    integrity: StorageChecksum
  LightSelectionResult*[T] = object ## Only the checked success alternative carries metadata or detached transport.
    case status: LightSelectionError
    of None: completed: T
    else: discard
func error*[T](outcome: LightSelectionResult[T]): LightSelectionError =
  ## Inspect a typed refusal without completed-data access.
  outcome.status
func value*[T](outcome: LightSelectionResult[T]): T {.inline,
    requires: outcome.status == LightSelectionError.None.} =
  ## Extract only a complete checked selection or detached encoded bytes.
  outcome.completed
func initialized*(manifest: LightJournalManifest): bool =
  ## Default scalar handles safely report their missing selection authority.
  manifest.ready
func chainId*(manifest: LightJournalManifest): StorageChainId {.requires: manifest.ready.} =
  ## Return the independently selected chain identity by value.
  manifest.chain
func root*(manifest: LightJournalManifest): StateRoot {.requires: manifest.ready.} =
  ## Return the complete trusted root; partial evidence never supplies it.
  manifest.stateRoot
func epoch*(manifest: LightJournalManifest): ManagedEpoch {.requires: manifest.ready.} =
  ## Read the positive physical file epoch independently of update sequence.
  manifest.selectedEpoch
func baseSequence*(manifest: LightJournalManifest): LightDeltaSequence {.requires: manifest.ready.} =
  ## Read the checkpoint's local sequence, including the initial zero baseline.
  manifest.baseline
func snapshotChecksum*(manifest: LightJournalManifest): StorageChecksum {.requires: manifest.ready.} =
  ## Bind the selected checkpoint to one exact canonical light evidence image.
  manifest.imageChecksum
func checksum*(manifest: LightJournalManifest): StorageChecksum {.requires: manifest.ready.} =
  ## Bind a journal anchor to this entire checked selection.
  manifest.integrity
func refused[T](reason: LightSelectionError): LightSelectionResult[T] =
  ## Failure leaves the inactive success payload uninitialized.
  LightSelectionResult[T](status: reason)
proc put(output: var seq[byte], offset: int, value: uint64) =
  ## Fixed preallocated widths prove every little-endian metadata write.
  for index in 0..<8: output[offset+index] = byte((value shr (8*index)) and 255)
func number(input: openArray[byte], offset: int): uint64 =
  ## Exact manifest/header widths precede every numeric read.
  result = 0
  for index in 0..<8: result = result or (uint64(input[offset+index]) shl (8*index))
proc putHash(output: var seq[byte], offset: int, value: array[32, byte]) =
  ## Fixed field extents precede scalar copies.
  for index in 0..<32: output[offset+index] = value[index]
func hashAt(input: openArray[byte], offset: int): array[32, byte] =
  ## Fixed field extents precede scalar extraction.
  result = default(array[32, byte])
  for index in 0..<32: result[index] = input[offset+index]
proc prefix(manifest: LightJournalManifest): seq[byte] =
  ## Serialize private metadata with a reserved footer; callers establish initialization before entry.
  result = newSeq[byte](LightJournalManifestBytes)
  for index, character in Magic: result[index] = byte(character)
  putHash(result, Magic.len, array[32, byte](manifest.chain))
  putHash(result, Magic.len+32, array[32, byte](manifest.stateRoot))
  put(result, Magic.len+64, uint64(manifest.selectedEpoch))
  put(result, Magic.len+72, uint64(manifest.baseline))
  putHash(result, Magic.len+80, array[32, byte](manifest.imageChecksum))
proc bytes*(manifest: LightJournalManifest): seq[byte] {.requires: manifest.ready.} =
  ## Return detached transport; mutations cannot alter the checked scalar selection.
  result = prefix(manifest)
  putHash(result, result.len-32, array[32, byte](manifest.integrity))
proc prepareLightJournalManifest*(image: PreparedLightSnapshot, epoch: ManagedEpoch,
    baseline: LightDeltaSequence, limit: ByteLimit): LightSelectionResult[LightJournalManifest] =
  ## Construct only from an authenticated image and positive physical epoch; zero local sequence is valid.
  if not image.initialized: return refused[LightJournalManifest](LightSelectionError.Uninitialized)
  if uint64(epoch) == 0: return refused[LightJournalManifest](LightSelectionError.InvalidFormat)
  if uint64(limit) < uint64(LightJournalManifestBytes): return refused[LightJournalManifest](
      LightSelectionError.LimitExceeded)
  var manifest = LightJournalManifest(ready: true, chain: image.chainId, stateRoot: image.root,
    selectedEpoch: epoch, baseline: baseline, imageChecksum: image.checksum)
  let encoded = prefix(manifest)
  let hashed = blake2b256(encoded.toOpenArray(0, encoded.len-33))
  if hashed.error != CryptoError.None: return refused[LightJournalManifest](
      LightSelectionError.BackendFailure)
  manifest.integrity = StorageChecksum(array[32, byte](hashed.value))
  LightSelectionResult[LightJournalManifest](status: LightSelectionError.None, completed: manifest)
proc decodeLightJournalManifest*(input: openArray[byte], chain: StorageChainId, root: StateRoot,
    limit: ByteLimit): LightSelectionResult[LightJournalManifest] =
  ## Require one exact schema, caller identity, positive epoch and checksum with no fallback or trailing bytes.
  if uint64(input.len) > uint64(limit): return refused[LightJournalManifest](
      LightSelectionError.LimitExceeded)
  if input.len != LightJournalManifestBytes: return refused[LightJournalManifest](
      LightSelectionError.InvalidFormat)
  for index, character in Magic:
    if input[index] != byte(character): return refused[LightJournalManifest](
        LightSelectionError.InvalidFormat)
  if hashAt(input, Magic.len) != array[32, byte](chain): return refused[LightJournalManifest](
      LightSelectionError.WrongChain)
  if hashAt(input, Magic.len+32) != array[32, byte](root): return refused[LightJournalManifest](
      LightSelectionError.WrongRoot)
  let epoch = number(input, Magic.len+64)
  if epoch == 0: return refused[LightJournalManifest](LightSelectionError.InvalidFormat)
  let hashed = blake2b256(input.toOpenArray(0, input.len-33))
  if hashed.error != CryptoError.None: return refused[LightJournalManifest](
      LightSelectionError.BackendFailure)
  let checksum = array[32, byte](hashed.value)
  if hashAt(input, input.len-32) != checksum: return refused[LightJournalManifest](
      LightSelectionError.ChecksumMismatch)
  LightSelectionResult[LightJournalManifest](status: LightSelectionError.None,
    completed: LightJournalManifest(ready: true, chain: chain, stateRoot: root,
      selectedEpoch: ManagedEpoch(epoch), baseline: LightDeltaSequence(number(input, Magic.len+72)),
      imageChecksum: StorageChecksum(hashAt(input, Magic.len+80)), integrity: StorageChecksum(checksum)))
proc encodeLightJournalAnchor*(manifest: LightJournalManifest,
    limit: ByteLimit): LightSelectionResult[seq[byte]] =
  ## Bind the new journal to the exact selected manifest and checkpoint sequence under its own checksum.
  if not manifest.initialized: return refused[seq[byte]](LightSelectionError.Uninitialized)
  if uint64(limit) < uint64(LightJournalAnchorBytes): return refused[seq[byte]](
      LightSelectionError.LimitExceeded)
  var output = newSeq[byte](LightJournalAnchorBytes)
  for index, character in AnchorMagic: output[index] = byte(character)
  putHash(output, AnchorMagic.len, array[32, byte](manifest.checksum))
  put(output, AnchorMagic.len+32, uint64(manifest.baseSequence))
  let hashed = blake2b256(output.toOpenArray(0, output.len-33))
  if hashed.error != CryptoError.None: return refused[seq[byte]](LightSelectionError.BackendFailure)
  putHash(output, output.len-32, array[32, byte](hashed.value))
  LightSelectionResult[seq[byte]](status: LightSelectionError.None, completed: output)
proc validateLightJournalAnchor*(input: openArray[byte], manifest: LightJournalManifest,
    limit: ByteLimit): LightSelectionError =
  ## Validate exactly one anchor before any following frame is interpreted; incomplete anchors are never repair authority.
  if not manifest.initialized: return LightSelectionError.Uninitialized
  if uint64(input.len) > uint64(limit): return LightSelectionError.LimitExceeded
  if input.len != LightJournalAnchorBytes: return LightSelectionError.InvalidFormat
  for index, character in AnchorMagic:
    if input[index] != byte(character): return LightSelectionError.InvalidFormat
  if hashAt(input, AnchorMagic.len) != array[32, byte](manifest.checksum) or
      number(input, AnchorMagic.len+32) != uint64(
          manifest.baseSequence): return LightSelectionError.WrongAnchor
  let hashed = blake2b256(input.toOpenArray(0, input.len-33))
  if hashed.error != CryptoError.None: return LightSelectionError.BackendFailure
  if hashAt(input, input.len-32) != array[32, byte](
      hashed.value): return LightSelectionError.ChecksumMismatch
  LightSelectionError.None
