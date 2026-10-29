# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Session order, unique request tickets, exact negotiation and every frame split are native boundary witnesses.
import std/[assertions, syncio]
import ../../support/fuzz_protocol_context
import ../../../src/state/fuzz/[protocol as fuzz_protocol, session as fuzz_session]
import ../../../src/state/store
import ../../../src/codec/bounded
import ../../../src/codec/state/trie as state_trie
proc peer(): FuzzPeer =
  ## The host explicitly advertises current GP and implemented features.
  FuzzPeer(protocol: 1, features: 3, jam: FuzzVersion(major: 0, minor: 8, patch: 0), name: "test")
proc readySession(): FuzzSession =
  ## Complete the real handshake but leave the required initialization pending.
  let limits = fuzzProtocolTestLimits()
  result = initFuzzSession(peer(), limits).value
  let hello = result.receive(newFuzzPeer(peer(), limits).value)
  assert hello.error == FuzzSessionError.None
  assert hello.value.kind == FuzzDispatchKind.Reply
  assert hello.value.reply.fuzzPeer.value.protocol == 1
proc initialization(): FuzzMessage =
  ## Independently authored Tiny header plus empty map and ancestry exercises the current layout.
  var wire = newSeq[byte](300)
  wire[0] = 1
  let decoded = decodeFuzzMessage(wire, fuzzProtocolTestLimits())
  assert decoded.error == FuzzError.None
  decoded.value
