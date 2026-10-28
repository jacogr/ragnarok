# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused projections and invalid full-width ordinals cannot expose partial per-block activity.

import std/cmdline
import ../../src/state/core_service_activity as state_core_service_activity
import ../../src/codec/state_statistics as codec_state_statistics

let argument = paramStr(1)
let owner = default(CoreServiceActivityProjection)
let outcome = if argument == "default": default(CoreServiceActivityResult[CoreServiceActivityProjection])
  else: projectCoreServiceActivity([], [], [], [], [], default(CoreServiceActivityConfig))
case argument
of "info": discard owner.coreServiceActivityInfo.value # No fabricated initialized-empty observations.
of "core": discard owner.projectedCoreAt(StatisticsCoreIndex(0)).value # No fabricated core tuple.
of "service": discard owner.projectedServiceAt(StatisticsServiceIndex(0)).value # No fabricated service/key tuple.
of "core-index", "service-index":
  let initialized = projectCoreServiceActivity([], [], [], [], [], CoreServiceActivityConfig(
      cores: CoreCount(2))).value
  if argument == "core-index":
    discard initialized.projectedCoreAt(StatisticsCoreIndex(high(
        uint64))).value # Full-width index remains a refusal.
  else:
    discard initialized.projectedServiceAt(StatisticsServiceIndex(high(
        uint64))).value # Empty dictionary has no valid ordinal.
else: discard outcome.value # Neither default nor invalid configuration contains success.
