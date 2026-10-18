# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Application code cannot forge success or mutate a read-only result accessor.
import ../../../src/codec/state_accounts
discard ServiceMetadataResult[ServiceMetadataRead](status: ServiceMetadataError.None,
    completed: default(ServiceMetadataRead))
