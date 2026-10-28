# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Actual TLS fragments, framing/FIN failures, deadlines and callback retirement perform no decoding or state mutation.
import std/assertions
import std/syncio
import std/envvars
import ../../../src/app/ancestor_response as app_ancestor_response
import ../../../src/app/ancestor_receiver as app_ancestor_receiver
import ../../../src/chain/genesis as chain_genesis
import ../../../src/codec/bounded as codec_bounded
import ../../../src/codec/block_codec as codec_block_codec
import ../../../src/codec/report_owned as codec_report_owned
import ../../support/app_download_chain
import ../../support/app_candidate_context
import ../../support/app_ancestor_transport
import ../../support/app_block_download_transport
proc failHash(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Receiving bytes must never invoke block/header hashing from a native callback.
proc hashCalls(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Independent primitive observer proves hashing is deferred until explicit producer decoding.
proc main() {.raises.} =
  ## Authored two-child chain supplies independent first-parent identity and complete response bytes.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var input = newSeq[byte](raw.len)
  for index, octet in raw: input[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(input, 2).value, 2)
  let request = initAncestorRequest(context.heads[2].header, ElementLimit(1)).value
  var expected = default(array[42, byte])
  expected[0] = 128
  expected[1] = 37
  for index, octet in array[32, byte](context.heads[1].blockHash): expected[index + 5] = octet
  expected[37] = 1
  expected[38] = 1 # Independently literal descending-inclusive request and E4 maximum.
  let body = responseFrame(context.children[0])
  var receiver = default(AncestorReceiver)
  for mode in [Healthy, EmptyReply, Oversized, PrematureClose, NoFin, Deadline, ResetEvent]:
    # Every scenario crosses real TLS/native callbacks and teardown before producer inspection.
    let id = receiver.begin(request, ByteLimit(body.len)).value
    let wire = if mode == EmptyReply: @[0'u8, 0, 0, 0]
      elif mode == Oversized: @[255'u8, 255, 255, 255]
      else: body
    failHash(1)
    exchangeAncestors(receiver, id, expected, wire, mode, mode == EmptyReply)
    assert hashCalls() == 0 # Callback-only reception has not hashed or decoded a historical header.
    failHash(0)
    if mode in [Healthy, EmptyReply]:
      let decoded = receiver.response(id, preparationLimits().reporting.admission.frame, ByteLimit(100000))
      let wanted = if mode == Healthy: AncestorResponseError.None else: AncestorResponseError.Empty
      assert decoded.error == wanted
      assert receiver.cancel(id)
    elif mode in [Oversized, PrematureClose]:
      assert receiver.cancel(id) # Failed native responses retain only their selected framing reason.
    else:
      assert receiver.stage == AncestorReceiveStage.Idle
  echo "PASS application ancestor stream: real TLS, bounded callbacks, FIN gates and native retirement"
try:
  main() # TLS/backend/fixture errors remain native test failures.
except:
  quit(2)
