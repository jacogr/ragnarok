# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private fixed-width C ABI. The execution boundary owns each opaque handle exclusively.
## No protocol gas, host callback or Nim reference crosses into Rust.

const Header = "ragnarok_polkavm.h" # Maintained declarations compile with the concrete C event layout.

type
  PolkaRaw {.importc: "Rpvm", header: Header, incompleteStruct.} = object ## Opaque exclusive Rust storage.
  PolkaHandle* = nil ptr PolkaRaw ## A nullable C handle has no public Nim payload or shared ownership.

type PolkaEvent* {.bycopy, importc: "RpvmEvent", header: Header.} = object ## Complete scalar output of one upstream instruction attempt.
  registers*: array[13, uint64]
  kind*, pc*, detail*: uint32

proc polkaCreate*(backend: uint32, code: nil pointer, length: csize_t,
    output: var PolkaHandle): cint {.importc: "rpvm_create", cdecl, header: Header, raises: [].}
  ## Success transfers one exclusive opaque owner to output; failure writes nil.

proc polkaDestroy*(handle: PolkaHandle): cint {.importc: "rpvm_destroy", cdecl, header: Header,
    raises: [].}
  ## Release one owner exactly once, after all borrowed calls have returned.

proc polkaPrepare*(handle: PolkaHandle, pc: uint32, registers: nil pointer,
    count: csize_t): cint {.importc: "rpvm_prepare", cdecl, header: Header, raises: [].}
  ## Prime a trace at the exact PC, refusing unrepresentable reentry before guest work.

proc polkaStep*(handle: PolkaHandle, output: var PolkaEvent): cint
    {.importc: "rpvm_step", cdecl, header: Header, raises: [].}
  ## Execute exactly one instruction from a primed trace or the preceding continued trace.

proc polkaPage*(handle: PolkaHandle, address, access: uint32, data: nil pointer,
    length: csize_t): cint {.importc: "rpvm_page", cdecl, header: Header, raises: [].}
  ## Replace or remove one complete page from borrowed caller bytes.

proc polkaRead*(handle: PolkaHandle, address: uint32, data: nil pointer,
    length: csize_t): cint {.importc: "rpvm_read", cdecl, header: Header, raises: [].}
  ## Copy one complete mapped page into caller-owned output storage.

proc polkaReset*(handle: PolkaHandle): cint {.importc: "rpvm_reset", cdecl, header: Header,
    raises: [].}
  ## Reset the resident module instance without retaining guest RAM, registers or traced continuation.

proc polkaRevision*(): cstring {.importc: "rpvm_revision", cdecl, header: Header, raises: [].}
  ## Return immutable process-lifetime revision storage for the loaded ABI identity check.
