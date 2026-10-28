# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real signed execution, startup policies and offline block/state queries agree across full backends and retention selections.
import std/[assertions, syncio, envvars, strutils, monotimes, times]
import std/posix/posix
import ../../support/[application_recovery_execution, accumulation_completion_context,
    historical_samples, managed_storage_samples]
import ../../../src/app/[services, options, chain, handoff, preparation_worker, block_input,
  historical_query, checkpoint_identity, checkpoint_codec, checkpoint_recovery]
import ../../../src/chain/[genesis, provider]
import ../../../src/state/store
import ../../../src/storage/[history_index, managed_manifest]
import ../../../src/codec/[bounded, header, report_owned]
import ../../../src/lib/json_writer
proc retentionPid(): cint {.importc: "getpid", cdecl, header: "<unistd.h>".}
  ## Each assertion/crash leaves only its own ignored process namespace for inspection.
proc configured(chain, path, backend: string, selection: int): Options =
  ## Explicit policy values are parsed by the same service boundary as production startup.
  var args = @["server", "--with-state", "--chain", chain]
  if backend != "memory":
    args.add("--state-storage"); args.add("disk")
    args.add("--state-db"); args.add(path)
    args.add("--state-layout"); args.add(backend)
  if selection == 1: args.add("--archive")
  elif selection == 2:
    args.add("--retain-blocks"); args.add("1")
  elif selection == 3:
    args.add("--retain-blocks"); args.add("300")
  result = default(Options)
  assert parseCanonicalOptions(args, result)
proc waitAdoption(owner: var Services) =
  ## Dispatcher polling observes only permitted scalars until collection installs the durable receipt.
  let start = getMonoTime()
  while owner.accumulationStage != AccumulationHandoffStage.Finished:
    assert (getMonoTime()-start).inSeconds < 20
    owner.tick(0)
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining)
proc offline(chain, path, backend, hash, output: string): Options =
  ## No retention override or listener is accepted by an offline query.
  var args = @["history", "--with-state", "--chain", chain, "--state-storage", "disk",
    "--state-db", path, "--state-layout", backend, "--history-block", hash]
  if output.len > 0:
    args.add("--history-checkpoint"); args.add(output)
  result = default(Options)
  assert parseOptions(args, result)
