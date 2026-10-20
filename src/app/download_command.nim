# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded one-child command owns canonical Services and stable download callbacks through explicit teardown.
## Startup accepts only explicit state/stage policies and a bounded pinned loopback peer list; no fixture or process-global inputs.

import std/[syncio, monotimes, times]
import std/posix/posix
import ./[options, services, download_policy, block_download]
import ./download_schedule
import ../quic/[block_download_loop, block_download_peers]

type DownloadCommandResult* {.pure.} = enum ## Process-level refusal never implies a prepared or adopted successor.
  Uninitialized, Adopted, InvalidOptions, InvalidEndpoint, InvalidIdentity, InvalidPolicy,
  StartupFailure, AdmissionFailure, TransportFailure, DispatchFailure, Exhausted, Timeout

proc number(text: string, maximum: uint64): uint64 =
  ## Positive canonical decimal parsing proves arithmetic/conversion bounds before native setup.
  if text.len == 0 or text.len > 20 or text[0] == '0': return 0
  var value = 0'u64
  for character in text:
    if character notin {'0'..'9'}: return 0 # No sign, exponent, whitespace or unknown command mode becomes an endpoint.
    let digit = uint64(ord(character) - ord('0'))
    if value > (maximum - digit) div 10: return 0 # maximum >=9 for both callers, proving subtraction too.
    value = value * 10 + digit
  value

proc identity(path: string, expected: var DownloadPeerKey): bool {.raises.} =
  ## A public identity file must be exactly 32 bytes, including detection of concurrent file growth.
  expected = default(DownloadPeerKey)
  var file: File = nil
  if path.len == 0 or not open(file, path, fmRead): return false
  defer: close(file) # No native certificate callback borrows file storage.
  var bytes = default(array[33, byte])
  if readBuffer(file, addr bytes[0], bytes.len) != 32: return false
  var key = default(array[32, byte])
  for index in 0..<32: key[index] = bytes[index] # Copy only the exact proven public key payload.
  expected = DownloadPeerKey(key)
  true

proc runDownload*(options: Options): DownloadCommandResult {.raises.} =
  ## Open at most sixteen endpoints; timeout/exhaustion/failure returns only after all callbacks and Services retire.
  if not options.valid or options.argumentCount < 8 or
      options.argumentCount > 38 or (options.argumentCount - 8) mod 2 != 0 or options.argument(1) !=
          "download" or
      not options.stateEnabled or options.telemetryEnabled:
    return DownloadCommandResult.InvalidOptions # This command cannot silently discard requested outgoing telemetry.
  let timeout = number(options.argument(7), 120000)
  if timeout == 0: return DownloadCommandResult.InvalidEndpoint
  let policy = loadDownloadPolicy(options.argument(8))
  if policy.error != DownloadPolicyError.None: return DownloadCommandResult.InvalidPolicy
  let limits = policy.value
  let count = 1 + (options.argumentCount - 8) div 2
  if uint64(count) > uint64(limits.schedule.peers): return DownloadCommandResult.InvalidPolicy
  var ports = default(array[16, uint16])
  var keys = default(array[16, DownloadPeerKey])
  var peers: seq[DownloadPeerId] = @[]
  for index in 0..<count:
    # The original tuple supplies credentials shared by every additional PORT PEER pair.
    let portArgument = if index == 0: 2 else: 9 + (index - 1) * 2
    let peerArgument = if index == 0: 5 else: portArgument + 1
    let port = number(options.argument(portArgument), 65535)
    if port == 0: return DownloadCommandResult.InvalidEndpoint
    ports[index] = uint16(port)
    if not identity(options.argument(peerArgument), keys[index]):
      return DownloadCommandResult.InvalidIdentity # No listener starts after a partially validated list.
    for previous in 0..<index:
      if keys[previous] == keys[index]: return DownloadCommandResult.InvalidIdentity # Aliases cannot multiply scheduler weight.
      if ports[previous] == ports[index]: return DownloadCommandResult.InvalidEndpoint # One loopback endpoint has one configured principal.
    peers.add(DownloadPeerId(uint64(index + 1))) # The shape cap proves IDs 1..16 and all argument arithmetic.
  var owner = default(Services)
  defer: owner.close() # Dispatcher teardown below must end every Services borrow first.
  if not owner.start(options, "download"): return DownloadCommandResult.StartupFailure
  var preflight = default(BlockDownload)
  let admitted = preflight.begin(owner, [], limits.input, limits.candidate)
  if admitted.error != BlockDownloadError.None: return DownloadCommandResult.AdmissionFailure
  discard preflight.cancel(admitted.value) # Exact raw admission is checked before any outgoing TLS engine opens.
  var dispatcher = default(BlockDownloadLoop)
  defer: dispatcher.close() # Stable stack owner remains alive during native close callbacks on every exit.
  if dispatcher.configure(owner, peers, [], limits, DownloadLoopTick(0)) !=
      DownloadLoopError.None: return DownloadCommandResult.InvalidPolicy
  for index in 0..<count:
    if dispatcher.openPeer(peers[index], keys[index], ports[index], options.argument(3),
        options.argument(4), options.argument(6)) != DownloadPeerError.None:
      return DownloadCommandResult.TransportFailure # Deferred close retires all earlier opened endpoints too.
  let started = getMonoTime()
  while true:
    let elapsed = (getMonoTime() - started).inMilliseconds
    if elapsed < 0: return DownloadCommandResult.DispatchFailure # Do not narrow a broken host clock into a huge deadline.
    if uint64(elapsed) >= timeout: return DownloadCommandResult.Timeout
    if dispatcher.tick(DownloadLoopTick(uint64(elapsed))) != DownloadLoopError.None:
      return DownloadCommandResult.DispatchFailure
    case dispatcher.stage
    of DownloadLoopStage.Adopted: return DownloadCommandResult.Adopted # Only an actual consumed Services success reaches this alternative.
    of DownloadLoopStage.Exhausted: return DownloadCommandResult.Exhausted
    of DownloadLoopStage.Failed: return DownloadCommandResult.DispatchFailure
    else: discard # Waiting/receiving/queued work requires a later bounded dispatcher turn.
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # One bounded host pause avoids spinning; all native endpoint polls remain nonblocking.
