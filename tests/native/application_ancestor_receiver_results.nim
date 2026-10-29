# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime guards retain actual complete empty-response and framing-failure positive controls.
import std/[assertions, cmdline]
import ../../src/app/ancestor/[response as ancestor_response, receiver as ancestor_receiver]
import ../../src/codec/[bounded, header, block_codec]

proc extract(outcome: AncestorReceiveResult[AncestorReceiveId]) =
  ## A failed/default begin result has no generation.
  discard outcome.value
proc response(receiver: AncestorReceiver, id: AncestorReceiveId) =
  ## Default, receiving or cancelled owners cannot expose response bytes to the decoder.
  discard receiver.response(id, default(FrameConfig), ByteLimit(0))
proc observeFailure(receiver: AncestorReceiver) =
  ## Only a terminal framing failure retains a selected reason.
  discard receiver.failure
proc main() =
  ## Same helper calls exercise each refusal and its actual successful alternative.
  var receiver = default(AncestorReceiver)
  case paramStr(1)
  of "default": extract(default(AncestorReceiveResult[AncestorReceiveId])) # No default generation.
  of "response": response(receiver, AncestorReceiveId(0)) # No default completed response.
  of "failure": observeFailure(receiver) # Idle carries no terminal framing reason.
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
    let request = initAncestorRequest(decodeHeader(wire, config).value.owner, ElementLimit(1)).value
    let admitted = receiver.begin(request, ByteLimit(0))
    extract(admitted)
    let id = admitted.value
    if paramStr(1) == "receiving": response(receiver, id) # Real generation still requires both FINs.
    else:
      assert receiver.requestFinished(id) == AncestorReceiveError.None
      assert receiver.append(id, [0'u8, 0, 0, 0], true) == AncestorReceiveError.None
      response(receiver, id)
      assert receiver.cancel(id)
      if paramStr(1) == "cancelled": response(receiver, id) # Retired generation never retains raw bytes.
      else:
        let failed = receiver.begin(request, ByteLimit(0)).value
        assert receiver.append(failed, [], true) == AncestorReceiveError.Truncated
        observeFailure(receiver)
        assert receiver.cancel(failed)
main() # Runtime contracts must fail natively, without a catch-all success path.
