# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real child-process POSIX file-size ceilings force zero/partial writes without production fault hooks.
## Native SDK declarations below are test-only; parent processes retain their original resource limits.

import std/assertions
import std/syncio
import std/posix/posix
import ../../../src/state/checkpoint_file as state_checkpoint_file
import ../../../src/state/checkpoint as state_checkpoint
import ../../../src/state/store as state_store
import ../../../src/codec/state_trie as codec_state_trie
import ../../../src/codec/state_layout as codec_state_layout
import ../../../src/codec/bounded as codec_bounded

type
  ResourceLimit {.importc: "struct rlimit", header: "<sys/resource.h>", bycopy.} = object
    ## Supported 64-bit Linux/macOS SDK fields retain their exact C names and native structure.
    current {.importc: "rlim_cur".}: uint64
    maximum {.importc: "rlim_max".}: uint64
  SignalHandler = proc(value: cint) {.cdecl, raises: [].} ## A nonallocating C callback keeps a size violation observable as write refusal.

let fileLimit {.importc: "RLIMIT_FSIZE", header: "<sys/resource.h>".}: cint
let sizeSignal {.importc: "SIGXFSZ", header: "<signal.h>".}: cint
let signalError {.importc: "SIG_ERR", header: "<signal.h>".}: SignalHandler
proc getLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "getrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Inspect the inherited hard ceiling before changing the child's soft file-size limit.
proc setLimit(resource: cint, value: ptr ResourceLimit): cint {.importc: "setrlimit", cdecl,
    header: "<sys/resource.h>".}
  ## Restrict only this child; no parent/global resource budget is changed.
proc install(signal: cint, handler: SignalHandler): SignalHandler {.importc: "signal", cdecl,
    header: "<signal.h>".}
  ## Keep the real kernel size violation as a return value instead of process termination.
proc ignore(value: cint) {.cdecl, raises: [].} =
  ## The signal handler performs no allocation, output or state access.
  discard

const FileName = "state-checkpoint-write-failure.bin"
proc policy(): StateStoreLimits =
  ## One multi-chunk value permits failures near the beginning and final byte of publication.
  StateStoreLimits(trie: StateTrieLimits(items: ElementLimit(1), perValue: ByteLimit(5000),
    totalValueBytes: ByteLimit(5000), nodes: TrieNodeLimit(1024)),
    writes: ElementLimit(1), writeValueBytes: ByteLimit(5000))
proc attempt(prior, next: StateStoreSnapshot, size: uint64, succeeds: bool) =
  ## A real forked writer must publish everything or preserve the exact prior trusted checkpoint.
  assert saveFullCheckpoint(FileName, prior, ByteLimit(10000)).error == CheckpointFileError.None
  let child = posix.fork()
  assert int(child) >= 0
  if int(child) == 0:
    var limits = default(ResourceLimit)
    if getLimit(fileLimit, addr limits) != 0 or size > limits.maximum:
      posix.exitnow(3) # Setup failure cannot masquerade as a witnessed write refusal.
    let previous = install(sizeSignal, ignore)
    if previous == signalError:
      posix.exitnow(4) # A failed signal policy would invalidate the claimed partial-write witness.
    limits.current = size
    if setLimit(fileLimit, addr limits) != 0:
      posix.exitnow(5) # The actual OS must enforce the selected child-only bound.
    let outcome = saveFullCheckpoint(FileName, next, ByteLimit(10000))
    let wanted = if succeeds: CheckpointFileError.None else: CheckpointFileError.IoFailure
    if outcome.error != wanted:
      posix.exitnow(6) # No fabricated producer refusal or interrupted process satisfies the expected stage.
    let root = if succeeds: next.commitment.root else: prior.commitment.root
    if loadFullCheckpoint(FileName, root, policy(), ByteLimit(10000)).error !=
        CheckpointFileError.None:
      posix.exitnow(7) # The child itself must observe the complete authorized old/new file after cleanup.
    posix.exitnow(0) # Avoid destructing copied parent ARC owners after fork; the child has retired its own writer resources.
  var reaped = false
  defer:
    if not reaped:
      discard posix.kill(child, SIGTERM)
      var ignored = 0.cint
      discard posix.waitpid(child, ignored, 0) # Every parent failure path joins its bounded child.
  var status = 0.cint
  assert posix.waitpid(child, status, 0) == child
  reaped = true
  assert WIFEXITED(status) and WEXITSTATUS(status) == 0, "real kernel write-limit child"
  let expected = if succeeds: next else: prior
  let restored = loadFullCheckpoint(FileName, expected.commitment.root, policy(), ByteLimit(10000))
  assert restored.error == CheckpointFileError.None
  assert encodeFullCheckpoint(restored.value.snapshot.value, ByteLimit(10000)).value ==
    encodeFullCheckpoint(expected, ByteLimit(10000)).value # Parent observation independently verifies complete exact bytes.
proc main() =
  ## Zero/partial/final-byte failures and exact/ample controls exercise real temporary-file rollback.
  var path = FileName
  defer: discard posix.unlink(path.toCString()) # All generated files remain in the runner's ignored working directory.
  let prior = newStateStore([], policy()).value.snapshot.value
  var value = newSeq[byte](5000)
  for index in 0..<value.len:
    value[index] = byte(index mod 251) # Several OS writes/chunks cannot hide a missing suffix.
  let next = newStateStore([StateEntry(key: default(StateKey), value: value)], policy()).value.snapshot.value
  let length = uint64(encodeFullCheckpoint(next, ByteLimit(10000)).value.len)
  for limit in [0'u64, 1, 64, 4096, length - 1]:
    attempt(prior, next, limit, false) # Each soft ceiling forces the kernel's real write/partial-write refusal.
  for limit in [length, length + 1]:
    attempt(prior, next, limit, true) # The same path publishes normally at exact and ample file-size bounds.
  echo "PASS checkpoint write failures: five real kernel refusals, exact controls and prior-state rollback"
main()
