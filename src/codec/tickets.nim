# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## GP 0.8.0 Appendix C.2 tickets extrinsic: E(count) followed by E1 attempt and 784 proof bytes.
## Proofs and attempts are structural values here; Safrole eligibility and cryptography are
## external.
##
## Exposes Ticket and TicketAttempt domains, encodeTickets/decodeTickets, inspection and checked
## count/extent results.

import ./natural

type
  # An entry index occupies exactly one octet, including values whose compact encoding would be longer.
  TicketAttempt* = distinct uint8
  # Opaque fixed-width RingVRF encoding; construction does not assert cryptographic validity.
  TicketProof* = distinct array[784, byte]
  # Explicit caller count ceiling; tiny/full profiles use three/sixteen respectively.
  TicketLimit* = distinct uint64
  # Every record owns all bytes and can outlive its source buffer without an owner handle.
  Ticket* = object
    attempt*: TicketAttempt
    proof*: TicketProof
  # Default and all failed outcomes contain no usable progress or record values.
  TicketError* {.pure.} = enum
    Uninitialized, None, Truncated, NonCanonical, LimitExceeded, OutputTooSmall,
    AliasedBuffers, LengthOverflow
  # Successful encoding reports only its complete committed prefix length.
  TicketWrite* = object
    case status: TicketError
    of None:
      byteWritten: int
    else:
      # Failed encodes leave the complete destination untouched.
      discard
  # Successful decoding selects the written typed prefix and exact source prefix length.
  TicketRead* = object
    case status: TicketError
    of None:
      recordCount, byteConsumed: int
    else:
      # A failed read publishes no partial count or cursor.
      discard

# Read write outcomes without exposing a mutable discriminator.
func error*(value: TicketWrite): TicketError = value.status
# Read decode/inspection outcomes; failed/default alternatives carry no progress.
func error*(value: TicketRead): TicketError = value.status
# Successful preflight and commit are required before observing the written prefix.
func written*(value: TicketWrite): int {.inline, requires: value.status == TicketError.None.} =
  value.byteWritten
# Only a complete validated sequence exposes its initialized record count.
func count*(value: TicketRead): int {.inline, requires: value.status == TicketError.None.} =
  value.recordCount
# Failed decode/inspection cannot advance a caller's input cursor.
func consumed*(value: TicketRead): int {.inline, requires: value.status == TicketError.None.} =
  value.byteConsumed

# Nominal attempt equality supports fully owned record comparisons without implicit integer conversion.
func `==`*(a, b: TicketAttempt): bool {.borrow.}
# Proof equality compares bytes without converting proof encodings into other cryptographic roles.
func `==`*(a, b: TicketProof): bool {.borrow.}

# Compare address distances without overflowing endpoints; zero-length ranges have no overlap.
proc overlaps(a: pointer, an: int, b: pointer, bn: int): bool {.raises: [].} =
  # Empty typed/wire prefixes require no valid element address.
  if an == 0 or bn == 0: return false
  let left = cast[uint](a)
  let right = cast[uint](b)
  # Subtract from the lower address, keeping unsigned arithmetic bounded.
  if left <= right: right-left < uint(an)
  else: left-right < uint(bn) # Reverse the ranges when output starts first.

