# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared real service/preparation lifetimes retain no fixture graph alias when leasing canonical state.
import std/assertions
import std/syncio
import std/envvars
import std/monotimes
import std/times
import std/posix/posix
import ../../src/app/services as app_services
import ../../src/app/options as app_options
import ../../src/app/block_input as app_block_input
import ../../src/app/preparation_worker as app_preparation_worker
import ../../src/app/checkpoint_worker as app_checkpoint_worker
import ../../src/codec/bounded as codec_bounded
import ../../src/codec/report_owned as codec_report_owned
import ./app_candidate_context as candidate_context
proc checkpointServicesOptions*(path: string): Options =
  ## Service state mutation ceilings are explicit; listeners remain disabled in component verification.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--chain", path, "--with-state", "--state-writes", "1000",
    "--state-write-bytes", "1000000"], result)
proc startCheckpointServices*(owner: var Services, path: string) {.raises.} =
  ## Author seed text from the pinned signed-block fixture, then retire that unrelated graph before any canonical lease.
  let raw = readFile(getEnv("RAGNAROK_STATE_REPORT"))
  var bytes = newSeq[byte](raw.len)
  for index, octet in raw: bytes[index] = byte(octet) # Only initialized fixture bytes reach owned decoding.
  let context = candidate_context.fixture(decodeOwnedReport(bytes, 2).value)
  writeFile(path, context.text)
  assert owner.start(checkpointServicesOptions(path), "checkpoint lease")
proc beginCheckpointLease*(owner: var Services, input: var BlockInput): PreparationTicket {.raises.} =
  ## A genuine managed execution lease remains held through Done until explicit collection/join, even for malformed block bytes.
  let admitted = owner.beginBlockInput(input, ByteLimit(1), [], BlockInputLimits(
      blockBytes: ByteLimit(1)), candidate_context.preparationLimits())
  assert admitted.error == BlockInputError.None
  assert input.append(admitted.value, [255'u8], true) == BlockInputError.None
  let job = owner.beginPreparation(input, admitted.value)
  assert job.error == PreparationError.None
  job.value
proc waitCheckpointServices*(owner: var Services) =
  ## Scalar export polling and ordinary service ticks stay available while canonical/RPC aliases are leased.
  let started = getMonoTime()
  while owner.checkpointExportPhase != ApplicationCheckpointWorkerPhase.Done:
    assert (getMonoTime() - started).inSeconds < 20
    owner.tick(0)
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining) # Test scheduling makes no production I/O latency claim.
