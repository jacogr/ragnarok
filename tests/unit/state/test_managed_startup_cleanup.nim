# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Validated managed startup retires only adjacent unselected files; disabled maintenance preserves forensic staging.
import std/[assertions, syncio, envvars, monotimes, times]
import std/posix/posix
import ../../support/managed_storage_samples
import ../../../src/app/[services, options, disk_worker, disk_chain]
import ../../../src/storage/[managed_manifest, managed_io, file_errors]
import ../../../src/codec/bounded
proc pathExists(path: cstring, mode: cint): cint {.importc: "access", header: "<unistd.h>".}
  ## Native zero-mode existence checks witness the absent pending entry without reading it.
proc configured(path: string, threshold: string): Options =
  ## Explicit zero preserves forensic staging; a positive threshold authorizes bounded startup retirement.
  result = default(Options)
  assert parseCanonicalOptions(@["server", "--with-state", "--chain", getEnv(
      "RAGNAROK_APPLICATION_CHECKPOINT"),
    "--state-storage", "disk", "--state-db", path, "--state-layout", "managed",
    "--state-compact-bytes", threshold], result)
proc stagePair(directory: ManagedDirectory, epoch: uint64) =
  ## Unselected bytes intentionally need not be a valid image: selection is the sole authority.
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    assert createManagedFile(directory, kind, ManagedEpoch(epoch), [byte(99)], ByteLimit(1)) == FileError.None
proc inspect(path: string, epoch: uint64, present: bool) =
  ## Inspect exact fixture-owned names only after the Services lease has been retired.
  var directory = default(ManagedDirectory)
  assert openManagedDirectory(directory, path) == FileError.None
  defer: assert directory.close == FileError.None
  for kind in [ManagedFileKind.Snapshot, ManagedFileKind.Journal]:
    let loaded = readManagedFile(directory, kind, ManagedEpoch(epoch), ByteLimit(1))
    if present:
      assert loaded.error == FileError.None and loaded.value == @[byte(99)]
    else:
      assert loaded.error == FileError.IoFailure
proc waitFinished(owner: var Services) =
  ## The dispatcher polls scalar completion while the worker retains the canonical graph aliases.
  let started = getMonoTime()
  while owner.diskPublicationActive:
    owner.tick(0)
    assert (getMonoTime()-started).inSeconds < 20
    var requested = Timespec(tv_sec: posix.Time(0), tv_nsec: 1_000_000)
    var remaining = default(Timespec)
    discard nanosleep(requested, remaining)
proc main() {.raises.} =
  ## Startup validates the selected pair before cleanup, refuses aliases, and never scans farther epochs.
  let path = "managed-startup-cleanup"
  var owner = default(Services)
  defer: owner.close()
  assert owner.start(configured(path, "0"), "validator")
  owner.close()
  let first = readFile(path & "/CURRENT")
  var directory = default(ManagedDirectory)
  assert openManagedDirectory(directory, path) == FileError.None
  stagePair(directory, 2)
  stagePair(directory, 4)
  assert directory.close == FileError.None
  writeFile(path & "/CURRENT.next", "partial")
  assert owner.start(configured(path, "0"), "validator")
  owner.close()
  inspect(path, 2, true)
  assert readFile(path & "/CURRENT.next") == "partial"
  var corrupt = first
  corrupt[corrupt.high] = char(ord(corrupt[corrupt.high]) xor 1)
  writeFile(path & "/CURRENT", corrupt)
  assert not owner.start(configured(path, "1"), "validator")
  owner.close()
  inspect(path, 2, true)
  assert readFile(path & "/CURRENT.next") == "partial"
  writeFile(path & "/CURRENT", first)
  assert owner.start(configured(path, "1"), "validator")
  owner.close()
  var pending = path & "/CURRENT.next"
  assert pathExists(pending.toCString(), 0) != 0
  assert readFile(path & "/CURRENT") == first
  inspect(path, 2, false)
  inspect(path, 4, true)
  assert owner.start(configured(path, "1"), "validator")
  assert owner.beginDiskMaintenance()
  waitFinished(owner)
  assert owner.diskMaintenanceCompletion.kind == DiskCompletionKind.Maintained
  assert owner.diskMaintenanceCompletion.maintenanceValue.error == DiskChainError.None
  owner.close()
  let second = readFile(path & "/CURRENT")
  assert second != first
  assert openManagedDirectory(directory, path) == FileError.None
  stagePair(directory, 1)
  stagePair(directory, 3)
  assert directory.close == FileError.None
  writeFile(path & "/CURRENT.next", "partial-again")
  assert owner.start(configured(path, "1"), "validator")
  owner.close()
  assert pathExists(pending.toCString(), 0) != 0
  inspect(path, 1, false)
  inspect(path, 3, false)
  inspect(path, 4, true)
  assert readFile(path & "/CURRENT") == second
  var alias = path & "/snapshot-0000000000000003.bin"
  var target = "CURRENT"
  assert posix.symlink(target.toCString(), alias.toCString()) == 0
  assert not owner.start(configured(path, "1"), "validator")
  owner.close()
  assert readFile(path & "/CURRENT") == second
  assert readFile(alias) == second # Refusal preserves both the symlink and its selected target.
  assert posix.unlink(alias.toCString()) == 0
  assert owner.start(configured(path, "1"), "validator")
  owner.close()
  removeManagedSample(path, [ManagedEpoch(1), ManagedEpoch(2), ManagedEpoch(3), ManagedEpoch(4)])
try:
  main()
except:
  quit(2)
echo "PASS managed startup cleanup: checked adjacent epochs, zero preserves staging, unknown files and aliases remain protected"
