# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable build identity shared by the application CLI and RPC client information.
## Make generates application labels/revisions and the verified nightly identity before compilation.
## Exposes AppVersion, AppRevision, CompilerVersion, CompilerRevision and BuildTimestamp constants.

include ../../build/build_info
