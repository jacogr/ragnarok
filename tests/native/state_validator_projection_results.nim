# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default projections and refused results cannot expose rows, populations or partial epochs.

import std/cmdline
import ../../src/state/validator_projection as state_validator_projection
import ../../src/codec/state_statistics as codec_state_statistics
import ../../src/codec/state_safrole as codec_state_safrole

let argument = paramStr(1)
let owner = default(ValidatorActivityProjection)
let outcome = if argument == "default": default(ValidatorActivityResult[ValidatorActivityProjection])
  else: projectValidatorActivity(default(ActivitySnapshot), default(ValidatorStateSnapshot),
    default(ValidatorActivityObservations), [], [], default(ValidatorActivityLimits))
case argument
of "info": discard owner.validatorActivityInfo.value # No fabricated epoch decision from default owners.
of "row": discard owner.projectedValidatorAt(StatisticsEpoch.Current,
  StatisticsValidatorIndex(0)).value # No fabricated zero counter tuple from default owners.
else: discard outcome.value # Neither default nor failed observation validation carries success.
