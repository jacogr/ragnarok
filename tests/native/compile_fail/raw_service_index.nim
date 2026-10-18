# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Deliberately invalid: service fields, work variants and record-count policies are nominal
## types.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

import ../../../src/codec/[composite, bounded]
let service = 1'u32
let record = Preimage(service: service, blob: BlobSpan())
discard record
