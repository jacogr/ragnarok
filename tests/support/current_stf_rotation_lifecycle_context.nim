# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit bounded account inventory and creation/retirement budgets for dynamic-roster lifecycle histories.
import ./current_stf_rotation_designation_context
import ../../src/app/candidate
import ../../src/codec/bounded

proc rotationLifecycleLimits*(): CurrentCandidateLimits =
  ## Sixteen complete accounts cover two originals, repeated child creation and reserved supervisor fixtures.
  result = rotationDesignationLimits()
  result.completion.composition.accounts.services = ElementLimit(16)
  result.completion.composition.accounts.metadataBytes = ByteLimit(1680)
  result.completion.composition.validators.services = ElementLimit(16)
  result.completion.composition.activity.services = ElementLimit(16)
  result.completion.execution.initial.accounts.entries = ElementLimit(512)
  result.completion.execution.initial.accounts.selection.accounts = ElementLimit(16)
  result.completion.execution.initial.accounts.creation.accounts = ElementLimit(16)
  result.completion.execution.initial.accounts.writes.accounts = ElementLimit(16)
  result.completion.execution.initial.accounts.writes.writes = ElementLimit(64)
  result.completion.execution.initial.accounts.writes.valueBytes = ByteLimit(65536)
  result.completion.execution.initial.guests.deletedAccounts = ElementLimit(1)
  result.completion.execution.execution.round.accounts = result.completion.execution.initial.accounts
  result.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(1)
