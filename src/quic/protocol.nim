# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Pinned JAMNP-S identity and CE framing checks, independent of peer scheduling and test
## workloads.
##
## Exposes nominal peer/frame lengths, peer-name validation, frame inspection and checked
## parsing results.

import ./transport as quic_transport

type
  FrameError* {.pure.} = enum ## Defaults, incomplete input and protocol failures never carry a successful extent.
    Uninitialized, None, Pending, InvalidPolicy, Truncated, InvalidKind, InvalidLength, Trailing, Overflow
  LengthResult* = object ## Only a complete checked E4 length carries a host-sized count.
    case status: FrameError
    of None:
      completed: int
    else:
      discard
  FrameResult* = object ## Only exact bytes followed by FIN carry usable payload size and whole-frame extent.
    case status: FrameError
    of None:
      payloadSize, completedExtent: int
    else:
      discard

func error*(value: LengthResult): FrameError =
  ## Read the reason without allowing callers to retag results or forge successful metadata.
  value.status
func error*(value: FrameResult): FrameError =
  ## Preserve incomplete versus malformed frame outcomes without exposing partial payload metadata.
  value.status
func value*(value: LengthResult): int {.inline, requires: value.status ==
    FrameError.None.} =
  ## Successful bounded lengths are usable only after selecting/checking success.
  value.completed
func size*(value: FrameResult): int {.inline, requires: value.status ==
    FrameError.None.} =
  ## The completed payload size is absent on default, pending and rejected frames.
  value.payloadSize
func extent*(value: FrameResult): int {.inline, requires: value.status ==
    FrameError.None.} =
  ## The completed frame extent includes its selector/header and is absent until exact FIN.
  value.completedExtent

proc peerName*(key: array[32, byte]): array[54, byte] {.raises: [].} =
  ## Literal least-significant-first radix-32 formula from the pinned JAMNP-S specification.
  result = default(array[54, byte])
  const alphabet = "$abcdefghijklmnopqrstuvwxyz234567"
  result[0] = byte('$')
  result[1] = byte('e')
  # The final group zero-extends the Ed25519 key beyond 256 bits.
  for group in 0..<52:
    var index = 0
    # Gather this group's five bits in little-endian order, not RFC base32 order.
    for bit in 0..<5:
      let position = group * 5 + bit
      if position < 256: index = index or (int((key[position div 8] shr (position mod 8)) and
          1) shl bit) # Only actual key bits contribute.
    result[2 + group] = byte(alphabet[index])

proc validPeer*(der: nil ptr byte, length: csize_t, expected: openArray[byte]): bool {.raises: [].} =
  ## Validate copied primitive certificate observations and optional expected identity entirely in Nim.
  # Reject missing/oversized borrows before entering the bounded primitive DER extractor.
  if der == nil or length == 0 or length > 8192: return false
  # The maintained C extractor zeroes the entire output before every parse attempt after this preflight.
  # Avoid constructing a C struct containing inline arrays through Nimony's native-array representation.
  var fields {.noinit.}: CertFields
  # DER is borrowed only for bounded synchronous extraction; no TLS-owned pointer is retained.
  if parseCert(der, length, addr fields) != 1: return false
  # Require both Ed25519 algorithms and exactly one DNS SAN.
  if fields.edKey != 1 or fields.edSignature != 1 or fields.keyLength != 32 or
      fields.sanExtensions != 1 or fields.sanCount != 1 or fields.sanDns != 1: return false
  var key = default(array[32, byte])
  # Copy C inline-array bytes individually into the language-owned fixed representation.
  for i in 0..<32: key[i] = fields.key[i]
  let name = peerName(key)
  # Exact byte length prevents prefix and embedded-NUL acceptance.
  if fields.sanLength != csize_t(name.len): return false
  # Every DNS SAN byte must be the exact key-derived identity.
  for i, value in name:
    if fields.san[i] != value: return false # Reject altered names.
  # Dialers pin the server key; acceptors may discover a consistent unknown peer.
  if expected.len > 0:
    if expected.len != 32: return false # No narrowing of malformed trusted identity input.
    for i in 0..<32:
      if expected[i] != fields.key[i]: return false # Compare full public keys.
  true

proc checkedLength*(header: openArray[byte], maximum: int): LengthResult =
  ## Validate an exact E4 header before host conversion, allocation or payload indexing.
  if maximum < 0: return LengthResult(status: FrameError.InvalidPolicy) # Invalid local policies cannot widen admission.
  if header.len != 4: return LengthResult(status: FrameError.Truncated) # Partial/oversized headers carry no length.
  var claimed = 0'u64
  # Assemble the four little-endian bytes independently of host width/endianness.
  for i in 0..<4: claimed = claimed or (uint64(header[i]) shl (8 * i))
  if claimed > uint64(maximum): return LengthResult(
      status: FrameError.InvalidLength) # Prove narrowing before conversion.
  LengthResult(status: FrameError.None, completed: int(claimed))

proc inspectFrame*(wire: openArray[byte], request: bool, maximum: int, fin: bool): FrameResult =
  ## Inspect one direction's framing; payload meaning remains the calling peer's policy.
  if maximum < 0: return FrameResult(status: FrameError.InvalidPolicy) # A negative ceiling cannot admit bytes.
  let start = if request: 1 else: 0
  if request and wire.len > 0 and wire[0] != 143: return FrameResult(
      status: FrameError.InvalidKind) # Only CE 143 is selected.
  let headerSize = start + 4
  if wire.len < headerSize:
    # A partial header may continue only while the sender's direction remains open.
    return FrameResult(status: if fin: FrameError.Truncated else: FrameError.Pending)
  let length = checkedLength(wire.toOpenArray(start, start + 3), maximum)
  if length.error != FrameError.None: return FrameResult(
      status: length.error) # Preserve typed size/policy failures.
  if length.value > high(int) - headerSize: return FrameResult(
      status: FrameError.Overflow) # Check before addition even on wrapping targets.
  let extent = headerSize + length.value
  if wire.len > extent: return FrameResult(status: FrameError.Trailing) # Exactly one message is allowed per direction.
  if not fin: return FrameResult(status: FrameError.Pending) # Exact bytes alone cannot substitute for required FIN.
  if wire.len != extent: return FrameResult(status: FrameError.Truncated) # FIN before the declared payload is terminal.
  FrameResult(status: FrameError.None, payloadSize: length.value, completedExtent: extent)
