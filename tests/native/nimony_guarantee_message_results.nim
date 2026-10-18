# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/backend-failed guarantee signing messages must stop at their supported success contract.
import std/[assertions, cmdline, syncio]
import ../../src/crypto/[primitives, guarantee]
# Faults are available only in the test observer library; production callers cannot force provider outcomes.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}
let useDefault = paramStr(2) == "default"
let source = case paramStr(1)
  of "empty": newSeq[byte](0) # Raw helper callers validate reports separately; empty input still has a hash.
  of "bytes": @[1'u8, 2, 3] # Nonempty failure must not expose a partial domain or all-zero digest.
  else: quit(2); @[]        # Unknown modes cannot count as guard evidence.
fail(1)
let parsed = if useDefault: default(GuaranteeMessageResult) else: guaranteeMessage(source)
assert parsed.error == (if useDefault: CryptoError.Uninitialized else: CryptoError.BackendFailure)
echo array[45, byte](parsed.value)[0]
