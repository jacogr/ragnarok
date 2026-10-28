# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Reject composition result forgery, source replacement and mixed independent retention domains.

# @@Verification={"group": "nominal", "expected": "AuthorizationInvocation", "early": ["prepareAuthorizedRefinement(", "[1] expected: AuthorizationInvocation but got: RefinedPackage"]}

import ../../../src/state/authorized_refinement as state_authorized_refinement
import ../../../src/state/refinement_report as state_refinement_report
import ../../../src/state/refinement_dispatch as state_refinement_dispatch
discard prepareAuthorizedRefinement(default(RefinedPackage), default(RefinementInputs), default(AuthorizedRefinementLimits))
