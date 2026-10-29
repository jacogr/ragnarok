# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The socket interface has one lifetime owner for every listener and accepted descriptor.
# @@Verification={"group": "ownership_compile", "expected": "'=dup' is not available for type <FuzzSocket>", "build_name": "jam-fuzzer-socket-copy"}
import ../../../src/app/fuzz/socket as fuzz_socket
var original = default(FuzzSocket)
var duplicate = original
original.close() # Retained original use prevents last-use sinking from masking descriptor duplication.
duplicate.close()
