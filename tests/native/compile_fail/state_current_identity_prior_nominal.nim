# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A completed logical source cannot bypass actual next-update preservation before prior-origin extraction.
# @@Verification={"group":"nominal","expected":"PreservedCurrentIdentities","early":["identityPriorCurrent(","[1] expected: PreservedCurrentIdentities but got: CurrentLogicalState"]}
import ../../../src/state/current_identities as state_current_identities
import ../../../src/state/current_logical as state_current_logical
discard identityPriorCurrent(default(CurrentLogicalState))
