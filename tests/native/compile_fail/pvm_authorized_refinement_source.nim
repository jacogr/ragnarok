# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject composition result forgery, source replacement and mixed independent retention domains.

# @@Verification={"group": "nominal", "expected": "AuthorizationInvocation", "early": ["prepareAuthorizedRefinement(", "[1] expected: AuthorizationInvocation but got: RefinedPackage"]}

import ../../../src/state/authorized_refinement
import ../../../src/state/refinement/[report as refinement_report, dispatch as refinement_dispatch]
discard prepareAuthorizedRefinement(default(RefinedPackage), default(RefinementInputs), default(AuthorizedRefinementLimits))
