# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized availability result guards with genuine independent completed-root controls.

import std/assertions
import std/cmdline
import ../../src/state/availability_specifier as state_availability_specifier
import ../../src/state/export_erasure as state_export_erasure
import ../../src/state/erasure_words as state_erasure_words
import ../../src/codec/bounded as codec_bounded
import ../support/pvm_export_erasure
import ../support/pvm_availability_vectors

proc reset(flags: cint) {.importc: "ro_fail", cdecl.}
  ## Refuse the real primitive backend after all original source construction.
proc afterCalls(count: cint) {.importc: "ro_blake_after", cdecl.}
  ## Refuse only after real successful validator hashing to test partial-prefix cleanup.
proc check[T](outcome: AvailabilityCommitmentResult[T], reason: AvailabilityCommitmentError) =
  ## Observe the runtime alternative before deliberate failed extraction selected by a process argument.
  assert outcome.error == reason, "availability guard control"
let original = prepareExportErasure(exportBundle(0, 6), exportErasureLimits()).value
let cap = AvailabilityCommitmentLimits(bytes: ByteLimit(10000), hashBytes: ByteLimit(100000),
    hashes: ElementLimit(100))
let done = prepareAvailabilityCommitment(original, cap)
check(done, AvailabilityCommitmentError.None)
assert done.value.availabilityInfo.value.specifier.erasureRoot.bytes == EmptyRoot, "independent completed root"
let missing = default(AvailabilityCommitmentResult[AvailabilityCommitment])
let invalid = prepareAvailabilityCommitment(default(ExportErasure), cap)
check(invalid, AvailabilityCommitmentError.InvalidSource)
let limited = prepareAvailabilityCommitment(original, AvailabilityCommitmentLimits())
check(limited, AvailabilityCommitmentError.LimitExceeded)
let index = done.value.availabilityShard(ErasureShardIndex(6))
check(index, AvailabilityCommitmentError.InvalidIndex)
reset(1)
let failed = prepareAvailabilityCommitment(original, cap)
check(failed, AvailabilityCommitmentError.BackendFailure)
afterCalls(2)
let late = prepareAvailabilityCommitment(original, cap)
check(late, AvailabilityCommitmentError.BackendFailure)
reset(0)
case paramStr(1)
of "default": discard missing.value # Defaults have no completed availability specifier.
of "source": discard invalid.value # Missing source cannot invent original package/root provenance.
of "limit": discard limited.value # Aggregate refusal exposes no computed prefix.
of "backend": discard failed.value # Failed bundle hashing cannot return a root.
of "late": discard late.value # A successful validator prefix cannot become availability authority.
of "index": discard index.value # Invalid validator ordinals have no fixed commitment pair.
of "info": discard default(AvailabilityCommitment).availabilityInfo.value # Defaults have no specifier metadata.
of "owner": discard default(AvailabilityCommitment).availabilitySource.value # Defaults have no original erasure owner.
else: discard default(AvailabilityCommitment).availabilityShard(ErasureShardIndex(
    0)).value # Defaults have no fabricated hashes.
