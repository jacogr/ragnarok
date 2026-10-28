# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Batch natural adapter; malformed decimal/hex transport is distinct from codec failure.
##
## Provides a test-process entry point that accepts trusted fixture requests and emits native
## observations for the independent Python harness.

import std/assertions
import std/cmdline
import std/strutils
import std/syncio
import ./nimony_batch_support
import ../../src/codec/natural as codec_natural

# Handle one trusted request, including deliberately malformed decimal and empty wire tokens.
proc request(line: string) =
  if line.startsWith("E "):
    var value: uint64 = 0
    if not parseUnsigned(line[2..^1], value):
      echo "inputerror" # Out-of-domain textual input cannot reach encoding.
      return
    let encoded = encode(JamNatural(value))
    var hex = ""
    # Display only the complete encoded prefix, preserving leading zeroes.
    for i in 0..<encoded.len: hex.add(toHex(int(encoded.bytes[i]), 2).toLowerAscii())
    echo hex
  elif line.startsWith("D "):
    let hex = line[2..^1]
    if hex.len mod 2 != 0 or hex.len > 128:
      echo "inputerror" # Utility storage is bounded independently of codec policy.
      return
    var bytes = newSeq[byte](hex.len div 2)
    # Original corpus hex transport is lowercase; each pair supplies one actual wire byte.
    for i in 0..<bytes.len: bytes[i] = octet(hex[2*i..2*i+1])
    let decoded = decode(bytes)
    if decoded.ok:
      echo $uint64(decoded.value) & " " & $decoded.consumed # Observe value and exact prefix extent.
    else:
      echo ($decoded.error).toLowerAscii() # Failure exposes only its typed reason.
  else:
    echo "inputerror" # Unknown adapter operations do not invoke production code.

# Every nonempty source line produces exactly one observation, including empty decode payloads.
try:
  for line in readFile(paramStr(1)).splitLines():
    if line.len > 0: request(line) # Ignore only the file-final empty line.
except:
  # Fixture I/O failures are fatal and cannot masquerade as production codec errors.
  quit 2
