# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Statically known success is forbidden by the failure-only authentication result factory.
import ../../../src/state/safrole_authentication
discard safroleAuthFailure(SafroleAuthError.None)
