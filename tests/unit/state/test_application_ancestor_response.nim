# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "application_ancestor_response_arc_release"}

## Genuine composed parents witness complete descending responses, quotas, linkage and immutable observations.
import std/[assertions, syncio, envvars]
import ../../../src/app/ancestor/response as ancestor_response
import ../../../src/chain/genesis
import ../../../src/codec/[bounded, header, block_codec, report_owned]
import ../../support/[application_download_chain, application_candidate_context, arc_evidence]

proc blockBytes(owner: OwnedBlock): seq[byte] =
  ## Serialize a complete independently authored block without CE message framing.
  result = newSeq[byte](owner.blockInfo.value.consumed)
  assert encodeOwnedBlock(owner, result).error == FrameError.None

proc cycle(request: AncestorRequest, payload: seq[byte], config: FrameConfig, bytes: uint64) =
  ## Repeated full success and late byte refusal must release all temporary blocks and headers.
  let decoded = decodeAncestorResponse(request, payload, config, ByteLimit(payload.len), ByteLimit(bytes))
  assert decoded.error == AncestorResponseError.None
  var changed = decoded.value.headers
  assert changed.len == 3
  changed[0] = default(OwnedHeader)
  assert decoded.value.headers[0].headerInfo.error == HeaderError.None
  let refused = decodeAncestorResponse(request, payload, config, ByteLimit(payload.len), ByteLimit(
      bytes - 1))
  assert refused.error == AncestorResponseError.LimitExceeded

proc main() {.raises.} =
  ## Independently execute four children once; acquisition itself performs no historical execution.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var input = newSeq[byte](raw.len)
  for index, octet in raw: input[index] = byte(octet)
  let context = chainFixture(decodeOwnedReport(input, 2).value, 4)
  let config = preparationLimits().reporting.admission.frame
  let child = context.heads[4].header
  let admitted = initAncestorRequest(child, ElementLimit(3))
  assert admitted.error == AncestorResponseError.None
  let request = admitted.value
  let wire = request.requestBytes
  assert wire[0] == 128 and wire[1] == 37
  for index in 2..<5: assert wire[index] == 0 # Literal fixed E4(37), never a compact integer.
  let expected = array[32, byte](context.heads[3].blockHash)
  for index, octet in expected: assert wire[index + 5] == octet
  assert wire[37] == 1 and wire[38] == 3
  for index in 39..<42: assert wire[index] == 0 # Descending inclusive, E4 maximum three.
  assert initAncestorRequest(child, ElementLimit(0)).error == AncestorResponseError.InvalidPolicy
  assert initAncestorRequest(child, ElementLimit(high(uint64))).error ==
      AncestorResponseError.InvalidPolicy
  assert initAncestorRequest(default(OwnedHeader), ElementLimit(1)).error ==
      AncestorResponseError.InvalidHeader
  let fullCount = initAncestorRequest(child, ElementLimit(uint64(high(uint32)))).value.requestBytes
  for index in 38..<42: assert fullCount[index] ==
      255 # Full wire count does not preallocate that many descriptors.
  var payload: seq[byte] = @[]
  var headerBytes = 0'u64
  for index in countdown(2, 0):
    for octet in blockBytes(context.children[index]): payload.add(octet)
    headerBytes += uint64(context.heads[index + 1].header.headerInfo.value.consumed)
  let decoded = decodeAncestorResponse(request, payload, config, ByteLimit(payload.len), ByteLimit(headerBytes))
  assert decoded.error == AncestorResponseError.None
  for index, owner in decoded.value.headers:
    var observed = newSeq[byte](owner.headerInfo.value.consumed)
    var expectedWire = newSeq[byte](observed.len)
    assert encodeOwnedHeader(owner, observed).error == HeaderError.None
    assert encodeOwnedHeader(context.heads[3 - index].header, expectedWire).error ==
        HeaderError.None
    assert observed == expectedWire # Exact sealed bytes survive response/block retirement.
  let short = blockBytes(context.children[2])
  assert decodeAncestorResponse(request, short, config, ByteLimit(short.len), ByteLimit(
      headerBytes)).error == AncestorResponseError.None
  assert decodeAncestorResponse(request, [], config, ByteLimit(0), ByteLimit(0)).error ==
      AncestorResponseError.Empty
  assert decodeAncestorResponse(default(AncestorRequest), payload, config, ByteLimit(high(uint64)),
      ByteLimit(high(uint64))).error == AncestorResponseError.Uninitialized
  assert decodeAncestorResponse(request, payload, config, ByteLimit(payload.len - 1), ByteLimit(
      headerBytes)).error == AncestorResponseError.LimitExceeded
  let narrow = initAncestorRequest(child, ElementLimit(2)).value
  assert decodeAncestorResponse(narrow, payload, config, ByteLimit(payload.len), ByteLimit(
      headerBytes)).error == AncestorResponseError.LimitExceeded
  var altered = payload
  altered[0] = altered[0] xor 1
  assert decodeAncestorResponse(request, altered, config, ByteLimit(altered.len), ByteLimit(
      headerBytes)).error == AncestorResponseError.BrokenAncestry
  altered = payload
  altered.setLen(altered.len - 1)
  let truncated = decodeAncestorResponse(request, altered, config, ByteLimit(altered.len),
      ByteLimit(headerBytes))
  assert truncated.error == AncestorResponseError.BlockFailure
  assert truncated.blockError.error != FrameError.None
  altered = payload
  altered.add(0)
  assert decodeAncestorResponse(request, altered, config, ByteLimit(altered.len), ByteLimit(
      headerBytes)).error == AncestorResponseError.LimitExceeded
  var duplicate = short
  for octet in short: duplicate.add(octet)
  let repeated = decodeAncestorResponse(request, duplicate, config, ByteLimit(duplicate.len),
      ByteLimit(headerBytes))
  assert repeated.error == AncestorResponseError.BrokenAncestry
  let wide = initAncestorRequest(child, ElementLimit(4)).value
  let suffixed = decodeAncestorResponse(wide, altered, config, ByteLimit(altered.len), ByteLimit(headerBytes))
  assert suffixed.error == AncestorResponseError.BlockFailure
  var sameSlot = newSeq[byte](child.headerInfo.value.consumed)
  assert encodeOwnedHeader(child, sameSlot).error == HeaderError.None
  sameSlot[96] = byte(uint32(context.heads[3].slot))
  let equal = initAncestorRequest(decodeHeader(sameSlot, preparationLimits(
    ).reporting.reports.ancestors.header).value.owner, ElementLimit(3)).value
  assert decodeAncestorResponse(equal, payload, config, ByteLimit(payload.len), ByteLimit(
      headerBytes)).error == AncestorResponseError.BrokenAncestry
  cycle(request, payload, config, headerBytes)
  let before = getOccupiedMem()
  for iteration in 0..<1000: cycle(request, payload, config,
      headerBytes) # Full and late failure retire every owner.
  let after = getOccupiedMem()
  assert before == after
  recordArcRelease("application_ancestor_response", 1000, before, after)
  echo "PASS application ancestor response: descending identity, complete blocks, atomic bounds and ownership"
try:
  main() # Genuine fixture/backend failures remain visible native failures.
except:
  quit(2)
