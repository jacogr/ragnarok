# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Integration results expose no default or failed key, snapshot, child, count or fixture bytes.
##
## Provides a command-line-selected runtime misuse probe; the failure harness checks its
## rejection diagnostic and exit status.

import std/assertions
import std/cmdline
import std/syncio
import ../../src/quic/integration as quic_integration
import ../../src/codec/owned as codec_owned

# Only the isolated observer-linked probe can inject a primitive refusal.
proc fail(flags: cint) {.importc: "ro_fail", cdecl.}

# Select one payload per process so an earlier contract trap cannot hide another result family.
proc main() {.raises.} =
  let args = commandLineParams()
  assert args.len == 2
  let actual = args[1] == "error"
  let empty = default(VerifiedDigest)
  let bank = default(IntegrationBank)
  case args[0]
  of "key":
    var checked = default(IntegrationResult[PreimageKey])
    if actual: fail(1); checked = preimageKey([]) # A genuine backend refusal carries no key.
    echo array[32, byte](checked.value)[0]
  of "capture":
    var checked = default(IntegrationResult[VerifiedDigest])
    var input = @[0'u8]
    if actual: checked = captureDigest(input, default(PreimageKey)) # Malformed wire creates no snapshot.
    discard wireLength(checked.value)
  of "child":
    var checked = default(IntegrationResult[OwnedFrame])
    if actual: checked = verifiedOwner(empty) # A missing parent cannot supply a codec owner.
    discard ownedInfo(checked.value)
  of "length", "copy":
    var checked = default(IntegrationResult[int])
    var output = @[0'u8]
    if actual:
      # Both operation errors retain only a reason, not an implicit successful zero.
      checked = if args[0] == "length": wireLength(empty) else: copyVerifiedWire(empty, output)
    echo checked.value
  of "fixture-key":
    var checked = default(IntegrationResult[PreimageKey])
    if actual: checked = fixtureKey(bank, 0) # Defaults cannot seed all-zero fixture lookups.
    echo array[32, byte](checked.value)[0]
  else:
    var checked = default(IntegrationResult[seq[byte]])
    if actual: checked = fixtureBytes(bank, 0) # A missing bank has no empty successful wire.
    echo checked.value.len

# Trusted invocation errors are separate from the expected release-enabled contract trap.
try:
  main()
except:
  quit(2)