proc cycle(fixture: RecoveryExecutionFixture, chain, backend: string, selection: int): array[32,
    byte] {.raises.} =
  ## Genuine opaque production preparation is repeated after each policy is selected; no structural certificate is substituted.
  let path = "retention-service-" & $retentionPid() & "-" & backend & "-" & $selection
  var owner = default(Services)
  var inventory: seq[BlockSnapshotResult] = @[]
  var checkpoint = path & ".checkpoint"
  defer:
    owner.close()
    if backend != "memory": removeHistorySample(path, inventory, 3)
    if backend == "journal":
      var native = path
      discard posix.unlink(native.toCString())
    elif backend == "managed": removeManagedSample(path, [ManagedEpoch(1)])
    discard posix.unlink(checkpoint.toCString())
  assert owner.start(configured(chain, path, backend, selection), "retention acceptance")
  let first = owner.chainView.bestBlock
  inventory.add(first)
  let parent = first.value.blockHash
  let original = array[32, byte](owner.stateSnapshot.value.commitment.root)
  let wire = recoveryChildBytes(fixture)
  var input = default(BlockInput)
  let id = receiveRecoveryInput(owner, input, wire)
  let ticket = owner.beginPreparation(input, id).value
  assert owner.historicalSnapshot(parent).error == HistoryError.Busy
  owner.waitRecoveredPreparation()
  let completion = owner.collectPreparation(ticket)
  assert completion.kind == PreparationCompletionKind.Completed and completion.value.error ==
      BlockInputError.None
  assert owner.enqueueAccumulation(completion.value.value, completionLimits().composition) ==
      AccumulationEnqueueError.None
  owner.tick(0)
  if backend != "memory": assert owner.historicalSnapshot(parent).error == HistoryError.Busy
  owner.waitAdoption()
  assert owner.takeAccumulation().error == ApplicationChainError.None
  let head = owner.chainView.bestBlock
  inventory.add(head)
  let hash = head.value.blockHash
  let held = owner.historicalSnapshot(hash).value
  assert held.chainView.bestBlock.value.blockBody == wire
  result = array[32, byte](held.stateSnapshot.value.commitment.root)
  assert result != original
  assert owner.chainView.retainedCount == (if selection == 2: 1 else: 2)
  assert owner.chainView.validationHeaderCount == 2
  assert owner.historicalSnapshot(parent).error == (if selection ==
      2: HistoryError.Unavailable else: HistoryError.None)
  if backend != "memory": assert owner.historicalCleanupError == HistoryError.None
  owner.close()
  assert held.chainView.bestBlock.value.blockBody == wire
  if backend != "memory":
    assert owner.start(configured(chain, path, backend, 0), "stored policy restart")
    assert owner.chainView.retainedCount == (if selection == 2: 1 else: 2)
    assert array[32, byte](owner.stateSnapshot.value.commitment.root) == result
    let historical = owner.historicalSnapshot(HistoryOrdinal(1))
    assert historical.error == (if selection == 0: HistoryError.Unavailable elif selection ==
        2: HistoryError.Pruned else: HistoryError.None)
    owner.close()
    let output = runHistoricalQuery(offline(chain, path, backend, historyHashName(hash),
        checkpoint)).value
    var expectedHex = ""
    for octet in wire: expectedHex.add(toHex(int(octet),
        2).toLowerAscii) # Independent stdlib formatting checks every emitted body octet.
    assert ("\"blockHex\":\"" & expectedHex & "\"") in $output
    assert "\"bodyAvailable\":true" in $output
    assert historyHashName(hash) in $output
    let identity = captureApplicationCheckpointIdentity(held).value
    let header = held.chainView.bestBlock.value.header
    var sealed = newSeq[byte](header.headerInfo.value.consumed)
    assert encodeOwnedHeader(header, sealed).error == HeaderError.None
    let raw = readFile(checkpoint)
    var bytes = newSeq[byte](raw.len)
    for index, octet in raw: bytes[index] = byte(octet)
    var limits = genesisStoreLimits()
    limits.writes = ElementLimit(DefaultStateWrites)
    limits.writeValueBytes = ByteLimit(DefaultStateWriteBytes)
    let restored = decodeRecoveryCheckpoint(bytes, sealed, identity, limits, ByteLimit(
        16777216)).value
    assert array[32, byte](restored.stateSnapshot.value.commitment.root) == result
    if selection != 2:
      let seed = runHistoricalQuery(offline(chain, path, backend, historyHashName(parent), "")).value
      assert "\"bodyAvailable\":false" in $seed and "\"blockHex\":null" in $seed
    let absent = offline(chain, path & "-absent", backend, historyHashName(hash), "")
    assert runHistoricalQuery(absent).error == HistoryError.IoFailure
    var missing = path & "-absent"
    var metadata = default(Stat)
    assert posix.stat(missing.toCString(), metadata) != 0 and errno() == ENOENT
proc main() {.raises.} =
  ## Every full backend executes the exact same admitted child under default, archive and bounded policies.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet)
  let fixture = recoveryFixture(decodeOwnedReport(bytes, 2).value)
  var chain = "retention-service-chain-" & $retentionPid()
  writeFile(chain, fixture.origin.text)
  defer: discard posix.unlink(chain.toCString())
  let expected = cycle(fixture, chain, "memory", 0)
  for backend in ["memory", "journal", "managed", "paged"]:
    for selection in 1..3: assert cycle(fixture, chain, backend, selection) == expected
  assert cycle(fixture, chain, "journal", 0) == expected
try:
  main()
except:
  quit(2) # Fixture, disk and checkpoint failures cannot qualify historical acceptance.
echo "PASS retention services: identical execution, full backends, stored policies, exact offline block/state export and no genesis fallback"
