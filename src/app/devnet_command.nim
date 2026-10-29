# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Bounded Tiny validator process: native authoring, ordinary GP candidate admission, canonical
## CE128 serving/polling and durable replay of validated blocks. No finality or fork choice is claimed.

import ../lib/logging
import ./node_logging

import std/[os, strutils, times, monotimes, syncio]
import ../pvm/backend
import ./[chain, candidate, block_author, tiny_genesis, current_download_policy]
import ../chain/[genesis, provider, parameters]
import ../codec/[bounded, header, block_codec]
import ../state/[store, checkpoint, accumulation_current_update, block_transition, safrole_transition]
import ../bandersnatch/bandersnatch
import ../crypto/[primitives, validator_keys]
import ../quic/[devnet, protocol]
import ../lib/atomic_file

proc number(text: string, maximum: uint64, output: var uint64): bool =
  ## Canonical bounded decimal is parsed before any multiplication, narrowing or time arithmetic.
  output = 0
  if text.len == 0 or text.len > 20 or (text.len > 1 and text[0] == '0'): return false
  for character in text:
    if character notin {'0'..'9'}: return false
    let digit = uint64(ord(character)-ord('0'))
    if digit > maximum or output > (maximum-digit) div 10: return false
    output = output*10+digit
  true
proc bytes(text: string): seq[byte] =
  ## Exact UTF8 configuration/diagnostic bytes pass unchanged to atomic publication.
  result = newSeq[byte](text.len)
  for index, character in text: result[index] = byte(character)
proc text(bytes: seq[byte]): string =
  ## Bounded regular-file input remains owned throughout strict chain configuration decoding.
  result = newString(bytes.len)
  for index, octet in bytes: result[index] = char(octet)
proc nowMs(): uint64 =
  ## The development clock uses a common explicit Unix origin with real six-second GP slots.
  let current = getTime()
  uint64(current.toUnix)*1000+uint64(current.nanosecond div 1000000)
proc diagnostic(outcome: CurrentCandidateResult): string =
  ## Stage-specific causes remain visible without extracting any rejected partial state.
  result = $outcome.error
  if outcome.error == CurrentCandidateError.PrefixFailure:
    let prefix = outcome.prefixFailure
    result.add("/" & $prefix.error)
    if prefix.error == ApplicationCandidateError.BlockFailure:
      result.add("/" & $prefix.blockFailure.error)
      if prefix.blockFailure.error == BlockTransitionError.SafroleFailure:
        result.add("/" & $prefix.blockFailure.safroleError.error)
  elif outcome.error == CurrentCandidateError.CompletionFailure:
    result.add("/" & $outcome.completionFailure.error) # Completion refusal is distinct from a malformed seal.

proc admit(chain: var ApplicationChain, raw: seq[byte], limits: CurrentCandidateLimits,
    journal: var seq[byte], path: string, durable: bool, logging: LogWriter): bool =
  ## Prepare through the ordinary complete-state path; only durable journal publication authorizes installation.
  let parsed = decodeBlock(raw, limits.reporting.admission.frame)
  if parsed.error != block_codec.FrameError.None or parsed.value.consumed != raw.len:
    log(logging, LogTarget.Application, LogLevel.Warn, "Block rejected: invalid encoding")
    stderr.writeLine("DEVNET_REFUSED decode")
    return false
  let prepared = prepareCurrentCandidate(chain, parsed.value.owner, [], limits)
  if prepared.error != CurrentCandidateError.None:
    log(logging, LogTarget.Application, LogLevel.Warn, "Block rejected: " & diagnostic(prepared))
    stderr.writeLine("DEVNET_REFUSED " & diagnostic(prepared))
    return false # Failed validation leaves the parent, journal and network catalog unchanged.
  if not chain.canInstallPrepared(prepared.value): return false
  if durable:
    if raw.len == 0 or raw.len > 65536 or journal.len > 64*(65536+4)-raw.len-4: return false
    var next = journal
    for index in 0..<4: next.add(byte((uint64(raw.len) shr (8*index)) and 255))
    for octet in raw: next.add(octet)
    if replaceAtomicFile(path, next, ByteLimit(64*(65536+4))) != AtomicFileError.None:
      stderr.writeLine("DEVNET_STORAGE_FAILED")
      return false # Visible-but-unsynced publication stops authoring rather than pretending durability.
    journal = next
  chain.installPrepared(prepared.value)
  log(logging, LogTarget.Application, LogLevel.Info, "Imported block, " & chain.describeHead)
  true
