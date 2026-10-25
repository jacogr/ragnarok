# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## One explicit broader input policy covers all independently authored allowance/incarnation/foreign-effect CLI cases.
import ./[current_consecutive_download_context, current_stf_guest_limits, pvm_accumulation_provision]
import ../../src/quic/current_block_download_loop
import ../../src/codec/[bounded, composite]
proc traceCheckTestPolicy*(): CurrentDownloadLoopLimits =
  ## Retain the supported current policy format; offline execution consumes its candidate limits without creating peers or callbacks.
  result = currentConsecutivePolicy()
  var limits = currentStfGuestLimits()
  limits.completion.execution.initial.accounts.creation.accounts = ElementLimit(4)
  limits.completion.execution.execution.round.accounts.creation.accounts = ElementLimit(4)
  limits.completion.execution.initial.guests.deletedAccounts = ElementLimit(1)
  limits.completion.execution.execution.round.guests.deletedAccounts = ElementLimit(1)
  limits.completion.execution.initial.guests.requestFacts = ElementLimit(4)
  limits.completion.execution.execution.round.guests.requestFacts = ElementLimit(4)
  limits.completion.execution.initial.guests.provisions = provisionPolicy(items = 1, perBlob = 512, total = 512)
  limits.completion.execution.initial.provisions.values = PreimageLimits(items: ElementLimit(1),
      perBlob: ByteLimit(512), totalBlobBytes: ByteLimit(512))
  limits.completion.execution.initial.provisions.encodedBytes = ByteLimit(1024)
  limits.completion.execution.execution.round.guests.provisions = limits.completion.execution.initial.guests.provisions
  limits.completion.execution.execution.round.provisions = limits.completion.execution.initial.provisions
  result.candidate = limits
