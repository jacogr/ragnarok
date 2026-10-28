# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused core activity cannot expose copied rows, source provenance or partial populations.

import std/cmdline
import ../../src/state/core_activity as state_core_activity
import ../../src/state/report_admission as state_report_admission
import ../../src/codec/state_statistics as codec_state_statistics

let argument = paramStr(1)
let owner = default(PreparedCoreActivity)
let outcome = if argument == "default": default(CoreActivityResult[PreparedCoreActivity])
  else: prepareCoreActivity(default(AdmittedReports), default(
      CoreActivityConfig))
case argument
of "info": discard owner.coreActivityInfo.value # Defaults have no observed source populations.
of "source": discard owner.coreActivitySource.value # No fabricated report-admission certificate.
of "index": discard owner.coreActivityAt(StatisticsCoreIndex(0)).value # No fabricated empty tuple.
else: discard outcome.value # Default/refused results require selected success.