proc observation(chain: ApplicationChain, folder: string, index: int, source: string): bool =
  ## Complete checkpoints are observations, while the validated block journal remains restart authority.
  let parent = chain.chainView.bestBlock.value
  let checkpoint = encodeFullCheckpoint(parent.stateSnapshot, ByteLimit(1048576))
  if checkpoint.error != CheckpointError.None: return false
  if replaceAtomicFile(folder/"state.bin", checkpoint.value, ByteLimit(1048576)) !=
      AtomicFileError.None:
    return false
  if replaceAtomicFile(folder/("state-" & $parent.slot & ".bin"), checkpoint.value, ByteLimit(
      1048576)) != AtomicFileError.None:
    return false # Bounded per-height observations permit whole-map conformance checks independently of final convergence.
  let hash = hex(array[32, byte](parent.blockHash))
  let root = hex(array[32, byte](parent.stateSnapshot.commitment.root))
  let value = "{\"slot\":" & $parent.slot & ",\"hash\":\"" & hash & "\",\"root\":\"" & root & "\"}\n"
  if replaceAtomicFile(folder/"head.json", bytes(value), ByteLimit(1024)) != AtomicFileError.None:
    return false
  stdout.writeLine("DEVNET_BLOCK node=" & $index & " source=" & source & " slot=" & $parent.slot &
    " hash=" & hash & " root=" & root)
  flushFile(stdout)
  true

