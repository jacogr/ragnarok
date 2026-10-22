# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded CE 128 descending-inclusive requests and complete response validation.
## Captured headers provide parent-linked context only; no execution, trust or canonical publication occurs.
import std/assertions
import ../codec/[bounded, header, block_codec]
import ../crypto/primitives

type
  AncestorResponseError* {.pure.} = enum ## Refusal retains no decoded prefix or usable request.
    Uninitialized, None, InvalidHeader, InvalidPolicy, LimitExceeded, Empty,
    BlockFailure, BrokenAncestry, BackendFailure
  AncestorRequest* = object ## An immutable selected child binds the requested first parent, slot and maximum.
    initialized: bool
    first: HeaderParent
    childSlot: HeaderSlot
    maximum: uint32
  AncestorResponseData = ref object ## Only immutable sealed headers survive full response validation.
    captured: seq[OwnedHeader]
  AncestorResponse* = object ## Copies share immutable validated context, never mutable sequence storage.
    data: nil AncestorResponseData
  AncestorResponseResult*[T] = object ## Failed/default results have only typed reasons; access requires success.
    case status: AncestorResponseError
    of None:
      completed: T
    of BlockFailure:
      blockReason: FrameResult[BlockRead]
    else:
      discard # No successful prefix survives a late codec, quota or linkage failure.

func error*[T](outcome: AncestorResponseResult[T]): AncestorResponseError =
  ## Inspect the selected success/refusal without exposing its discriminator.
  outcome.status
func value*[T](outcome: AncestorResponseResult[T]): T {.inline, requires:
    outcome.status == AncestorResponseError.None.} =
  ## Extract only the successfully constructed immutable request or response owner.
  outcome.completed
func blockError*[T](outcome: AncestorResponseResult[T]): FrameResult[BlockRead] {.inline,
    requires: outcome.status == AncestorResponseError.BlockFailure.} =
  ## Preserve the complete existing block decoder failure, including its selected component cause.
  outcome.blockReason
proc headers*(response: AncestorResponse): seq[OwnedHeader] =
  ## Return independent sequence storage; default owners expose no context.
  let data = response.data
  if data == nil: return @[] # A default cannot invent a successful response or header.
  result = newSeq[OwnedHeader](data.captured.len)
  for index in 0..<data.captured.len:
    result[index] = data.captured[index] # Replacing an observed element cannot mutate the retained response.

proc initAncestorRequest*(child: OwnedHeader, maximum: ElementLimit): AncestorResponseResult[
    AncestorRequest] =
  ## Request the known child's parent inclusively; reject zero/non-wire-sized counts before narrowing.
  if uint64(maximum) == 0 or uint64(maximum) > uint64(high(uint32)):
    return AncestorResponseResult[AncestorRequest](status: AncestorResponseError.InvalidPolicy)
  let info = child.headerInfo
  if info.error != HeaderError.None:
    return AncestorResponseResult[AncestorRequest](status: AncestorResponseError.InvalidHeader)
  AncestorResponseResult[AncestorRequest](status: AncestorResponseError.None,
    completed: AncestorRequest(initialized: true, first: info.value.unsigned.parent,
      childSlot: info.value.unsigned.slot, maximum: uint32(uint64(maximum))))

func valid*(request: AncestorRequest): bool =
  ## Distinguish a successfully bound request from a default without extracting wire bytes.
  request.initialized

func requestBytes*(request: AncestorRequest): array[42, byte] {.requires: request.initialized.} =
  ## Literal stream kind, E4(37), parent hash, descending-inclusive direction and E4(maximum).
  result = default(array[42, byte])
  result[0] = 128
  result[1] = 37
  let first = array[32, byte](request.first)
  for index, octet in first: result[index + 5] = octet # Hash has no count prefix or terminator.
  result[37] = 1
  for index in 0..<4:
    result[index + 38] = byte((request.maximum shr (index * 8)) and 255) # Fixed E4 is little endian.

proc decodeAncestorResponse*(request: AncestorRequest, payload: openArray[byte],
    frame: FrameConfig, maxBytes, headerBytes: ByteLimit): AncestorResponseResult[
        AncestorResponse] =
  ## Decode the uncounted sequence through EOF, checking each exact sealed identity against its child.
  if not request.initialized:
    return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.Uninitialized)
  if uint64(payload.len) > uint64(maxBytes):
    return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.LimitExceeded)
  if payload.len == 0:
    return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.Empty)
  var remaining = uint64(headerBytes)
  var expected = array[32, byte](request.first)
  var childSlot = uint32(request.childSlot)
  var offset = 0
  var captured: seq[OwnedHeader] = @[]
  while offset < payload.len:
    # Check descriptor count/extent before decoding or appending any additional attacker-supplied block.
    if uint64(captured.len) >= uint64(request.maximum) or captured.len >= high(int) div sizeof(OwnedHeader):
      return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.LimitExceeded)
    let decoded = decodeBlock(payload.toOpenArray(offset, payload.high), frame)
    if decoded.error != FrameError.None:
      return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.BlockFailure,
        blockReason: decoded)
    let consumed = decoded.value.consumed
    assert consumed > 0 and consumed <= payload.len -
        offset # Successful codec extents stay inside the supplied view.
    let component = decoded.value.owner.blockHeader.value
    let owner = component.readHeader.value.owner
    let info = owner.headerInfo.value
    if uint64(info.consumed) > remaining:
      return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.LimitExceeded)
    let digest = blake2b256(payload.toOpenArray(offset, offset + info.consumed - 1))
    if digest.error != CryptoError.None:
      return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.BackendFailure)
    if array[32, byte](digest.value) != expected or uint32(info.unsigned.slot) >= childSlot:
      return AncestorResponseResult[AncestorResponse](status: AncestorResponseError.BrokenAncestry)
    remaining -= uint64(info.consumed) # Success proves safe subtraction from the independent retained-header budget.
    expected = array[32, byte](info.unsigned.parent)
    childSlot = uint32(info.unsigned.slot)
    captured.add(owner)
    offset += consumed # The decoder's checked consumed extent proves this addition stays within payload.
  AncestorResponseResult[AncestorResponse](status: AncestorResponseError.None,
    completed: AncestorResponse(data: AncestorResponseData(captured: captured)))
