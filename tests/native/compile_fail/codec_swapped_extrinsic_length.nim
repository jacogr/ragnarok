# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Intentional rejection protects nominal work-package identities or private owner storage.
##
## Compiler-rejection fixture; compilation must fail at the attempted access or type misuse.
## Exposes no library API.

# @@Verification={"group": "nominal", "expected": "got: BundleLength but wanted: ExtrinsicLength"}

import ../../../src/codec/work_package as codec_work_package
import ../../../src/codec/work_report as codec_work_report

var value: ExtrinsicCommitment
value.length = BundleLength(1)
