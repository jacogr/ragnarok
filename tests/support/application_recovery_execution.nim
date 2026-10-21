# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared genuine signed execution context crosses encoded checkpoint recovery before Services owns its fresh canonical graph.
import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../src/app/[chain, services, options, checkpoint_identity, checkpoint_codec,
    checkpoint_recovery, block_input, preparation_worker]
import ../../src/chain/[genesis, provider]
import ../../src/codec/[bounded, header, report_owned, block_codec]
import ../../src/state/store
import ./application_candidate_context as candidate_context

type RecoveryExecutionFixture* = object ## Original execution authority is deliberately separate from the restored map graph.
  origin*: candidate_context.SeedFixture
  expected*: ApplicationCheckpointIdentity
  envelope*, sealed*: seq[byte]
proc recoveryFixture*(base: OwnedReport): RecoveryExecutionFixture =
  ## Retain a genuine signed two-guest block and detached checkpoint bytes from its complete parent.
  result = default(RecoveryExecutionFixture)
  result.origin = candidate_context.fixture(base)
  let source = candidate_context.initialized(result.origin)
  result.expected = captureApplicationCheckpointIdentity(source).value
  result.envelope = encodeApplicationCheckpoint(source, ByteLimit(high(uint64))).value
  let header = source.chainView.bestBlock.value.header
  result.sealed = newSeq[byte](header.headerInfo.value.consumed)
  assert encodeOwnedHeader(header, result.sealed).error == HeaderError.None
proc recoveryOptions*(path: string, limits: StateStoreLimits, port = 0'u16): Options =
  ## Component recovery retains its explicit caller policy; optional RPC uses a separately selected local port.
  var arguments = @["server", "--with-state", "--chain", path, "--state-writes", $uint64(
      limits.writes),
    "--state-write-bytes", $uint64(limits.writeValueBytes)]
  if port != 0:
    arguments.add("--with-rpc")
    arguments.add("--rpc-port")
    arguments.add($port) # Port configuration never changes the checkpoint's inherited state policy.
  result = default(Options)
  assert parseOptions(arguments, result)
proc startRecoveredExecution*(owner: var Services, fixture: RecoveryExecutionFixture,
    path: string, limits: StateStoreLimits, port = 0'u16) {.raises.} =
  ## The temporary restored result retires on return, leaving no host canonical alias across later execution leases.
  writeFile(path, fixture.origin.text)
  let restored = decodeRecoveryCheckpoint(fixture.envelope, fixture.sealed, fixture.expected,
      limits, ByteLimit(high(uint64)))
  assert restored.error == ApplicationRecoveryError.None
  assert owner.startRecovered(recoveryOptions(path, limits, port), "recovered execution", restored)

proc recoveryChildBytes*(fixture: RecoveryExecutionFixture): seq[byte] =
  ## Encode exact signed child bytes before granting any native canonical lease.
  let child = candidate_context.candidateBlock(fixture.origin)
  result = newSeq[byte](child.blockInfo.value.consumed)
  assert encodeOwnedBlock(child, result).error == FrameError.None
proc receiveRecoveryInput*(owner: Services, input: var BlockInput,
    wire: openArray[byte]): BlockInputId =
  ## Receiver admission retains the restored parent before preparation closes canonical access.
  let admitted = owner.beginBlockInput(input, ByteLimit(uint64(wire.len)), [],
    BlockInputLimits(blockBytes: ByteLimit(uint64(wire.len))), candidate_context.preparationLimits())
  assert admitted.error == BlockInputError.None
  result = admitted.value
  assert input.append(result, wire, true) == BlockInputError.None
proc waitRecoveredPreparation*(owner: var Services) =
  ## Poll only permitted scalar/dispatcher work; no canonical or raw-input alias is touched during the lease.
  let started = getMonoTime()
  while owner.preparationPhase != PreparationPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20
    owner.tick(0)
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # The bounded host pause yields to the actual native worker.
