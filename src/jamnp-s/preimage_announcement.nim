# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Fixed CE142 possession claims and bounded exact canonical outstanding-request checks.
## A parsed announcement is untrusted; successful lookup grants no blob or state-transition certificate.
import ./read_stream
import ../chain/[genesis, provider]
import ../codec/[bounded, composite]
import ../codec/state/[service_values, requests]
import ../state/preimages

type
  PreimageAnnouncement* = object ## Fixed copied wire facts contain no canonical owner or mutable input buffer.
    ready: bool
    service: ServiceIndex
    hash: ServicePreimageHash
    length: RequestLength
  AnnouncementResult* = object ## Only full exact decoding exposes a claim, never an input prefix.
    case status: ReadError
    of None: completed: PreimageAnnouncement
    else: discard              # Defaults/refusals have no fields to interpret.
func error*(outcome: AnnouncementResult): ReadError =
  ## Inspect parsing status before extracting untrusted fixed facts.
  outcome.status
func value*(outcome: AnnouncementResult): PreimageAnnouncement {.requires: outcome.status ==
    ReadError.None.} =
  ## Parsing alone confers neither service membership nor outstanding-request authority.
  outcome.completed
func valid*(notice: PreimageAnnouncement): bool =
  ## Defaults cannot enter followup queues.
  notice.ready
func service*(notice: PreimageAnnouncement): ServiceIndex {.requires: notice.ready.} =
  ## Return the announced service namespace as a nominal copied identity.
  notice.service
func hash*(notice: PreimageAnnouncement): ServicePreimageHash {.requires: notice.ready.} =
  ## Preserve the full requested content identity, not a truncated storage key.
  notice.hash
func length*(notice: PreimageAnnouncement): RequestLength {.requires: notice.ready.} =
  ## The announced exact byte length remains independently checked against fetched content.
  notice.length
func e4(input: openArray[byte], offset: int): uint32 {.requires: offset >= 0 and offset <=
    input.len and input.len-offset >= 4.} =
  ## Fixed extent precedes every byte access and widened shift.
  result = 0
  for index in 0..<4: result = result or (uint32(input[offset+index]) shl (index*8))
proc decodeAnnouncement*(payload: openArray[byte]): AnnouncementResult =
  ## Refuse reserved GP length namespaces and local retrieval ceilings before state access or allocation.
  if payload.len != 40: return AnnouncementResult(status: ReadError.InvalidRequest)
  let length = e4(payload, 36)
  if length >= high(uint32)-1: return AnnouncementResult(status: ReadError.InvalidRequest)
  if uint64(length) > uint64(MaxReadReplyBytes-4): return AnnouncementResult(
      status: ReadError.LimitExceeded)
  var identity = default(array[32, byte])
  for index in 0..<32: identity[index] = payload[4+index]
  AnnouncementResult(status: ReadError.None, completed: PreimageAnnouncement(ready: true,
    service: ServiceIndex(e4(payload, 0)), hash: ServicePreimageHash(identity),
        length: RequestLength(length)))
proc announcementRequest*(service: ServiceIndex, hash: ServicePreimageHash,
    length: RequestLength): AnnouncementResult =
  ## The same exact decoder validates locally constructed claims without accepting arbitrary namespace keys.
  var payload = default(array[40, byte])
  for index in 0..<4:
    payload[index] = byte((uint32(service) shr (index*8)) and 255)
    payload[36+index] = byte((uint32(length) shr (index*8)) and 255)
  let identity = array[32, byte](hash)
  for index in 0..<32: payload[4+index] = identity[index]
  decodeAnnouncement(payload)
proc request*(notice: PreimageAnnouncement): ReadRequest {.requires: notice.valid.} =
  ## Encode exactly the fixed payload; the outer route owns selector/E4/FIN.
  var payload = default(array[40, byte])
  for index in 0..<4:
    payload[index] = byte((uint32(notice.service) shr (index*8)) and 255)
    payload[36+index] = byte((uint32(notice.length) shr (index*8)) and 255)
  let identity = array[32, byte](notice.hash)
  for index in 0..<32: payload[4+index] = identity[index]
  decodeReadRequest(ReadKind.PreimageAnnouncement, payload).value
proc requested*(view: ChainView, notice: PreimageAnnouncement): ReadError =
  ## Reuse account existence, exact zero-slot history and current namespace semantics; no caller-selected key is trusted.
  if not notice.valid or view.fuzzOnly: return ReadError.InvalidRequest
  let head = view.bestBlock
  if head.error != GenesisError.None: return ReadError.Unavailable
  let checked = preimageRequested(head.value.stateSnapshot, notice.service, notice.hash, notice.length)
  case checked.error
  of PreimageTransitionError.None:
    if checked.value: ReadError.None else: ReadError.Unavailable
  of PreimageTransitionError.InvalidInput: ReadError.InvalidRequest
  of PreimageTransitionError.LimitExceeded: ReadError.LimitExceeded
  else: ReadError.BackendFailure # Malformed present account/history never becomes ordinary unavailability.
