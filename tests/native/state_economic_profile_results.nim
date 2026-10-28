# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Dynamic selected-profile payload guards retain genuine valid parameter selection as a control.
import std/assertions
import std/cmdline
import std/syncio
import ../support/state_economic_profile_context
import ../../src/chain/parameters as chain_parameters
import ../../src/state/economic_profile as state_economic_profile
proc extract(outcome: EconomicProfileResult[StateEconomicProfile]): StateEconomicProfile {.noinline.} =
  ## Default and invalid parameter capture cannot expose selected economic policy.
  outcome.value
case paramStr(1)
of "default": discard extract(default(EconomicProfileResult[StateEconomicProfile])) # No default profile.
of "invalid": discard extract(captureEconomicProfile(default(Parameters))) # Actual invalid input.
of "ok":
  let selected = extract(captureEconomicProfile(decodeParameters(economicTestWire()).value))
  assert selected.economicParameters.value.valid
  echo "state-economic-profile-results: ok"
else: quit(2) # Unknown selectors cannot pass controls.
