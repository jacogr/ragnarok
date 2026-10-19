# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Two mutable endpoint owners cannot close the same descriptor after an implicit copy.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "ownership_compile", "expected": "'=dup' is not available for type <UdpEndpoint>", "build_name": "quic-endpoint-copy"}

import ../../../src/quic/io
var original = default(UdpEndpoint)
var duplicate = original
original.close()
duplicate.close()
