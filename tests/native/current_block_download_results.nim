# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current results and unrelated selected failure payloads never grant successful authority.
import std/cmdline
import "../../src/app/current/block/download" as current_block_download
import "../../src/app/current/block/input" as current_block_input
import ../../src/app/[chain, candidate]
let argument = paramStr(1)
var download = default(CurrentBlockDownload)
let missing = default(ApplicationChain)
let outcome = if argument == "default": default(CurrentBlockDownloadResult[CurrentBlockDownloadId])
  else: download.begin(missing, [], default(CurrentBlockInputLimits), default(
      CurrentCandidateLimits))
case argument
of "owner": discard download.failure # Idle reception has no retained failure owner.
of "input": discard outcome.failure.inputError # Missing head is not input-admission failure.
of "preparation": discard outcome.failure.preparationFailure # Missing head carries no execution prefix.
of "worker": discard outcome.failure.workerError # No worker admission occurred.
of "handoff": discard outcome.failure.handoffError # No current handoff admission occurred.
else: discard outcome.value # Neither default nor missing-head admission grants a callback generation.
