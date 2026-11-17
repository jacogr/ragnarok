# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## An exclusive Balsa parser cannot split destruction authority over copied C++ header storage.

# @@Verification={"group":"ownership_compile","expected":"'=dup' is not available for type <Head>","build_name":"http-head-copy","rationale":"Head owns a C++ parser and copied header storage. Copying it would double-free the same foreign allocation; the native http_head suite separately proves safe explicit moves.","reference":"src/lib/http_head.nim"}
import ../../../src/lib/http_head
var original = default(Head)
var duplicate = original
original.close() # Keep both values live so lowering cannot replace the copy with a sink.
duplicate.close()