proc node(arguments: openArray[string], logging: LogWriter, selected: PvmBackend): int {.raises.} =
  ## One native process owns one public development signer, an independent complete chain and two QUIC engines.
  if arguments.len != 8: return 2
  var index, base, start, stop = 0'u64
  if not number(arguments[3], 5, index) or not number(arguments[4], 65530, base) or base < 1024 or
      not number(arguments[5], 4102444800000'u64, start) or not number(arguments[6], 64, stop) or
          stop < 2:
    return 2 # Ports, validator ordinal, finite horizon and Unix origin are admitted before allocation.
  let folder = arguments[2]/("node-" & $index)
  let certificate = folder/"cert.pem"
  let keyFile = folder/"key.pem"
  let journalPath = folder/"blocks.bin"
  let genesisInput = readBoundedFile(arguments[2]/"chain.json", ByteLimit(1048576))
  let policy = loadCurrentDownloadPolicy(arguments[7])
  if genesisInput.error != AtomicFileError.None or policy.error != CurrentDownloadPolicyError.None:
    stderr.writeLine("DEVNET_START_FAILED configuration")
    return 2
  var limits = policy.value.candidate
  limits.selectLogging(logging)
  limits.selectPvmBackend(selected)
  var storeLimits = genesisStoreLimits()
  storeLimits.writes = ElementLimit(1000)
  storeLimits.writeValueBytes = ByteLimit(1048576)
  let initial = initApplicationChain(text(genesisInput.value), storeLimits)
  if initial.error != ApplicationChainError.None: return 2
  var chain = initial.value
  let parameters = chain.chainView.bestBlock.value.chainParameters
  if parameters.get(coreCount) != 2 or parameters.get(epochPeriod) != 12 or
      parameters.get(slotPeriodSec) != 6 or parameters.get(epochTailStart) != 10:
    stderr.writeLine("DEVNET_START_FAILED profile")
    return 2 # The Tiny command never converts a supplied foreign profile or shortens slot time.
  let secret = tinySigningKey(int(index))
  if secret.error != BsError.None: return 2
  var peers = default(array[6, array[32, byte]])
  for ordinal in 0..<6:
    let public = tinyPeerKey(ordinal)
    if public.error != CryptoError.None: return 2
    peers[ordinal] = array[32, byte](public.value)
  let alpn = "jamnp-s/1/" & hex(array[32, byte](chain.chainView.bestBlock.value.blockHash))[0..7]
  var network = DevnetNetwork()
  defer: network.close() # Every startup/runtime failure retires callback owners before stack destruction.
  var journal: seq[byte] = @[]
  if fileExists(journalPath):
    let loaded = readBoundedFile(journalPath, ByteLimit(64*(65536+4)))
    if loaded.error != AtomicFileError.None: return 2
    journal = loaded.value
    var cursor = 0
    var records = 0
    while cursor < journal.len:
      if journal.len-cursor < 4 or records >= 64: return 2
      var count = 0'u64
      for octet in 0..<4: count = count or (uint64(journal[cursor+octet]) shl (8*octet))
      cursor += 4
      if count == 0 or count > 65536 or count > uint64(journal.len-cursor): return 2
      var raw = newSeq[byte](int(count))
      for octet in 0..<raw.len: raw[octet] = journal[cursor+octet]
      let parent = array[32, byte](chain.chainView.bestBlock.value.blockHash)
      if not admit(chain, raw, limits, journal, journalPath, false, logging) or not network.publish(
          parent, raw):
        return 2 # Replaying a journal always reruns GP checks; no trusted successor map is loaded.
      cursor += raw.len
      inc records
  if not observation(chain, folder, int(index), "replay"): return 2
  if chain.chainView.bestBlock.value.slot > uint32(stop): return 2
  if not network.open(uint16(base+index), certificate, keyFile, alpn, peers):
    stderr.writeLine("DEVNET_START_FAILED transport")
    return 2
  logRuntimeIdentity(logging)
  log(logging, LogTarget.Startup, LogLevel.Info, "Role: development AUTHORITY; validator=" & $index)
  log(logging, LogTarget.Storage, LogLevel.Info, "Block journal: " & journalPath)
  log(logging, LogTarget.Network, LogLevel.Info, "Development QUIC listener: [::1]:" & $(base+index))
  stdout.writeLine("DEVNET_READY node=" & $index)
  flushFile(stdout)
  let deadline = start+stop*6000+15000
  var pending = false
  var peer = int((index+1) mod 6)
  var attemptedSlot = 0'u32
  var dialedAt = getMonoTime()
  var nextDial = getMonoTime()
  while nowMs() < deadline and not fileExists(arguments[2]/"STOP"):
    if not network.poll(): return 2
    let now = nowMs()
    let head = chain.chainView.bestBlock.value
    let slot = if now < start: 0'u64 else: min(stop, (now-start) div 6000+1)
    if slot > uint64(head.slot) and uint32(slot) != attemptedSlot:
      attemptedSlot = uint32(slot)
      let authored = authorEmptyBlock(head, HeaderSlot(uint32(slot)), secret.value,
        limits.reporting.admission.frame, limits.reporting.safrole)
      if authored.error == BlockAuthorError.None:
        log(logging, LogTarget.Application, LogLevel.Info, "Authored development block at slot " & $slot)
        var raw = newSeq[byte](65536)
        let encoded = encodeOwnedBlock(authored.value, raw)
        if encoded.error != block_codec.FrameError.None: return 2
        raw.setLen(encoded.value)
        if not admit(chain, raw, limits, journal, journalPath, true, logging) or
            not network.publish(array[32, byte](head.blockHash), raw) or
            not observation(chain, folder, int(index), "local"): return 2
      elif authored.error != BlockAuthorError.NotEligible:
        stderr.writeLine("DEVNET_AUTHOR_FAILED " & $authored.error)
        return 2 # Unsupported schedules and actual failures never become silently skipped successes.
    if pending and (network.finished or (getMonoTime()-dialedAt).inMilliseconds >= 800):
      var raw: seq[byte] = @[]
      let received = network.take(raw)
      network.closeRequest()
      pending = false
      if received and raw.len > 0:
        let current = chain.chainView.bestBlock.value
        var parent = default(array[32, byte])
        if raw.len >= 32:
          for octet in 0..<32: parent[octet] = raw[octet]
        if parent == array[32, byte](current.blockHash):
          if admit(chain, raw, limits, journal, journalPath, true, logging):
            if not network.publish(parent, raw) or not observation(chain, folder, int(index),
                "peer"): return 2
            attemptedSlot = 0 # A changed parent can make this process eligible later in the same wall-clock slot.
        else:
          log(logging, LogTarget.Application, LogLevel.Warn, "Block rejected: stale parent; fork choice is unavailable")
          stderr.writeLine("DEVNET_REFUSED stale-parent") # A response to an older local head cannot roll the node back.
      peer = (peer+1) mod 6
      if peer == int(index): peer = (peer+1) mod 6
      nextDial = getMonoTime()+initDuration(milliseconds = 50) # Peer rotation remains local policy and changes no GP admission rule.
    if not pending and getMonoTime() >= nextDial:
      let parent = array[32, byte](chain.chainView.bestBlock.value.blockHash)
      pending = network.request(uint16(base+uint64(peer)), peers[peer], parent, certificate,
          keyFile, alpn)
      dialedAt = getMonoTime()
      if not pending: return 2 # Actual resource/setup failure is not an empty peer reply.
  if not observation(chain, folder, int(index), "final"): return 2
  if chain.chainView.bestBlock.value.slot != uint32(stop):
    stderr.writeLine("DEVNET_INCOMPLETE node=" & $index)
    return 2
  log(logging, LogTarget.Startup, LogLevel.Info, "Stopping development validator " & $index)
  stdout.writeLine("DEVNET_COMPLETE node=" & $index)
  flushFile(stdout)
  0

proc runDevnet*(arguments: seq[string], logging: LogWriter = default(LogWriter),
    selected: PvmBackend = DefaultPvmBackend): int {.raises.} =
  ## Explicit development-only commands are parsed before ordinary service startup.
  if arguments.len == 3 and arguments[1] == "identity":
    var index = 0'u64
    if not number(arguments[2], 5, index): return 2
    let seed = deriveEd25519Seed(trivialSeed(uint32(index)))
    if seed.error != CryptoError.None: return 2
    defer: clearSeed(seed.value)
    let public = publicKey(seed.value)
    let exported = exportPkcs8(seed.value)
    if public.error != CryptoError.None or exported.error != CryptoError.None: return 2
    let name = peerName(array[32, byte](public.value))
    var label = ""
    for octet in name: label.add(char(octet))
    stdout.writeLine("{\"public\":\"" & hex(array[32, byte](public.value)) & "\",\"name\":\"" &
        label & "\",\"pkcs8\":\"" & hex(exported.value) & "\"}")
    return 0
  if arguments.len == 3 and arguments[1] == "init":
    let genesis = initTinyGenesis()
    if genesis.error != GenesisError.None:
      stderr.writeLine("DEVNET_GENESIS_FAILED")
      return 2
    if replaceAtomicFile(arguments[2], bytes(tinyChainText(genesis.value)), ByteLimit(1048576)) !=
        AtomicFileError.None:
      return 2
    stdout.writeLine("DEVNET_GENESIS_OK")
    return 0
  if arguments.len > 1 and arguments[1] == "node": return node(arguments, logging, selected)
  stderr.writeLine("Usage: ragnarok tiny-devnet init CHAIN_JSON | node DIRECTORY INDEX BASE_PORT START_UNIX_MS STOP_SLOT CURRENT_POLICY")
  2
