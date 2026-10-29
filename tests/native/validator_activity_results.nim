# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused validator activity cannot expose copied rows, source provenance or partial populations.

import std/cmdline
import ../../src/state/validator/activity as validator_activity
import ../../src/state/report/admission as report_admission
import ../../src/codec/state/statistics as state_statistics

let argument = paramStr(1)
let owner = default(PreparedValidatorActivity)
let outcome = if argument == "default": default(ValidatorActivityResult[PreparedValidatorActivity])
  else: prepareValidatorActivity(default(AdmittedReports), default(
      ValidatorActivityConfig))
case argument
of "info": discard owner.validatorActivityInfo.value # Defaults have no observed source populations.
of "source": discard owner.validatorActivitySource.value # No fabricated report-admission certificate.
of "index": discard owner.validatorActivityAt(StatisticsEpoch.Current, StatisticsValidatorIndex(
    0)).value # No fabricated empty tuple.
else: discard outcome.value # Default/refused results require selected success.
