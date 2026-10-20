# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Publish and verify all fourteen original complete maps through one real bounded checkpoint worker.

import std/[assertions, syncio, monotimes, times]
import std/posix/posix
import ../../../src/state/[checkpoint_worker, checkpoint_bank, checkpoint_head, checkpoint_transfer,
    checkpoint, store]
import ../../../src/lib/atomic_file
import ../../../src/codec/[state_trie, bounded]
import ../../support/published_state

const Prefix = "state-worker-replay"
proc waitDone(worker: var CheckpointWorker) =
  ## Test-only scheduling waits use scalar reads and a finite monotonic deadline.
  let started = getMonoTime()
  while worker.phase != CheckpointWorkerPhase.Done:
    assert (getMonoTime() - started).inSeconds < 30, "bounded published checkpoint worker completion"
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # No production polling or latency guarantee is introduced.
proc detached(expected: Mapping): PreparedCheckpoint =
  ## Source graph and all construction aliases retire here before native publication receives sole encoded bytes.
  let source = newStateStore(expected.entries, policy(expected, expected)).value.snapshot.value
  prepareFullCheckpoint(source, ByteLimit(high(uint64)))
proc replay(worker: var CheckpointWorker, head: var CheckpointHead, expected: Mapping, index: int) =
  ## Independently published roots authorize verification; generated head values never supply their own trust.
  var prepared = detached(expected)
  let maximum = ByteLimit(uint64(prepared.byteLength))
  let operation = if index == 0: CheckpointOperation.Bootstrap else: CheckpointOperation.Advance
  let ticket = worker.stage(prepared, operation, head, maximum).value
  assert prepared.error == CheckpointError.Uninitialized
  assert worker.begin(ticket)
  worker.waitDone()
  assert worker.peek(ticket).value.error == CheckpointBankError.None
  assert worker.stageHead().error == CheckpointWorkerError.Busy
  head = worker.collect(ticket).value.value
  assert uint64(head.generation) == uint64(index)
  assert array[32, byte](head.root) == array[32, byte](expected.root)
  let check = worker.stageVerification(expected.root, policy(expected, expected), maximum).value
  assert worker.begin(check)
  worker.waitDone()
  let verified = worker.collect(check)
  assert verified.kind == CheckpointCompletionKind.Completed and verified.value.error ==
      CheckpointBankError.None
  assert uint64(verified.value.value.generation) == uint64(index)
  let observed = worker.stageHead().value
  assert worker.begin(observed)
  worker.waitDone()
  assert uint64(worker.collect(observed).value.value.generation) == uint64(index)
proc main() {.raises.} =
  ## One reusable native owner publishes every mapping, then fresh locked restoration checks all final bytes and counts.
  for suffix in [".head", ".0", ".1"]:
    var path = Prefix & suffix
    discard posix.unlink(path.toCString()) # Namespace reset precedes any native worker.
  defer:
    for suffix in [".head", ".head.lock", ".0", ".1"]:
      var path = Prefix & suffix
      discard posix.unlink(path.toCString()) # Joined owner and independent restored bank retire before test-only cleanup.
  let mappings = publishedMappings()
  var worker = default(CheckpointWorker)
  defer: discard worker.close()
  assert worker.start(Prefix) == CheckpointBankError.None
  var head = default(CheckpointHead)
  for index, expected in mappings:
    replay(worker, head, expected, index) # Repeated roots still create and acknowledge distinct durable generations.
  assert worker.close().retirementError == CheckpointBankError.None
  let expected = mappings[mappings.high]
  var bank = default(CheckpointBank)
  defer: discard bank.close()
  assert bank.openCheckpointBank(Prefix) == CheckpointBankError.None
  matches(bank.restore(expected.root, policy(expected, expected), ByteLimit(high(
      uint64))).value.snapshot.value, expected)
  assert uint64(bank.selectedHead().value.generation) == 13
  assert bank.close() == CheckpointBankError.None
  echo "PASS checkpoint worker replay: fourteen published maps, detached publication, trusted verification and restart"
try:
  main() # Native or fixture errors cannot become successful empty-corpus evidence.
except:
  quit(2)
