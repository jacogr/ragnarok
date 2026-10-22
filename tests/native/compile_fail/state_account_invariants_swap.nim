# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"group": "nominal", "expected": "CheckedAccountFootprints", "early": ["joinAccountInvariants(", "[1] expected: CheckedAccountFootprints but got: CheckedPreimageContent"]}

## Content evidence cannot substitute for the dependent metadata predicate.
import ../../../src/state/[account_invariants, preimage_content, preimage_linkage]
discard joinAccountInvariants(default(CheckedPreimageContent), default(CheckedPreimageContent),
    default(CheckedPreimageLinkage))
