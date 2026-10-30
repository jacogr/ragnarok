# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The production dispatcher retires child connections before demand and resumes the original prepared input without another request.
import std/[assertions, envvars, syncio]
import std/posix/posix
import "../../../src/app/block/input" as block_input
import "../../../src/app/block/download" as block_download
import ../../../src/app/[candidate, chain, services, options]
import ../../../src/app/download/schedule as download_schedule
import "../../../src/jamnp-s/block/download/loop" as block_download_loop
import "../../../src/jamnp-s/block/download/peers" as block_download_peers
import "../../../src/jamnp-s/block/download/stream" as block_download_stream
import ../../../src/chain/provider
import ../../../src/codec/[bounded, report_owned, block_codec, header]
import ../../../src/state/report/anchors as report_anchors
import ../../support/[application_candidate_context, accumulation_completion_context, block_download_transport]
import ../../support/report_admission_context as report_context

proc pauseMicros(value: cuint): cint {.importc: "usleep", header: "<unistd.h>".}
  ## Yield only between bounded host turns, without accessing a leased ARC graph.
proc advance(dispatcher: var BlockDownloadLoop, servers: var DownloadResponders,
    target: DownloadLoopStage) =
  ## Fixed host time isolates stage barriers; a separate explicit deadline case verifies expiration.
  var reached = false
  for turn in 0..<8000:
    assert servers.poll()
    assert dispatcher.tick(DownloadLoopTick(0)) == DownloadLoopError.None
    if dispatcher.stage == target:
      reached = true
      break # Observe the exact stage before another turn may prepare or adopt.
    if dispatcher.stage in [DownloadLoopStage.Preparing, DownloadLoopStage.Cancelling]:
      discard pauseMicros(1000) # Only synchronized scalar dispatcher state is inspected while work runs.
  assert reached, "dispatcher did not reach ancestor stage"
proc scenario(context: SeedFixture, frame: seq[byte], older: seq[OwnedHeader], key: DownloadPeerKey,
    expire: bool) {.raises.} =
  ## Native sockets, worker leases and canonical Services all retain stable addresses through explicit shutdown.
  var options = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", "dispatch-ancestor-seed",
    "--state-write-bytes", "1000000"], options)
  var owner = default(Services)
  assert owner.start(options, "dispatch ancestors")
  defer: owner.close()
  let limits = DownloadLoopLimits(schedule: DownloadScheduleLimits(peers: ElementLimit(1),
      attempts: 1,
    retryDelay: DownloadRetryDelay(1)), input: BlockInputLimits(blockBytes: ByteLimit(100000),
        ancestorBytes: ByteLimit(8192),
      ancestors: ElementLimit(1), discoverAncestors: true), candidate: preparationLimits(),
          composition: completionLimits().composition,
    stream: DownloadStreamLimits(readBytes: ByteLimit(4096), writeBytes: ByteLimit(42),
        timeout: DownloadTimeout(20000)),
    attemptTimeout: DownloadAttemptTimeout(20000))
  var preflight = default(BlockDownload)
  let admitted = preflight.begin(owner, [], limits.input, limits.candidate).value
  let expected = preflight.request(admitted).value
  assert preflight.cancel(admitted)
  var servers = default(DownloadResponders)
  assert servers.openResponders(expected, frame)
  defer: servers.close()
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close() # Joins execution and native borrowers before the outer Services aliases retire.
  assert dispatcher.configure(owner, [DownloadPeerId(1)], [], limits, DownloadLoopTick(0)) ==
      DownloadLoopError.None
  assert dispatcher.openPeer(DownloadPeerId(1), key, servers.port(false), getEnv(
      "RAGNAROK_TEST_CERT"),
    getEnv("RAGNAROK_TEST_KEY"), "jamnp-s/1/00000000") == DownloadPeerError.None
  advance(dispatcher, servers, DownloadLoopStage.AwaitingAncestors)
  assert not owner.preparationActive and owner.preparationAvailable
  assert dispatcher.readyPeers.len == 0
  assert dispatcher.ancestorDemand.value.missingLookups.value == 1
  assert dispatcher.ancestorRemaining(DownloadLoopTick(19999)) == 1
  assert dispatcher.ancestorRemaining(DownloadLoopTick(20000)) == 0
  assert servers.requestCount(false) == 1 and owner.chainView.retainedCount == 1
  if expire:
    assert dispatcher.resumeAncestors(older, DownloadLoopTick(20000)) ==
        DownloadLoopError.AttemptExpired
    assert dispatcher.stage == DownloadLoopStage.Failed and owner.chainView.retainedCount == 1
    return
  assert dispatcher.resumeAncestors([older[0], older[0]], DownloadLoopTick(0)) ==
      DownloadLoopError.SessionFailure
  assert dispatcher.stage == DownloadLoopStage.AwaitingAncestors
  assert dispatcher.resumeAncestors(older, DownloadLoopTick(0)) == DownloadLoopError.None
  assert dispatcher.stage == DownloadLoopStage.Receiving and not owner.preparationActive
  advance(dispatcher, servers, DownloadLoopStage.Queued)
  assert owner.chainView.retainedCount == 1 # Queuing a genuine certificate is still separate from adoption.
  advance(dispatcher, servers, DownloadLoopStage.Adopted)
  assert dispatcher.adoption.error == ApplicationChainError.None and
      owner.chainView.retainedCount == 2
  assert servers.requestCount(false) == 1 # The original signed child was neither fetched nor prepared from bytes again.
proc main() {.raises.} =
  ## Independently author a signed guaranteed child and retain its exact historical lookup header.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var source = newSeq[byte](raw.len)
  for index, octet in raw: source[index] = byte(octet) # Frozen report fixture supplies genuine credential inputs.
  let base = decodeOwnedReport(source, 2).value
  let context = fixture(base, guarantees = 1)
  writeFile("dispatch-ancestor-seed", context.text)
  defer: discard posix.unlink("dispatch-ancestor-seed")
  let blockOwner = candidateBlock(context)
  let size = blockOwner.blockInfo.value.consumed
  assert size < 100000
  var frame = newSeq[byte](size + 4)
  for index in 0..<4: frame[index] = byte((uint32(size) shr (index * 8)) and
      255) # Literal CE E4 extent, independent of receiver internals.
  assert encodeOwnedBlock(blockOwner, frame.toOpenArray(4, frame.high)).error == FrameError.None
  let rawKey = readFile(getEnv("RAGNAROK_TEST_PEER_A"))
  assert rawKey.len == 32
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = byte(rawKey[index]) # Exact pinned test public identity.
  let older = report_context.authored(base).older
  scenario(context, frame, older, DownloadPeerKey(key), false)
  scenario(context, frame, older, DownloadPeerKey(key), true)
  echo "dispatch-ancestors: ok"
try:
  main() # Fixture IO failure must fail the supported native runner.
except:
  quit(2)
