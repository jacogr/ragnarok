# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Separate unbound policy controls and actual shared-worker allocation refusal retain exact checked execution.

include ./test_pvm_runtime_policy

import ../../support/pvm_shared_async
runSharedAsyncRefusal()
