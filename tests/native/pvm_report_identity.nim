# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized guards pair genuine successes with failed/default result and owner misuse.

import std/[assertions, cmdline]
import ../../src/state/report/identity as report_identity
import ../../src/state/authorized_refinement
import ../../src/codec/work/package as work_package
import ../support/pvm_report_identity

proc check(outcome: ReportIdentityResult[ReportIdentity], reason: ReportIdentityError) =
  ## Verify real alternatives without statically specializing the later deliberate runtime misuse.
  assert outcome.error == reason
let source = identityFixture([@[packageImport(identityKey(1), ImportIndex(0))]])
let success = prepareReportIdentity(source, [identityPair(1)], identityLimits())
check(success, ReportIdentityError.None)
assert success.value.identityInfo.value.lookupCount == 1
let missing = default(ReportIdentityResult[ReportIdentity])
check(missing, ReportIdentityError.Uninitialized)
let invalid = prepareReportIdentity(default(AuthorizedRefinement), [], identityLimits())
check(invalid, ReportIdentityError.InvalidSource)
let lookup = prepareReportIdentity(source, [], identityLimits())
check(lookup, ReportIdentityError.InvalidLookup)
let limited = prepareReportIdentity(source, [identityPair(1)], default(ReportIdentityLimits))
check(limited, ReportIdentityError.LimitExceeded)
case paramStr(1)
of "default": discard missing.value # Default variants have no identity payload.
of "source": discard invalid.value # A detached/absent source cannot yield report identity.
of "lookup": discard lookup.value # Wrong key sets expose no prefix.
of "limit": discard limited.value # Hash-copy refusal exposes no partial owner.
else: discard default(ReportIdentity).identityInfo.value # Missing owners contain no copied metadata.
