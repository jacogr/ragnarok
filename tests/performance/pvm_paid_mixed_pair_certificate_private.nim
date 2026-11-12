# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reuse the maintained source and paid-continuation cases for private native qualification.

import std/syncio
import ../support/pvm_mixed_loop_source

runMixedLoopSource()
runPaidMixedLoopSource(true)
echo "MIXED_PAID_CERTIFICATE_OK"
