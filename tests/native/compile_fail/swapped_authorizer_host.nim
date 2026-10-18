# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects nominal work-package identities or private owner storage.
import ../../../src/codec/[work_package, composite]

var value: WorkPackage
value.host = ServiceIndex(1)
