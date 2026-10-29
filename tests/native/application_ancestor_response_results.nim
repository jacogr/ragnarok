# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime contract witnesses use the same extractors for invalid and actual successful owners.
import std/[assertions, cmdline]
import ../../src/app/ancestor/response as ancestor_response
import ../../src/codec/[bounded, header, block_codec, tickets]

proc extract(outcome: AncestorResponseResult[AncestorRequest]) =
  ## Failed/default tagged outcomes cannot supply a request owner.
  discard outcome.value
proc reason(outcome: AncestorResponseResult[AncestorResponse]) =
  ## Only a selected block decoder failure carries its original reason.
  discard outcome.blockError
proc request(owner: AncestorRequest) =
  ## An uninitialized opaque request has no serializable wire authority.
  discard owner.requestBytes
proc main() =
  ## Genuine structural encoding supplies the positive request without forging private fields.
  case paramStr(1)
  of "default": extract(default(AncestorResponseResult[AncestorRequest])) # Default has no payload.
  of "refused": extract(initAncestorRequest(default(OwnedHeader), ElementLimit(
      1))) # Failed initialization has no payload.
  of "block": reason(default(AncestorResponseResult[AncestorResponse])) # Default has no block reason.
  of "request": request(default(AncestorRequest)) # Zero scalar values never become a request.
  else:
    var source = default(header.Header)
    source.unsigned.epoch = absentEpoch()
    source.unsigned.winners = absentWinners()
    source.unsigned.slot = HeaderSlot(1)
    let config = fullHeaderConfig(ByteLimit(1024))
    var wire = newSeq[byte](1024)
    let size = encodeHeader(source, config, wire)
    assert size.error == HeaderError.None
    wire.setLen(size.value)
    let child = decodeHeader(wire, config).value.owner
    let admitted = initAncestorRequest(child, ElementLimit(1))
    extract(admitted)
    request(admitted.value)
    var frame = default(FrameConfig)
    frame.cores = config.cores
    frame.validators = config.authorValidators
    frame.epochSlots = config.epochSlots
    frame.ticketLimit = TicketLimit(16)
    frame.maxBytes = ByteLimit(1024)
    let failed = decodeAncestorResponse(admitted.value, [0'u8], frame, ByteLimit(1), ByteLimit(1024))
    assert failed.error == AncestorResponseError.BlockFailure
    reason(failed)
main() # Contract violations must reach the native runtime, never a catch-all success path.
