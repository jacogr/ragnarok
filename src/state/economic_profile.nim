# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit immutable valid parameter snapshots bind deposit rates without selecting a network or trusted root.
## Existing parameter validity remains its documented population/clock subset, not full protocol configuration validation.
import ../chain/parameters as chain_parameters
import ../codec/state_accounts as codec_state_accounts
import ./account_deposit as state_account_deposit

type
  StateEconomicProfile* = object ## Private fixed parameter snapshot prevents default zero rates from posing as selected valid configuration.
    parameters: Parameters
    schedule: AccountDepositSchedule
  EconomicProfileError* {.pure.} = enum ## Default owners and invalid input parameters grant no usable selected schedule.
    Uninitialized, None, InvalidParameters
  EconomicProfileResult*[T] = object ## Success-only immutable profile extraction preserves existing parameter validation boundaries.
    case status: EconomicProfileError
    of None:
      completed: T
    else:
      discard
func error*[T](outcome: EconomicProfileResult[T]): EconomicProfileError =
  ## Inspect the immutable selection alternative.
  outcome.status
func value*[T](outcome: EconomicProfileResult[T]): T {.inline,
    requires: outcome.status == EconomicProfileError.None.} =
  ## Default/failed capture exposes no selected parameter or rate snapshot.
  outcome.completed
func captureEconomicProfile*(parameters: Parameters): EconomicProfileResult[StateEconomicProfile] =
  ## Copy the existing valid fixed snapshot and its exact three deposit fields; never substitute defaults.
  if not parameters.valid:
    return EconomicProfileResult[StateEconomicProfile](
        status: EconomicProfileError.InvalidParameters) # Existing validity is mandatory before reading selected rates.
  EconomicProfileResult[StateEconomicProfile](status: EconomicProfileError.None,
    completed: StateEconomicProfile(parameters: parameters,
      schedule: AccountDepositSchedule(base: AccountBalance(parameters.get(depositPerAccount)),
        item: AccountBalance(parameters.get(depositPerItem)), octet: AccountBalance(parameters.get(
            depositPerByte)))))
func economicParameters*(profile: StateEconomicProfile): EconomicProfileResult[Parameters] =
  ## Copy the exact originally selected parameter snapshot, retaining no caller byte buffer.
  if not profile.parameters.valid:
    return EconomicProfileResult[Parameters](status: EconomicProfileError.Uninitialized) # Default profiles are invalid.
  EconomicProfileResult[Parameters](status: EconomicProfileError.None,
      completed: profile.parameters)
func economicSchedule*(profile: StateEconomicProfile): EconomicProfileResult[
    AccountDepositSchedule] =
  ## Copy the selected rates only from an initialized valid parameter profile.
  if not profile.parameters.valid:
    return EconomicProfileResult[AccountDepositSchedule](
        status: EconomicProfileError.Uninitialized) # Default rates grant no selected configuration.
  EconomicProfileResult[AccountDepositSchedule](status: EconomicProfileError.None,
      completed: profile.schedule)
proc sameEconomicProfile*(left, right: StateEconomicProfile): bool =
  ## Fixed-value parameter equality requires initialization and all fields, not just matching deposit rates.
  if not left.parameters.valid or not right.parameters.valid:
    return false # Defaults never compare as selected usable configuration.
  sameParameterProfile(left.parameters, right.parameters)
