# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Authored canonical sealed chains exercise capture, profile limits and immutable retained ownership.
import std/[assertions, syncio]
import ../../../src/state/ancestor_context
import ../../../src/codec/[bounded, header, assurances, tickets]
import ../../../src/crypto/primitives

proc profile(): HeaderConfig =
  ## Explicit tiny profile; no production or fixture default is inferred.
  HeaderConfig(cores: CoreCount(2), authorValidators: ValidatorCount(6),
    epochSlots: EpochSlots(12), maxBytes: ByteLimit(10000))
proc header(slot: uint32, parent: HeaderParent = default(HeaderParent)): OwnedHeader =
  ## Independently serialize a full sealed structural header with no transition authority.
  var source = default(Header)
  source.unsigned.slot = HeaderSlot(slot)
  source.unsigned.parent = parent
  var wire = newSeq[byte](10000)
  let encoded = encodeHeader(source, profile(), wire)
  assert encoded.error == HeaderError.None
  decodeHeader(wire.toOpenArray(0, encoded.value - 1), profile()).value.owner
proc digest(owner: OwnedHeader): HeaderParent =
  ## Hash actual complete canonical bytes independently of the context's stored identities.
  var wire = newSeq[byte](owner.headerInfo.value.consumed)
  assert encodeOwnedHeader(owner, wire).error == HeaderError.None
  HeaderParent(array[32, byte](blake2b256(wire).value))
proc main() =
  ## Every refusal must discard progress and leave independently retained contexts usable.
  let oldest = header(3)
  let middle = header(10, digest(oldest))
  let parent = header(11, digest(middle))
  var limits = AncestorContextLimits(header: profile(), headers: ElementLimit(3),
      maxBytes: ByteLimit(10000))
  let empty = default(AncestorContext)
  assert not empty.valid and empty.len == 0 and empty.serializedBytes == 0
  assert empty.headerAt(0).error == AncestorContextError.Uninitialized
  assert empty.hashAt(0).error == AncestorContextError.Uninitialized
  var older = @[middle, oldest]
  let captured = captureAncestorContext(parent, older, limits)
  assert captured.error == AncestorContextError.None
  let context = captured.value
  assert context.valid and context.len == 3
  assert array[32, byte](context.hashAt(0).value) == array[32, byte](digest(parent))
  assert array[32, byte](context.hashAt(2).value) == array[32, byte](digest(oldest))
  assert uint32(context.headerAt(1).value.headerInfo.value.unsigned.slot) == 10
  older[0] = default(OwnedHeader)
  assert context.headerAt(1).value.headerInfo.error == HeaderError.None
  for index in [-1, 3, high(int)]:
    # Invalid indices return reasons, never the first/default header.
    assert context.headerAt(index).error == AncestorContextError.InvalidIndex
    assert context.hashAt(index).error == AncestorContextError.InvalidIndex
  let bytes = context.serializedBytes
  limits.maxBytes = ByteLimit(bytes)
  assert captureAncestorContext(parent, [middle, oldest], limits).error == AncestorContextError.None
  limits.maxBytes = ByteLimit(bytes - 1)
  assert captureAncestorContext(parent, [middle, oldest], limits).error ==
      AncestorContextError.LimitExceeded
  limits.maxBytes = ByteLimit(high(uint64))
  limits.headers = ElementLimit(2)
  assert captureAncestorContext(parent, [middle, oldest], limits).error ==
      AncestorContextError.LimitExceeded
  limits.headers = ElementLimit(3)
  assert captureAncestorContext(parent, [oldest, middle], limits).error ==
      AncestorContextError.BrokenAncestry
  assert captureAncestorContext(parent, [middle, middle], limits).error ==
      AncestorContextError.BrokenAncestry
  assert captureAncestorContext(parent, [default(OwnedHeader)], limits).error ==
      AncestorContextError.InvalidHeader
  assert captureAncestorContext(default(OwnedHeader), [], limits).error ==
      AncestorContextError.InvalidHeader
  assert captureAncestorContext(parent, [], limits).value.len == 1
  limits.headers = ElementLimit(0)
  assert captureAncestorContext(parent, [], limits).error == AncestorContextError.LimitExceeded
  limits.headers = ElementLimit(3)
  let prefix = captureAncestorContext(parent, [], limits).value
  let extended = extendAncestorContext(prefix, [middle, oldest], limits)
  assert extended.error == AncestorContextError.None and extended.value.len == 3
  assert prefix.len == 1 # Publication creates a new immutable context, leaving all prior aliases intact.
  assert extended.value.serializedBytes == bytes
  assert extendAncestorContext(prefix, [oldest], limits).error ==
      AncestorContextError.BrokenAncestry
  assert extendAncestorContext(empty, [oldest], limits).error == AncestorContextError.Uninitialized
  assert extendAncestorContext(context, [oldest], limits).error ==
      AncestorContextError.LimitExceeded
  limits.maxBytes = ByteLimit(bytes - 1)
  assert extendAncestorContext(prefix, [middle, oldest], limits).error ==
      AncestorContextError.LimitExceeded
  assert extended.value.len == 3 and prefix.len == 1
  limits.header.maxBytes = ByteLimit(1)
  assert extendAncestorContext(context, [], limits).error == AncestorContextError.LimitExceeded
  echo "ancestor-context: ok"
main()
