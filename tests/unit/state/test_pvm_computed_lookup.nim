# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "pvm_computed_lookup_arc_release"}

## Original age/chain/root correspondence, bounded work, late faults and immutable retained ancestry.

import std/[assertions, syncio]
import ../../../src/state/[computed_lookup, computed_recent]
import ../../../src/codec/[bounded, header]
import ../../support/[pvm_computed_lookup, pvm_computed_lookup_vectors, arc_evidence]

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Reset primitive observations only after genuine source/chain preparation.
proc after(successful: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse a real hash after a known completed prefix, including the final supplied suffix.
proc hashes(): cint {.importc: "ro_blake_calls", cdecl.}
  ## Observe all attempted real Blake calls without fabricating a successful digest.
proc expect[T](outcome: ComputedLookupResult[T], reason: ComputedLookupError) =
  ## Inspect selected reasons before any guarded payload extraction.
  if outcome.error != reason:
    echo "computed lookup actual=", ord(outcome.error), " expected=", ord(reason)
  assert outcome.error == reason, "computed lookup reason"
let fixture = lookupFixture()
let exact = ComputedLookupLimits(headers: ElementLimit(3), headerBytes: ByteLimit(297),
    bytes: ByteLimit(891))
reset(0)
let done = checkComputedLookupAnchor(fixture.source, fixture.older, exact).value
assert hashes() == 3, "one full sealed hash per retained header"
let info = done.computedLookupInfo.value
assert info.headers == 3 and info.bytes == 891, "exact parent plus two older full-header extents"
assert uint64(info.anchor) == 1, "original lookup matches immediate older ancestor"
assert uint32(headerInfo(done.computedLookupHeader(ComputedAncestorIndex(
    0)).value).value.unsigned.slot) == 20, "exact admitted parent endpoint"
assert uint32(headerInfo(done.computedLookupHeader(info.anchor).value).value.unsigned.slot) == 19, "exact original lookup slot"
assert array[32, byte](headerInfo(done.computedLookupHeader(ComputedAncestorIndex(
    0)).value).value.unsigned.priorState)[0] == 8, "child commits lookup posterior root"
assert array[32, byte](headerInfo(done.computedLookupHeader(
    info.anchor).value).value.unsigned.priorState)[0] == 7, "lookup own prior root differs"
assert uint32(done.computedLookupSource.value.computedRecentAnchor.value.slot) == 20, "exact original recent source retained"
# A sufficient prefix containing both lookup and child is accepted; missing the lookup itself is not.
expect(checkComputedLookupAnchor(fixture.source, [fixture.older[0]], exact),
    ComputedLookupError.None)
expect(checkComputedLookupAnchor(fixture.source, [], exact),
    ComputedLookupError.MissingLookupAnchor)
expect(checkComputedLookupAnchor(fixture.source, [fixture.older[1]], exact),
    ComputedLookupError.BrokenAncestry)
expect(checkComputedLookupAnchor(fixture.source, [fixture.older[1], fixture.older[0]], exact),
    ComputedLookupError.BrokenAncestry)
expect(checkComputedLookupAnchor(fixture.source, [fixture.older[0], fixture.older[0]], exact),
    ComputedLookupError.BrokenAncestry)
expect(checkComputedLookupAnchor(fixture.source, [default(OwnedHeader)], exact),
    ComputedLookupError.InvalidHeader)
let fork = alteredLookupHeader(fixture.older[0], 201, 44)
expect(checkComputedLookupAnchor(fixture.source, [fork], exact), ComputedLookupError.BrokenAncestry)
let suffix = alteredLookupHeader(fixture.older[1], 201, 44)
let rejected = @[fixture.older[0], suffix]
expect(checkComputedLookupAnchor(fixture.source, rejected, exact),
    ComputedLookupError.BrokenAncestry)
let stale = lookupFixture(1)
let saturated = lookupFixture(2)
let ownRoot = lookupFixture(5)
let endpoint = lookupFixture(6)
let oldest = lookupFixture(7)
let equalSlots = lookupFixture(9)
expect(checkComputedLookupAnchor(saturated.source, saturated.older, exact),
    ComputedLookupError.None)
expect(checkComputedLookupAnchor(ownRoot.source, ownRoot.older, exact),
    ComputedLookupError.WrongLookupState)
expect(checkComputedLookupAnchor(endpoint.source, endpoint.older, exact),
    ComputedLookupError.MissingLookupAnchor)
let last = checkComputedLookupAnchor(oldest.source, oldest.older, exact).value
assert uint64(last.computedLookupInfo.value.anchor) == 2, "oldest retained lookup uses immediate newer child"
expect(checkComputedLookupAnchor(equalSlots.source, equalSlots.older, exact),
    ComputedLookupError.BrokenAncestry)
for mode in [3, 4, 8]:
  let missing = lookupFixture(mode)
  expect(checkComputedLookupAnchor(missing.source, missing.older, exact),
      ComputedLookupError.MissingLookupAnchor)
# Count and encoded-byte policies include the admitted parent, and fail before any primitive attempt.
var countShort = exact
countShort.headers = ElementLimit(2)
var byteShort = exact
byteShort.bytes = ByteLimit(890)
var headerShort = exact
headerShort.headerBytes = ByteLimit(296)
reset(1)
expect(checkComputedLookupAnchor(stale.source, [default(OwnedHeader)], ComputedLookupLimits()),
    ComputedLookupError.LookupTooOld)
expect(checkComputedLookupAnchor(fixture.source, fixture.older, countShort),
    ComputedLookupError.LimitExceeded)
expect(checkComputedLookupAnchor(fixture.source, fixture.older, byteShort),
    ComputedLookupError.LimitExceeded)
expect(checkComputedLookupAnchor(fixture.source, fixture.older, headerShort),
    ComputedLookupError.LimitExceeded)
expect(checkComputedLookupAnchor(default(RecentComputedReport), [], exact),
    ComputedLookupError.InvalidSource)
assert hashes() == 0, "source/age/policy preflight before hashing"
expect(checkComputedLookupAnchor(fixture.source, fixture.older, exact),
    ComputedLookupError.BackendFailure)
assert hashes() == 1, "first backend refusal exposes no partial chain"
after(2)
expect(checkComputedLookupAnchor(fixture.source, fixture.older, exact),
    ComputedLookupError.BackendFailure)
assert hashes() == 3, "late backend failure after matching prefix still rejects whole supplied chain"
assert done.computedLookupInfo.value.bytes == 891, "prior successful owner survives later backend refusal"
reset(0)
expect(checkComputedLookupAnchor(fixture.source, fixture.older, exact), ComputedLookupError.None)
assert hashes() == 3, "backend retry hashes every full header"
expect(default(ComputedLookupResult[LookupAnchoredComputedReport]),
    ComputedLookupError.Uninitialized)
expect(default(LookupAnchoredComputedReport).computedLookupInfo, ComputedLookupError.Uninitialized)
expect(default(LookupAnchoredComputedReport).computedLookupSource,
    ComputedLookupError.Uninitialized)
expect(default(LookupAnchoredComputedReport).computedLookupHeader(ComputedAncestorIndex(0)),
    ComputedLookupError.Uninitialized)
expect(done.computedLookupHeader(ComputedAncestorIndex(3)), ComputedLookupError.InvalidIndex)
expect(done.computedLookupHeader(ComputedAncestorIndex(high(uint64))),
    ComputedLookupError.InvalidIndex)
var supplied = fixture.older
supplied[0] = default(OwnedHeader)
var copy = lookupWire(done.computedLookupHeader(info.anchor).value)
copy[201] = 99
var changed = done.computedLookupInfo.value
changed.headers = 0
assert lookupWire(done.computedLookupHeader(info.anchor).value) == lookupWire(fixture.older[0]), "caller list/wire copies cannot change retained ancestry"
assert done.computedLookupInfo.value.headers == 3, "info copy isolation"
proc detached(): LookupAnchoredComputedReport =
  ## Retain original recent/state/report provenance and recaptured chain after every fixture local retires.
  let fixture = lookupFixture()
  checkComputedLookupAnchor(fixture.source, fixture.older, lookupLimits()).value
let retained = detached()
assert uint32(retained.computedLookupSource.value.computedRecentAnchor.value.slot) == 20, "detached source lifetime"
assert uint32(headerInfo(retained.computedLookupHeader(
    retained.computedLookupInfo.value.anchor).value).value.unsigned.slot) == 19, "detached header lifetime"
proc cycle(policy: ComputedLookupLimits) =
  ## Release complete recaptured chains and late backend/ancestry failures in each warmed iteration.
  reset(0)
  let value = checkComputedLookupAnchor(fixture.source, fixture.older, policy).value
  assert value.computedLookupInfo.value.headers == 3
  discard value.computedLookupSource.value
  discard value.computedLookupHeader(ComputedAncestorIndex(2)).value
  expect(checkComputedLookupAnchor(fixture.source, rejected, policy),
      ComputedLookupError.BrokenAncestry)
  after(2)
  expect(checkComputedLookupAnchor(fixture.source, fixture.older, policy),
      ComputedLookupError.BackendFailure)
  reset(0)
cycle(exact)
let before = getOccupiedMem()
for iteration in 0..<1000: cycle(exact)
let afterRelease = getOccupiedMem()
assert before == afterRelease, "computed lookup ARC release"
recordArcRelease("pvm_computed_lookup", 1000, before, afterRelease)
echo "PVM computed lookup passed"
echo "ARC_RELEASE cycles=1000 unchanged"
