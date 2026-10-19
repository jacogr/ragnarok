# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "AdmittedPreimages", "early": ["integratePreimages(", "[2] expected: AdmittedPreimages but got: PreparedPreimageValues"]}

## A prepared value set is not a prior-admitted extrinsic certificate.

import ../../../src/state/[preimages, store]
import ../../../src/codec/header
var state: StateStore
var plan: PreparedPreimageValues
discard integratePreimages(state, plan, HeaderSlot(0))
