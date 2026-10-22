# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Independently encoded parameter fields prove exact rate selection, full snapshot equality and detached fixed ownership.
import std/[assertions, syncio]
import ../../support/economic_profile_context
import ../../../src/chain/parameters
import ../../../src/state/economic_profile
import ../../../src/codec/state_accounts
var wire = economicTestWire()
let selectedParameters = decodeParameters(wire).value
let result = captureEconomicProfile(selectedParameters)
assert result.error == EconomicProfileError.None
let profile = result.value
let rates = profile.economicSchedule.value
assert uint64(rates.base) == 100 and uint64(rates.item) == 2 and uint64(rates.octet) == 3
assert encodeParameters(profile.economicParameters.value) == wire
assert sameEconomicProfile(profile, profile)
assert sameEconomicProfile(profile, captureEconomicProfile(decodeParameters(wire).value).value)
wire[26] = 1
let other = captureEconomicProfile(decodeParameters(wire).value).value
assert not sameEconomicProfile(profile, other)
assert uint64(other.economicSchedule.value.base) == 100
wire[16] = 101
assert not sameEconomicProfile(profile, captureEconomicProfile(decodeParameters(wire).value).value)
wire = default(array[ParameterBytes, byte])
assert uint64(profile.economicSchedule.value.base) == 100
assert captureEconomicProfile(default(Parameters)).error == EconomicProfileError.InvalidParameters
assert default(StateEconomicProfile).economicParameters.error == EconomicProfileError.Uninitialized
assert default(StateEconomicProfile).economicSchedule.error == EconomicProfileError.Uninitialized
assert not sameEconomicProfile(default(StateEconomicProfile), default(StateEconomicProfile))
let zero = captureEconomicProfile(decodeParameters(economicTestWire(0, 0, 0)).value).value
assert uint64(zero.economicSchedule.value.base) == 0
let maximum = captureEconomicProfile(decodeParameters(economicTestWire(high(uint64), high(uint64),
    high(uint64))).value).value
assert uint64(maximum.economicSchedule.value.item) == high(uint64)
var copied = profile.economicSchedule.value
copied.base = AccountBalance(0)
assert uint64(profile.economicSchedule.value.base) == 100
echo "state-economic-profile: ok"
