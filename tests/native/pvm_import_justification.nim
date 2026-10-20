# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized failed-result and missing-owner guards retain real successful proof controls.

import std/[assertions, cmdline]
import ../../src/state/import_justification
import ../../src/codec/[work_package, work_report]
import ../support/[pvm_import_justification, pvm_import_vectors]

proc check(outcome: ImportJustificationResult[VerifiedImport], reason: ImportJustificationError) =
  ## Confirm alternatives without statically specializing later deliberate runtime misuse.
  assert outcome.error == reason
let success = verifyImportSegment(SegmentRoot(bytes: SingletonRoot), ImportIndex(0), importSegment(
  ), [], importLimits())
check(success, ImportJustificationError.None)
assert success.value.verifiedImportProof.value == @[0'u8]
let missing = default(ImportJustificationResult[VerifiedImport])
check(missing, ImportJustificationError.Uninitialized)
let mismatched = verifyImportSegment(SegmentRoot(), ImportIndex(0), importSegment(), [],
    importLimits())
check(mismatched, ImportJustificationError.RootMismatch)
let indexed = verifyImportSegment(SegmentRoot(), ImportIndex(high(uint16)), importSegment(), [],
    importLimits())
check(indexed, ImportJustificationError.InvalidIndex)
let limited = verifyImportSegment(SegmentRoot(bytes: SingletonRoot), ImportIndex(0), importSegment(
  ), [], default(ImportJustificationLimits))
check(limited, ImportJustificationError.LimitExceeded)
case paramStr(1)
of "default": discard missing.value # Defaults cannot expose a verified leaf.
of "mismatch": discard mismatched.value # Failed root equality carries no authenticated payload.
of "index": discard indexed.value # Unrepresentable leaf ordinals expose no proof prefix.
of "limit": discard limited.value # Local hashing/copy refusal exposes no partial owner.
of "owner": discard default(VerifiedImport).verifiedImportInfo.value # Default handles have no nominal source facts.
else: discard default(VerifiedImport).verifiedImportProof.value # Default handles have no encoded path.
