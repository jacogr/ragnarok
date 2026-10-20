# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict optimized failed-result, empty-owner and invalid-page guards with genuine positive controls.

import std/[assertions, cmdline]
import ../../src/state/[export_commitment, report_identity]
import ../support/pvm_export_commitment

proc check(outcome: ExportCommitmentResult[ExportCommitment], reason: ExportCommitmentError) =
  ## Verify real alternatives without statically specializing the deliberate runtime misuse below.
  assert outcome.error == reason
let source = zeroExportSource(3)
let success = prepareExportCommitment(source, commitmentLimits())
check(success, ExportCommitmentError.None)
assert success.value.commitmentInfo.value.pages == 1
let missing = default(ExportCommitmentResult[ExportCommitment])
check(missing, ExportCommitmentError.Uninitialized)
let invalid = prepareExportCommitment(default(ReportIdentity), commitmentLimits())
check(invalid, ExportCommitmentError.InvalidSource)
let limited = prepareExportCommitment(source, default(ExportCommitmentLimits))
check(limited, ExportCommitmentError.LimitExceeded)
case paramStr(1)
of "default": discard missing.value # Default results carry no tree owner.
of "source": discard invalid.value # Invalid provenance cannot produce a commitment.
of "limit": discard limited.value # Local refusals discard all partial preparation.
of "owner": discard default(ExportCommitment).commitmentInfo.value # Default handles carry no root.
else: discard success.value.commitmentPage(ExportPageIndex(high(
    uint64))).value # Invalid full-width page ordinals expose no proof.
