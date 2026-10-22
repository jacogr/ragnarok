# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Narrow native filesystem metadata used by management observations and socket ownership checks.
## The platform C header owns struct layout; no hand-written ABI padding is assumed.

type FileStatus* {.importc: "struct stat", header: "<sys/stat.h>", bycopy.} = object
  ## Only inspected fields are named; the native header supplies all remaining fields and alignment.
  st_mode*: uint32
  st_uid*: uint32
  st_dev*, st_ino*: uint64
  st_size*, st_blocks*: int64

proc readStatus*(path: cstring, status: var FileStatus): cint {.importc: "lstat",
    header: "<sys/stat.h>".}
  ## Inspect the selected path itself without following a terminal symlink.
proc readFileStatus*(fd: cint, status: var FileStatus): cint {.importc: "fstat",
    header: "<sys/stat.h>".}
  ## Observe one already opened descriptor without changing its file position.
