# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 header.tex extrinsic commitment: five family hashes over their prescribed
## projections. Inputs are immutable codec owners; all temporary bytes and returned digests are
## independently owned.
##
## Exposes extrinsicCommitment over immutable extrinsic components and a checked owned digest
## result.

import ../codec/[block_codec, header, owned, report_owned, guarantees, natural, bounded]
import ./primitives

type
  ExtrinsicCommitmentError* {.pure.} = enum ## Default/refused commitments contain no digest, partial family hashes or consumed progress.
    Uninitialized, None, InvalidOwner, LimitExceeded, LengthOverflow, BackendFailure
  ExtrinsicCommitmentResult*[T] = object ## Private discriminator/payload guard every successful digest or internal temporary extraction.
    case status: ExtrinsicCommitmentError
    of None:
      completed: T # Only fully completed operations can expose bytes or a nominal extrinsic root.
    else:
      discard      # No successful prefix escapes a refusal.

func error*[T](outcome: ExtrinsicCommitmentResult[T]): ExtrinsicCommitmentError =
  ## Inspect failure without permitting result retagging.
  outcome.status
func value*[T](outcome: ExtrinsicCommitmentResult[T]): T {.inline,
    requires: outcome.status == ExtrinsicCommitmentError.None.} =
  ## Extract only after selecting complete success.
  outcome.completed

## Copy a schema-bound component only after its complete immutable extent fits the caller's ceiling.
proc wire[K: static[ComponentKind]](owner: Component[K], limit: ByteLimit):
    ExtrinsicCommitmentResult[seq[byte]] =
  let info = componentInfo(owner)
  if info.error != FrameError.None:
    return ExtrinsicCommitmentResult[seq[byte]](status: ExtrinsicCommitmentError.InvalidOwner) # No default component.
  if uint64(info.value.consumed) > uint64(limit):
    return ExtrinsicCommitmentResult[seq[byte]](status: ExtrinsicCommitmentError.LimitExceeded) # Pre-copy bound.
  var bytes = newSeq[byte](info.value.consumed)
  let encoded = encodeComponent(owner, bytes)
  if encoded.error != FrameError.None:
    return ExtrinsicCommitmentResult[seq[byte]](status: ExtrinsicCommitmentError.InvalidOwner) # No invalid component can be hashed as empty.
  ExtrinsicCommitmentResult[seq[byte]](status: ExtrinsicCommitmentError.None, completed: bytes)

## Prove aggregate projected bytes and native addressing before any extent addition/allocation.
func charge(total: var int, count, width: int, limit: ByteLimit): ExtrinsicCommitmentError =
  if count < 0 or count > (high(int)-total) div width:
    return ExtrinsicCommitmentError.LengthOverflow # Multiplication/addition cannot wrap under Nimony.
  let size = count*width
  if uint64(total) > uint64(limit) or uint64(size) > uint64(limit)-uint64(total):
    return ExtrinsicCommitmentError.LimitExceeded # Bound the complete five-family projection, not each part independently.
  total += size
  ExtrinsicCommitmentError.None

## Write canonical natural prefix octets into an already preflighted private destination.
proc prefix(value: uint64, destination: var seq[byte], cursor: var int) =
  let encoded = natural.encode(JamNatural(value))
  for i in 0..<int(encoded.len):
    destination[cursor] = encoded.bytes[i] # No outer sequence count is added to the fixed five hashes.
    inc cursor

## Copy fixed digest/credential octets into a preflighted buffer without exposing retained owner storage.
proc put(bytes: openArray[byte], destination: var seq[byte], cursor: var int) =
  for octet in bytes:
    destination[cursor] = octet # All destination lengths were proved before cryptographic work.
    inc cursor

