# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CheckedAccountFootprints", "early": ["joinAccountInvariants(", "[1] expected: CheckedAccountFootprints but got: CheckedPreimageContent"]}

## Content evidence cannot substitute for the dependent metadata predicate.
import ../../../src/state/account_invariants as state_account_invariants
import ../../../src/state/preimage_content as state_preimage_content
import ../../../src/state/preimage_linkage as state_preimage_linkage
discard joinAccountInvariants(default(CheckedPreimageContent), default(CheckedPreimageContent),
    default(CheckedPreimageLinkage))
