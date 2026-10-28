# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Historical exports create new files outside the selected database and its archive namespace.
## Call with the database lease held and a stable directory namespace; final publication never replaces an existing inode.
import std/strutils
import std/posix/posix
import ../lib/atomic_file
import ../storage/history_index
import ../codec/bounded

proc resolveNative(path: cstring, buffer: nil cstring): nil cstring {.importc: "realpath", cdecl,
    header: "<stdlib.h>".}
  ## A nil output requests libc-owned exact canonical bytes without guessing the platform PATH_MAX.
proc freeNative(address: nil pointer) {.importc: "free", cdecl, header: "<stdlib.h>".}
  ## Every successful libc path allocation has one local retirement, including later guard refusals.
proc resolved(path: string): HistoryResult[string] =
  ## Resolve existing ancestors, dot components and symbolic links while owning all returned bytes.
  var name = path
  let native = resolveNative(name.toCString(), nil)
  if native == nil: return historyFailure[string](HistoryError.IoFailure)
  defer: freeNative(cast[nil pointer](native)) # Copy before retiring the foreign allocation on every return.
  historySuccess($native)
proc destination(path: string): HistoryResult[string] =
  ## A new filename needs a real existing parent; resolve that parent rather than requiring the new file to exist.
  var slash = -1
  for index, character in path:
    if character == '/': slash = index
  let name = if slash < 0: path else: path.substr(slash+1)
  if name.len == 0 or name in [".", ".."]: return historyFailure[string](HistoryError.InvalidFormat)
  let parent = if slash < 0: "." elif slash == 0: "/" else: path.substr(0, slash-1)
  let directory = resolved(parent)
  if directory.error != HistoryError.None: return directory
  historySuccess(directory.value & (if directory.value == "/": "" else: "/") & name)
func sameFile(left, right: Stat): bool =
  ## Native device/inode identity also covers case-folding filesystems and alternative directory aliases.
  left.st_dev == right.st_dev and left.st_ino == right.st_ino
proc protectedAncestor(output: string, selected, archive: Stat, hasArchive: bool): HistoryError =
  ## Walk existing parent identities without a directory listing or trusting textual canonicalization alone.
  var ancestor = output
  while true:
    let slash = ancestor.rfind('/')
    ancestor = if slash <= 0: "/" else: ancestor.substr(0, slash-1)
    var name = ancestor
    var metadata = default(Stat)
    if posix.stat(name.toCString(), metadata) != 0: return HistoryError.IoFailure
    if sameFile(metadata, selected) or (hasArchive and sameFile(metadata, archive)):
      return HistoryError.InvalidPolicy
    if ancestor == "/": break # Parent extents strictly decrease until the native root is checked.
  HistoryError.None
func within(path, root: string): bool =
  ## Separator-aware matching protects a namespace without treating similarly prefixed siblings as children.
  path == root or path.startsWith(root & "/")
proc exportHistoricalCheckpoint*(database, path: string, bytes: openArray[byte],
    limit: ByteLimit): HistoryError =
  ## Reject physical source aliases and database-owned namespaces before creating any output; occupied names fail atomically.
  for name in [database, path]:
    if name.len == 0 or name.len > 4096: return HistoryError.InvalidFormat
    for character in name:
      if character == char(0): return HistoryError.InvalidFormat # Native identity may not truncate at embedded NUL.
  let selected = resolved(database)
  if selected.error != HistoryError.None: return selected.error
  let output = destination(path)
  if output.error != HistoryError.None: return output.error
  var primary = selected.value
  var selectedMetadata = default(Stat)
  if posix.stat(primary.toCString(), selectedMetadata) != 0: return HistoryError.IoFailure
  if within(output.value, selected.value): return HistoryError.InvalidPolicy
  let historical = database & ".history"
  let reserved = destination(historical)
  if reserved.error != HistoryError.None: return reserved.error
  if within(output.value, reserved.value): return HistoryError.InvalidPolicy
  # A pre-existing archive symlink may resolve somewhere different from its reserved sibling spelling.
  var archive = historical
  var metadata = default(Stat)
  var archiveMetadata = default(Stat)
  var hasArchive = false
  if posix.lstat(archive.toCString(), metadata) == 0:
    let physical = resolved(archive)
    if physical.error != HistoryError.None: return physical.error
    if within(output.value, physical.value): return HistoryError.InvalidPolicy
    if posix.stat(archive.toCString(), archiveMetadata) != 0: return HistoryError.IoFailure
    hasArchive = true
  elif errno() != ENOENT:
    return HistoryError.IoFailure # Missing archives are allowed; inaccessible or malformed ancestors are not ignored.
  let protected = protectedAncestor(output.value, selectedMetadata, archiveMetadata, hasArchive)
  if protected != HistoryError.None: return protected
  # Reserve the future history directory name even when source spelling differs on a case-folding filesystem.
  if output.value.toLowerAscii.endsWith(".history"):
    var source = output.value.substr(0, output.value.len-9)
    var identity = default(Stat)
    if posix.stat(source.toCString(), identity) == 0 and sameFile(identity, selectedMetadata):
      return HistoryError.InvalidPolicy
  let written = createAtomicFile(output.value, bytes, limit)
  case written
  of AtomicFileError.None: HistoryError.None
  of AtomicFileError.Busy: HistoryError.AlreadyExists
  of AtomicFileError.LimitExceeded: HistoryError.LimitExceeded
  of AtomicFileError.PublishedUnsynced: HistoryError.PublishedUnsynced
  else: HistoryError.IoFailure