proc extrinsicCommitment*(owner: OwnedExtrinsic, maxBytes: ByteLimit):
    ExtrinsicCommitmentResult[ExtrinsicRoot] =
  ## Hash exact T, projected P/G, A and D; hash their five ordered 32-byte results without an outer count.
  ## maxBytes independently caps original extrinsic wire and the aggregate projected encodings.
  ## Preimages become E4(service)||B(blob); guarantees become B(report)||E4(slot)||var(credentials).
  let info = extrinsicInfo(owner)
  if info.error != FrameError.None:
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: ExtrinsicCommitmentError.InvalidOwner) # Default is not seven-byte empty extrinsic.
  if uint64(info.value.consumed) > uint64(maxBytes):
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: ExtrinsicCommitmentError.LimitExceeded) # Bound every materialization before copying.
  var parts = default(array[5, seq[byte]])
  let tickets = wire(extrinsicTickets(owner).value, maxBytes)
  let assurances = wire(extrinsicAssurances(owner).value, maxBytes)
  let disputes = wire(extrinsicDisputes(owner).value, maxBytes)
  # Named predicates keep boolean tokens intact under the pinned formatter.
  let invalidTickets = tickets.error != ExtrinsicCommitmentError.None
  let invalidAssurances = assurances.error != ExtrinsicCommitmentError.None
  let invalidDisputes = disputes.error != ExtrinsicCommitmentError.None
  if invalidTickets or invalidAssurances or invalidDisputes:
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: ExtrinsicCommitmentError.InvalidOwner) # Immutable valid parent proves complete matching children.
  parts[0] = tickets.value
  parts[3] = assurances.value
  parts[4] = disputes.value
  let images = readPreimages(extrinsicPreimages(owner).value)
  let reports = readGuarantees(extrinsicGuarantees(owner).value)
  if images.error != OwnershipError.None or reports.error != GuaranteeError.None:
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: ExtrinsicCommitmentError.InvalidOwner) # Select complete owners before record traversal.
  var total = 0
  for index in [0, 3, 4]:
    let reason = charge(total, parts[index].len, 1, maxBytes)
    if reason != ExtrinsicCommitmentError.None:
      return ExtrinsicCommitmentResult[ExtrinsicRoot](
          status: reason) # Plain families also count toward projected bytes.
  let preimageCount = ownedInfo(images.value).value.blobCount
  let imagePrefix = natural.encode(JamNatural(uint64(preimageCount)))
  var imageSize = 0
  var reason = charge(imageSize, int(imagePrefix.len), 1, maxBytes)
  if reason == ExtrinsicCommitmentError.None:
    reason = charge(imageSize, preimageCount, 36, maxBytes) # Fixed E4 service plus 32-byte blob hash.
  if reason != ExtrinsicCommitmentError.None:
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: reason) # Preserve the classified projection extent/budget refusal.
  reason = charge(total, imageSize, 1, maxBytes)
  if reason != ExtrinsicCommitmentError.None:
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: reason) # Prove aggregate before allocating projection storage.
  let guaranteeCount = reports.value.count
  let guaranteePrefix = natural.encode(JamNatural(uint64(guaranteeCount)))
  var guaranteeSize = int(guaranteePrefix.len)
  for i in 0..<guaranteeCount:
    let record = guaranteeAt(reports.value.owner, i).value
    let countPrefix = natural.encode(JamNatural(uint64(record.credentialCount)))
    reason = charge(guaranteeSize, 36+int(countPrefix.len), 1, maxBytes)
    if reason == ExtrinsicCommitmentError.None:
      reason = charge(guaranteeSize, record.credentialCount, 66,
          maxBytes) # E2 index and 64-byte signature per credential.
    if reason != ExtrinsicCommitmentError.None:
      return ExtrinsicCommitmentResult[ExtrinsicRoot](status: reason) # No partial projection reaches hashing.
  reason = charge(total, guaranteeSize, 1, maxBytes)
  if reason != ExtrinsicCommitmentError.None:
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: reason) # Preserve the classified projection extent/budget refusal.
  parts[1] = newSeq[byte](imageSize)
  parts[2] = newSeq[byte](guaranteeSize)
  var cursor = 0
  prefix(uint64(preimageCount), parts[1], cursor)
  for i in 0..<preimageCount:
    let size = ownedBlobLength(images.value, i).value
    var bytes = newSeq[byte](size) # Original captured wire already bounds each payload before this copy.
    discard copyOwnedBlob(images.value, i, bytes).value
    let digest = blake2b256(bytes)
    if digest.error != CryptoError.None:
      return ExtrinsicCommitmentResult[ExtrinsicRoot](
          status: ExtrinsicCommitmentError.BackendFailure) # No synthetic blob digest after refusal.
    let service = uint32(ownedService(images.value, i).value)
    for j in 0..<4:
      parts[1][cursor] = byte((service shr (8*j)) and 255) # E4 is little endian on every host.
      inc cursor
    put(array[32, byte](digest.value), parts[1], cursor)
  cursor = 0
  prefix(uint64(guaranteeCount), parts[2], cursor)
  for i in 0..<guaranteeCount:
    let record = guaranteeAt(reports.value.owner, i).value
    var bytes = newSeq[byte](ownedReportInfo(record.report).value.consumed)
    discard encodeOwnedReport(record.report, bytes).value # Hash the entire canonical report, not a signing-domain transcript.
    let digest = blake2b256(bytes)
    if digest.error != CryptoError.None:
      return ExtrinsicCommitmentResult[ExtrinsicRoot](
          status: ExtrinsicCommitmentError.BackendFailure) # Refused report hashes never become successful zero identifiers.
    put(array[32, byte](digest.value), parts[2], cursor)
    for j in 0..<4:
      parts[2][cursor] = byte((uint32(record.slot) shr (8*j)) and
          255) # Slot remains E4, independently of report hash.
      inc cursor
    prefix(uint64(record.credentialCount), parts[2], cursor)
    for j in 0..<record.credentialCount:
      let credential = record.credentials[j]
      for k in 0..<2:
        parts[2][cursor] = byte((uint16(credential.validator) shr (8*k)) and
            255) # Preserve E2 validator domain and ordinal order.
        inc cursor
      put(array[64, byte](credential.signature), parts[2], cursor)
  var families = default(array[160, byte])
  for i in 0..<5:
    let digest = blake2b256(parts[i])
    if digest.error != CryptoError.None:
      return ExtrinsicCommitmentResult[ExtrinsicRoot](
          status: ExtrinsicCommitmentError.BackendFailure) # A late family refusal exposes no prefix.
    let octets = array[32, byte](digest.value)
    for j in 0..<32: families[i*32+j] = octets[j] # Fixed five hashes carry no natural outer count.
  let digest = blake2b256(families)
  if digest.error != CryptoError.None:
    return ExtrinsicCommitmentResult[ExtrinsicRoot](
        status: ExtrinsicCommitmentError.BackendFailure) # Final refusal exposes no family prefix or root.
  ExtrinsicCommitmentResult[ExtrinsicRoot](status: ExtrinsicCommitmentError.None,
    completed: ExtrinsicRoot(array[32, byte](digest.value)))
