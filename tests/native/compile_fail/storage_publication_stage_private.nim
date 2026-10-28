# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## External callers cannot construct or access private encoded-admission authority.
# @@Verification={"group":"privacy","expected":"PublicationStage"}
import ../../../src/storage/node_repository as storage_node_repository
type Hidden = storage_node_repository.PublicationStage
discard sizeof(Hidden)
