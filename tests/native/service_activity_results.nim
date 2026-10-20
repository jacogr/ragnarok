# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused service activity cannot expose copied rows, source provenance or partial populations.

import std/cmdline
import ../../src/state/[service_activity, accumulation_statistics]
import ../../src/codec/state_statistics

let argument = paramStr(1)
let owner = default(PreparedServiceActivity)
let outcome = if argument == "default": default(ServiceActivityResult[PreparedServiceActivity])
  else: prepareServiceActivity(default(PreparedAccumulationStatistics), default(
      ServiceActivityConfig))
case argument
of "info": discard owner.serviceActivityInfo.value # Defaults have no observed source populations.
of "source": discard owner.serviceActivitySource.value # No fabricated finalized statistics certificate.
of "index": discard owner.serviceActivityAt(StatisticsServiceIndex(0)).value # No fabricated empty tuple.
else: discard outcome.value # Default/refused results require selected success.