# Validate the entire source extent and output before committing a canonical tickets extrinsic.
proc encodeTickets*(values: openArray[Ticket], limit: TicketLimit,
                    output: var openArray[byte]): TicketWrite {.raises: [].} =
  # Count policy precedes extent arithmetic, allocation or any destination access.
  if uint64(values.len) > uint64(limit): return TicketWrite(status: TicketError.LimitExceeded)
  let prefix = natural.encode(JamNatural(values.len))
  # Both wire stride and host record stride must be representable before alias checks.
  if values.len > (high(int)-prefix.len) div 785 or values.len > high(int) div sizeof(Ticket):
    return TicketWrite(status: TicketError.LengthOverflow)
  let required = prefix.len+785*values.len
  # Require the whole destination, including the final proof byte, before any write.
  if output.len < required: return TicketWrite(status: TicketError.OutputTooSmall)
  # Stable source records must not be overwritten by the count or any earlier record.
  if values.len > 0 and overlaps(unsafeAddr values[0], values.len*sizeof(Ticket), addr output[0], required):
    return TicketWrite(status: TicketError.AliasedBuffers)
  # Only the measured natural prefix is emitted; unused encoder storage remains private.
  for i in 0..<prefix.len: output[i] = prefix.bytes[i]
  var cursor = int(prefix.len)
  # Commit owned fields in normative order; attempts use E1 rather than general naturals.
  for value in values:
    output[cursor] = byte(value.attempt)
    let proof = array[784, byte](value.proof)
    # Copy every proof byte without invoking cryptography or retaining a caller pointer.
    for i in 0..<784: output[cursor+1+i] = proof[i]
    cursor += 785
  TicketWrite(status: TicketError.None, byteWritten: required)

# Decode into fully owned caller records atomically, consuming exactly one extrinsic prefix.
proc decodeTickets*(input: openArray[byte], limit: TicketLimit,
                    output: var openArray[Ticket]): TicketRead {.raises: [].} =
  let prefix = natural.decode(input)
  # Preserve canonicality/truncation reasons before any untrusted count can be narrowed.
  if not prefix.ok:
    return TicketRead(status: if prefix.error == natural.truncated: TicketError.Truncated
      else: TicketError.NonCanonical) # Overlong count encodings are not canonical extrinsics.
  let count = uint64(prefix.value)
  # Count policy bounds work before proving the complete wire stride.
  if count > uint64(limit): return TicketRead(status: TicketError.LimitExceeded)
  # Division proves the raw extent without multiplying an attacker-controlled count.
  if count > uint64((input.len-prefix.consumed) div 785):
    return TicketRead(status: TicketError.Truncated)
  # The wire proof above also proves count fits host int; typed storage still needs its own capacity.
  if count > uint64(output.len): return TicketRead(status: TicketError.OutputTooSmall)
  let size = int(count)
  # A forged/oversized typed extent must not overflow overlap arithmetic.
  if size > high(int) div sizeof(Ticket): return TicketRead(status: TicketError.LengthOverflow)
  let consumed = prefix.consumed+size*785
  # Protect all borrowed input, including trailing bytes, from writes to the typed result prefix.
  if size > 0 and overlaps(unsafeAddr input[0], input.len, addr output[0], size*sizeof(Ticket)):
    return TicketRead(status: TicketError.AliasedBuffers)
  var cursor = int(prefix.consumed)
  # No remaining field can fail: every attempt/proof byte pattern has a structural representation.
  for i in 0..<size:
    output[i].attempt = TicketAttempt(input[cursor])
    var proof: array[784, byte] = default(array[784, byte])
    # Copy into private local storage before committing the complete owned proof value.
    for j in 0..<784: proof[j] = input[cursor+1+j]
    output[i].proof = TicketProof(proof)
    cursor += 785
  TicketRead(status: TicketError.None, recordCount: size, byteConsumed: consumed)

# Inspect complete ticket framing without allocating records or exposing any borrowed proof bytes.
proc inspectTickets*(input: openArray[byte], limit: TicketLimit): TicketRead {.raises: [].} =
  let prefix = natural.decode(input)
  # An incomplete/overlong count cannot authorize a record extent or host conversion.
  if not prefix.ok:
    return TicketRead(status: if prefix.error == natural.truncated: TicketError.Truncated
      else: TicketError.NonCanonical) # Canonical framing precedes count policy.
  let count = uint64(prefix.value)
  # Apply the same configured count ceiling as the existing caller-record decoder.
  if count > uint64(limit): return TicketRead(status: TicketError.LimitExceeded)
  # Every attempt/proof bit pattern is structurally valid; division proves the whole fixed sequence.
  if count > uint64((input.len-int(prefix.consumed)) div 785):
    return TicketRead(status: TicketError.Truncated)
  TicketRead(status: TicketError.None, recordCount: int(count), byteConsumed: int(
      prefix.consumed)+int(count)*785)
