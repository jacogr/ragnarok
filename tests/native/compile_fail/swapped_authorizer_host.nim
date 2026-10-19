# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects nominal work-package identities or private owner storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: ServiceIndex but wanted: AuthorizerHost"}

import ../../../src/codec/[work_package, composite]

var value: WorkPackage
value.host = ServiceIndex(1)
