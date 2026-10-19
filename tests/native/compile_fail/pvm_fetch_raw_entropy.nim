# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Arbitrary byte arrays cannot enter the nominal invocation entropy boundary implicitly.

# @@Verification={"group": "nominal", "expected": "got: array[0..31, uint8] but wanted: FetchEntropy"}

import ../../../src/pvm/host_fetch

type
  # This fixture binds the public entropy type to a field to isolate nominal assignment checking.
  Input = object
    entropy: FetchEntropy

let raw = default(array[32, byte])
discard Input(entropy: raw)
