# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Consuming failed results must stop before payload access; each child supplies a causal start witness.
import std/assertions
import std/syncio
import std/strutils
import std/posix/posix
import ../../../src/storage/managed_io as storage_managed_io
import ../../../src/storage/record_codec as storage_record_codec
import ../../../src/storage/snapshot_codec as storage_snapshot_codec
import ../../../src/storage/journal_codec as storage_journal_codec

proc armTimeout(seconds: cuint): cuint {.importc: "alarm", cdecl, header: "<unistd.h>".}
  ## Bound only the deliberately failing child; timeout signals never qualify as contract evidence.
const ApiFiles = ["managed_io.nim", "record_codec.nim", "snapshot_codec.nim", "journal_codec.nim"]
  ## Each diagnostic must identify its actual guarded API, not merely another failing operation.

proc consumeIo(outcome: var ManagedIoResult[seq[byte]]) =
  ## Unknown incoming status retains the real API runtime guard rather than a compiler-constant error.
  discard outcome.takeValue
proc consumeRecords(outcome: var RecordResult[seq[byte]]) =
  ## Failed record transports must expose no default byte payload through consumption.
  discard outcome.takeValue
proc consumeSnapshot(outcome: var SnapshotResult[SnapshotEncoding]) =
  ## A consumed/default snapshot cannot regain an encoded owner through its success alternative.
  discard outcome.takeValue
proc consumeFrame(outcome: var FrameResult[seq[byte]]) =
  ## Failed frames cannot bypass their checked success precondition through the moving accessor.
  discard outcome.takeValue

proc runChild(mode: int, writer: cint) =
  ## Route bounded failure evidence to the owned pipe and publish a marker before the API guard.
  discard armTimeout(5)
  if posix.dup2(writer, 2) != 2: posix.exitnow(98)
  var marker = 90'u8
  if posix.write(writer, addr marker, 1) != 1: posix.exitnow(98)
  discard posix.close(writer)
  case mode
  of 0:
    var outcome = default(ManagedIoResult[seq[byte]])
    consumeIo(outcome) # The invalid source must stop in the guarded API, before returning bytes.
  of 1:
    var outcome = default(RecordResult[seq[byte]])
    consumeRecords(outcome) # Same contract for decoded record payload ownership.
  of 2:
    var outcome = default(SnapshotResult[SnapshotEncoding])
    consumeSnapshot(outcome) # Same contract for composite snapshot encodings.
  of 3:
    var outcome = default(FrameResult[seq[byte]])
    consumeFrame(outcome) # Same contract for publication frames.
  of 4:
    posix.exitnow(0) # A successful setup/start/join control rules out accepting unrelated early termination.
  else:
    posix.exitnow(98) # Only the five source-owned modes belong to this bounded fixture.
  posix.exitnow(99) # Returning from an invalid extraction is a failed guard, never a successful control.

proc scenario(mode: int) =
  ## Own exactly one child and pipe; retire descriptors and reap before evaluating any child evidence.
  var channels = [-1.cint, -1.cint]
  assert posix.pipe(addr channels[0]) == 0
  let child = posix.fork()
  if child < 0:
    discard posix.close(channels[0])
    discard posix.close(channels[1])
    assert false, "guard child creation failed"
    return
  if child == 0:
    discard posix.close(channels[0]) # The child owns only the causal start writer.
    runChild(mode, channels[1])
  else:
    let writerClosed = posix.close(channels[1])
    var marker = 0'u8
    var count = 0
    while true:
      count = posix.read(channels[0], addr marker, 1)
      if count >= 0 or posix.errno() != EINTR: break # EINTR alone authorizes another identical read.
    var diagnostic = ""
    var overflow = false
    var buffer = default(array[256, char])
    while true:
      let received = posix.read(channels[0], addr buffer[0], buffer.len)
      if received > 0:
        # Drain beyond the bound too, so an unexpected verbose failure cannot deadlock its own pipe.
        for index in 0..<min(received, buffer.len):
          if diagnostic.len < 4096: diagnostic.add(buffer[index])
          else: overflow = true
      elif received == 0 or posix.errno() != EINTR:
        break # EOF terminates capture; a permanent read failure cannot be positive guard evidence.
    let readerClosed = posix.close(channels[0])
    var status = 0.cint
    var joined = -1.cint
    while true:
      joined = posix.waitpid(child, status, 0)
      if joined == child or posix.errno() != EINTR: break # Only this exact child can satisfy retirement.
    assert joined == child and writerClosed == 0 and readerClosed == 0
    assert count == 1 and marker == 90 # A signal before the API boundary cannot count as guard evidence.
    assert not overflow
    if mode == 4:
      assert WIFEXITED(status) and WEXITSTATUS(status) == 0 and diagnostic.len == 0
    else:
      assert mode >= 0 and mode < ApiFiles.len
      assert WIFEXITED(status) and WEXITSTATUS(status) == 1, diagnostic
      let intended = diagnostic.contains(ApiFiles[mode]) and diagnostic.contains(
          "outcome.status ==") and
        diagnostic.contains("[AssertionDefect]")
      assert intended, diagnostic # Exit status alone or an unrelated signal never establishes this guard.

for mode in 0..4:
  scenario(mode) # All four nominal result domains require the same explicit success authority.
echo "PASS storage result transfer guards: four causal refusals and a successful child control"
