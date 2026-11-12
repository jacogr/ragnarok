# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A stream lease owns mutable block metadata even in interpreter-only builds.

# @@Verification={"group":"ownership_compile","build_name":"pvm-stream-catalogue-copy","expected":"'=dup' is not available for type <FlatStream>","rationale":"Copying an interpreter-only stream would share its privately mutable catalogue across independent frame leases, allowing a later block admission to mutate both owners.","reference":"src/pvm/internal/handler_stream.nim"}

import std/syncio
import ../../../src/pvm/internal/handler_stream

var first = default(FlatStream)
var second = first
# Both leases remain live, so the assignment must duplicate rather than move the catalogue capability.
echo streamNodes(first), " ", streamNodes(second)