proc main() =
  ## No test backend fabricates STF success: these witnesses exercise only protocol scheduling and transport.
  let limits = fuzzProtocolTestLimits()
  let empty = decodeFuzzMessage(@[5'u8, 0], limits).value
  let root = newFuzzRoot(empty.fuzzState.value.commitment.root, limits).value
  let state = newFuzzState(empty.fuzzState.value, limits).value
  let error = newFuzzError("rejected", limits).value
  let absent = default(FuzzSessionResult[FuzzDispatch])
  assert absent.error == FuzzSessionError.Uninitialized
  assert default(FuzzRequest).requestMessage.error == FuzzSessionError.StaleRequest
  var missing = default(FuzzSession)
  assert missing.closed
  assert missing.receive(initialization()).error == FuzzSessionError.Closed
  var badPeer = peer()
  badPeer.protocol = 2
  assert initFuzzSession(badPeer, limits).error == FuzzSessionError.InvalidConfiguration
  badPeer = peer()
  badPeer.features = 4
  assert initFuzzSession(badPeer, limits).error == FuzzSessionError.InvalidConfiguration
  var session = initFuzzSession(peer(), limits).value
  assert session.receive(initialization()).error == FuzzSessionError.UnexpectedMessage
  assert session.closed
  for mismatch in 0..<4:
    var remote = peer()
    case mismatch
    of 0: remote.protocol = 2 # Fuzzer wire version is independently mandatory.
    of 1: remote.jam.major = 1 # Every JAM version component selects the exact profile.
    of 2: remote.jam.minor = 7
    else: remote.jam.patch = 1
    session = initFuzzSession(peer(), limits).value
    assert session.receive(newFuzzPeer(remote, limits).value).error ==
        FuzzSessionError.IncompatiblePeer
    assert session.closed
  var remote = peer()
  remote.features = 0x80000001'u32
  remote.app.patch = 99
  session = initFuzzSession(peer(), limits).value
  assert session.receive(newFuzzPeer(remote, limits).value).error == FuzzSessionError.None
  assert session.negotiatedFeatures == 1
  let init = session.receive(initialization()).value.request
  assert init.requestMessage.value.fuzzInfo.value.kind == FuzzKind.Initialize
  assert session.respond(init, root).error == FuzzSessionError.None
  assert session.respond(init, root).error == FuzzSessionError.StaleRequest
  assert session.closed # Reusing a completed request never grants a second response.
  session = readySession()
  let badInit = session.receive(initialization()).value.request
  assert session.respond(badInit, error).error == FuzzSessionError.InvalidResponse
  assert session.closed # Initialization failures are not consensus ImportBlock errors.
  session = readySession()
  let first = session.receive(initialization()).value.request
  var other = readySession()
  let second = other.receive(initialization()).value.request
  assert session.respond(second, root).error == FuzzSessionError.StaleRequest
  assert other.respond(first, root).error == FuzzSessionError.StaleRequest
  session = readySession()
  discard session.receive(initialization())
  assert session.receive(initialization()).error == FuzzSessionError.Busy
  session = readySession()
  let initialized = session.receive(initialization()).value.request
  assert session.respond(initialized, root).error == FuzzSessionError.None
  assert session.receive(initialization()).error == FuzzSessionError.UnexpectedMessage
  var importWire = newSeq[byte](305)
  importWire[0] = 3
  let body = decodeFuzzMessage(importWire, limits).value
  session = readySession()
  assert session.receive(body).error == FuzzSessionError.UnexpectedMessage
  session = readySession()
  assert session.respond(session.receive(initialization()).value.request, root).error ==
      FuzzSessionError.None
  let imported = session.receive(body).value.request
  assert session.respond(imported, error).error == FuzzSessionError.None
  assert not session.closed # A genuine consensus rejection permits the next block request.
  let retried = session.receive(body).value.request
  assert session.respond(retried, root).error == FuzzSessionError.None
  var lookupWire = newSeq[byte](33)
  lookupWire[0] = 4
  let lookup = decodeFuzzMessage(lookupWire, limits).value
  let query = session.receive(lookup).value.request
  assert session.respond(query, state).error == FuzzSessionError.None
  let wrongReply = session.receive(lookup).value.request
  assert session.respond(wrongReply, root).error == FuzzSessionError.InvalidResponse
  session = readySession()
  var withAncestry = newSeq[byte](336)
  withAncestry[0] = 1
  withAncestry[299] = 1
  var noFeatures = peer()
  noFeatures.features = 0
  session = initFuzzSession(noFeatures, limits).value
  assert session.receive(newFuzzPeer(peer(), limits).value).error == FuzzSessionError.None
  assert session.receive(decodeFuzzMessage(withAncestry, limits).value).error ==
      FuzzSessionError.UnexpectedMessage
  session = readySession()
  assert session.receive(decodeFuzzMessage(withAncestry, limits).value).error ==
      FuzzSessionError.None
  session.close()
  assert session.closed
  assert session.respond(default(FuzzRequest), root).error == FuzzSessionError.Closed
  let framed = newFuzzPeer(peer(), limits).value.encodeFuzzFrame(limits.bytes).value
  for split in 0..framed.len:
    var reader = initFuzzFrameReader(limits)
    let before = reader.feed(framed.toOpenArray(0, split-1))
    assert before.error == FuzzSessionError.None
    assert before.value.consumed == split
    if split == framed.len:
      assert before.value.complete # A fully delivered frame completes without an extra read.
    else:
      assert not before.value.complete # Every incomplete prefix retains no message owner.
      let after = reader.feed(framed.toOpenArray(split, framed.high))
      assert after.error == FuzzSessionError.None
      assert after.value.complete
      assert after.value.consumed == framed.len-split
      assert after.value.message.fuzzPeer.value.name == "test"
  var reader = initFuzzFrameReader(limits)
  for index in 0..<framed.len:
    let chunk = reader.feed(framed.toOpenArray(index, index))
    assert chunk.error == FuzzSessionError.None and chunk.value.consumed == 1
    assert chunk.value.complete == (index == framed.high) # Single-byte delivery includes partial prefix and payload.
  var joined = framed
  for item in framed: joined.add(item) # Concatenation retains a caller-owned unread second frame.
  let firstFrame = reader.feed(joined)
  assert firstFrame.value.complete and firstFrame.value.consumed == framed.len
  let secondFrame = reader.feed(joined.toOpenArray(framed.len, joined.high))
  assert secondFrame.value.complete and secondFrame.value.consumed == framed.len
  reader = initFuzzFrameReader(limits)
  assert reader.feed(@[0'u8, 0, 0, 0]).error == FuzzSessionError.LimitExceeded
  assert reader.feed(framed).error == FuzzSessionError.Closed
  reader = initFuzzFrameReader(limits)
  assert reader.feed(@[255'u8, 255, 255, 255]).error == FuzzSessionError.LimitExceeded
  reader = initFuzzFrameReader(limits)
  assert reader.feed(@[1'u8, 0, 0, 0, 6]).error == FuzzSessionError.InvalidMessage
  assert reader.feed(framed).error == FuzzSessionError.Closed
  var dormant = default(FuzzFrameReader)
  assert dormant.feed(framed).error == FuzzSessionError.Closed
  echo "PASS JAM fuzzer session: ordered tickets, negotiated profiles and bounded incremental frames"
main()
