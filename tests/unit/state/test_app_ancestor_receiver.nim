# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_ancestor_receiver_arc_release"}

## Every message split, two FIN orders, malformed framing and generation reuse preserve bounded exclusive ownership.
import std/assertions
import std/syncio
import std/envvars
import ../../../src/app/ancestor_response as app_ancestor_response
import ../../../src/app/ancestor_receiver as app_ancestor_receiver
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/header as codec_header
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/report_owned as codec_report_owned
import ../../support/app_download_chain
import ../../support/app_candidate_context
import ../../support/testing_arc_evidence

proc cycle(request: AncestorRequest, wire: seq[byte], config: FrameConfig) =
  ## The same receiver releases successful/failed buffers and retains only its monotonic scalar generation.
  var receiver = default(AncestorReceiver)
  let id = receiver.begin(request, ByteLimit(wire.len - 4)).value
  assert receiver.request(id).value == request.requestBytes
  assert receiver.append(id, wire, true) == AncestorReceiveError.None
  assert receiver.stage == AncestorReceiveStage.Receiving
  assert receiver.requestFinished(id) == AncestorReceiveError.None
  assert receiver.stage == AncestorReceiveStage.Ready
  let response = receiver.response(id, config, ByteLimit(100000))
  assert response.error == AncestorResponseError.None and response.value.headers.len == 1
  assert receiver.cancel(id)
  let next = receiver.begin(request, ByteLimit(wire.len - 5)).value
  assert not receiver.cancel(id)
  assert receiver.append(id, wire, true) == AncestorReceiveError.Stale
  assert receiver.stage == AncestorReceiveStage.Receiving
  assert receiver.append(next, wire, true) == AncestorReceiveError.LimitExceeded
  assert receiver.failure == AncestorReceiveError.LimitExceeded
  assert receiver.cancel(next)
  assert response.value.headers[0].headerInfo.error ==
      HeaderError.None # Producer owns immutable headers after receiver retirement.

proc main() {.raises.} =
  ## Authored/composed fixture supplies a real parent block and known child header.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var input = newSeq[byte](raw.len)
  for index, octet in raw: input[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(input, 2).value, 2)
  let config = preparationLimits().reporting.admission.frame
  let request = initAncestorRequest(context.heads[2].header, ElementLimit(1)).value
  let wire = responseFrame(context.children[0])
  for split in 0..wire.len:
    # Every proper header/body split preserves bytes and keeps Ready gated on both FIN observations.
    var receiver = default(AncestorReceiver)
    let id = receiver.begin(request, ByteLimit(wire.len - 4)).value
    assert receiver.requestFinished(id) == AncestorReceiveError.None
    assert receiver.append(id, wire.toOpenArray(0, split - 1), false) == AncestorReceiveError.None
    assert receiver.stage == AncestorReceiveStage.Receiving
    assert receiver.append(id, wire.toOpenArray(split, wire.high), true) ==
        AncestorReceiveError.None
    assert receiver.stage == AncestorReceiveStage.Ready
    assert receiver.response(id, config, ByteLimit(100000)).error == AncestorResponseError.None
    assert receiver.append(id, [0'u8], true) == AncestorReceiveError.Busy
    assert receiver.cancel(id)
  var receiver = default(AncestorReceiver)
  assert receiver.begin(default(AncestorRequest), ByteLimit(1)).error ==
      AncestorReceiveError.InvalidRequest
  assert receiver.begin(request, ByteLimit(high(uint64))).error ==
      AncestorReceiveError.InvalidPolicy
  let id = receiver.begin(request, ByteLimit(wire.len)).value
  assert receiver.begin(request, ByteLimit(1)).error == AncestorReceiveError.Busy
  for index, octet in wire:
    assert receiver.append(id, [octet], false) == AncestorReceiveError.None # Byte-at-a-time callbacks do no decoding or hashing.
  assert receiver.requestFinished(id) == AncestorReceiveError.None
  assert receiver.stage == AncestorReceiveStage.Receiving
  assert receiver.append(id, [], true) == AncestorReceiveError.None
  assert receiver.stage == AncestorReceiveStage.Ready
  assert receiver.cancel(id)
  for length in 0..<wire.len:
    let next = receiver.begin(request, ByteLimit(wire.len)).value
    assert receiver.append(next, wire.toOpenArray(0, length - 1), true) ==
        AncestorReceiveError.Truncated
    assert receiver.failure == AncestorReceiveError.Truncated
    assert receiver.cancel(next) # Every early header/body FIN retires its entire buffer.
  var extra = wire
  extra.add(0)
  let trailing = receiver.begin(request, ByteLimit(wire.len)).value
  assert receiver.append(trailing, extra, true) == AncestorReceiveError.Trailing
  assert receiver.cancel(trailing)
  let empty = receiver.begin(request, ByteLimit(0)).value
  assert receiver.requestFinished(empty) == AncestorReceiveError.None
  assert receiver.append(empty, [0'u8, 0, 0, 0], true) == AncestorReceiveError.None
  assert receiver.response(empty, config, ByteLimit(0)).error == AncestorResponseError.Empty
  assert receiver.cancel(empty)
  cycle(request, wire, config)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(request, wire, config) # Reuse and atomic refusal must not retain payloads or decoded owners.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("app_ancestor_receiver", 1000, before, after)
  echo "PASS application ancestor receiver: fragments, two FINs, atomic framing and stale generations"
try:
  main() # Backend/fixture exceptions remain actual native failures.
except:
  quit(2)
