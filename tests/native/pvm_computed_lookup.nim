# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized lookup results include genuine original recent/state/admission and independent sealed-chain controls.

import std/[assertions, cmdline]
import ../../src/state/[computed_lookup, computed_recent]
import ../../src/codec/[bounded, header]
import ../support/[pvm_computed_lookup, pvm_computed_lookup_vectors]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse only after genuine source and chain fixture construction.
proc check[T](outcome: ComputedLookupResult[T], reason: ComputedLookupError) =
  ## Confirm selected alternatives before deliberate unsuccessful extraction.
  assert outcome.error == reason, "computed lookup guard control"
let fixture = lookupFixture()
let done = checkComputedLookupAnchor(fixture.source, fixture.older, lookupLimits())
check(done, ComputedLookupError.None)
assert done.value.computedLookupInfo.value.headers == 3, "complete linked ancestor control"
assert uint64(done.value.computedLookupInfo.value.anchor) == 1, "genuine original lookup match"
let missing = default(ComputedLookupResult[LookupAnchoredComputedReport])
let source = checkComputedLookupAnchor(default(RecentComputedReport), [], lookupLimits())
check(source, ComputedLookupError.InvalidSource)
let stale = lookupFixture(1)
let age = checkComputedLookupAnchor(stale.source, stale.older, lookupLimits())
check(age, ComputedLookupError.LookupTooOld)
let limited = checkComputedLookupAnchor(fixture.source, fixture.older, ComputedLookupLimits())
check(limited, ComputedLookupError.LimitExceeded)
let badHeader = checkComputedLookupAnchor(fixture.source, [default(OwnedHeader)], lookupLimits())
check(badHeader, ComputedLookupError.InvalidHeader)
let ancestry = checkComputedLookupAnchor(fixture.source, [fixture.older[1]], lookupLimits())
check(ancestry, ComputedLookupError.BrokenAncestry)
let absent = checkComputedLookupAnchor(fixture.source, [], lookupLimits())
check(absent, ComputedLookupError.MissingLookupAnchor)
let wrong = lookupFixture(5)
let root = checkComputedLookupAnchor(wrong.source, wrong.older, lookupLimits())
check(root, ComputedLookupError.WrongLookupState)
reset(1)
let backend = checkComputedLookupAnchor(fixture.source, fixture.older, lookupLimits())
check(backend, ComputedLookupError.BackendFailure)
reset(0)
case paramStr(1)
of "default": discard missing.value # Defaults contain no linked-chain owner.
of "source": discard source.value # No original admitted recent provenance.
of "age": discard age.value # Stale original lookup cannot become an accepted chain.
of "limit": discard limited.value # No partial chain after local policy refusal.
of "header": discard badHeader.value # No default ancestor owner.
of "backend": discard backend.value # No fabricated hash on backend refusal.
of "ancestry": discard ancestry.value # No skipped/forked/reordered sequence.
of "missing": discard absent.value # No history fallback for a missing ancestor pair.
of "root": discard root.value # Own prior root cannot replace the child's committed posterior root.
of "info": discard default(LookupAnchoredComputedReport).computedLookupInfo.value # Defaults have no match metadata.
of "owner": discard default(LookupAnchoredComputedReport).computedLookupSource.value # Defaults have no original source.
of "index": discard done.value.computedLookupHeader(ComputedAncestorIndex(high(
    uint64))).value # Full-width index refusal.
else: discard default(LookupAnchoredComputedReport).computedLookupHeader(ComputedAncestorIndex(
    0)).value # Defaults have no headers.
