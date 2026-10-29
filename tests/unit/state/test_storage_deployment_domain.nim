# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Larger fixture identities remain unique across 16-bit boundaries and preserve complete revision payloads.
import std/[assertions, syncio]
import ../../support/storage_deployment_samples
import ../../../src/codec/state/layout as state_layout

for index in [0, 65535, 65536, 131071]:
  # Independently decode every authored boundary key instead of comparing two calls to the constructor.
  let raw = array[31, byte](deploymentKey(index))
  let decoded = int(raw[0])*16777216+int(raw[1])*65536+int(raw[2])*256+int(raw[3])
  assert decoded == index
  for position in 4..<31:
    assert raw[position] == 0 # Unused key bytes remain canonical.
assert deploymentValue(0, 0) != deploymentValue(65536, 0)
assert deploymentValue(131071, 0) != deploymentValue(131071, 64)
assert deploymentRevision(255, 131072, 64) == 64
assert deploymentRevision(256, 131072, 64) == 0
assert deploymentRevision(63, 65536, 16) == 16
assert deploymentRevision(64, 65536, 16) == 0
echo "PASS storage deployment domain"
