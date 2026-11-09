# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Immutable build identity shared by the application CLI and RPC client information.
## Make generates these constants before compilation so a shipped binary can report
## its application, compiler and specification identities without consulting the
## build environment. CLI and RPC read the same UTC build timestamp and revisions.
## See spec/application.md for build inputs and packaging overrides.

include ../build/build_info
