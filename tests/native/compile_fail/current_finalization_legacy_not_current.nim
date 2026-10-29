# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0
# @@Verification={"group": "nominal", "expected": "expected: PreparedCurrentAccumulationAccounts but got: PreparedAccumulationAccounts", "early": ["prepareCurrentAccumulationFinalization(", "[1] expected: PreparedCurrentAccumulationAccounts but got: PreparedAccumulationAccounts"]}

## Current timestamp provenance cannot be replaced with another completion domain.
import ../../../src/state/accumulation/current/finalization as accumulation_current_finalization
import ../../../src/state/accumulation/accounts as accumulation_accounts
discard prepareCurrentAccumulationFinalization(default(PreparedAccumulationAccounts), default(CurrentAccumulationFinalizationConfig))
