# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A prepared value set is not a prior-admitted extrinsic certificate.

import ../../../src/state/[preimages, store]
import ../../../src/codec/header
var state: StateStore
var plan: PreparedPreimageValues
discard integratePreimages(state, plan, HeaderSlot(0))
