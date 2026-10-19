# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects nominal work-package identities or private owner storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

## Verification: {"group": "nominal", "expected": "got: ValidatorIndex but wanted: ImportIndex"}

import ../../../src/codec/[work_package, assurances]

var value: ImportReference
value.index = ValidatorIndex(1)
