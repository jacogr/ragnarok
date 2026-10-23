# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## The appended continuation reason is guarded; healthy default-policy observation remains available without opening workers or storage.
import std/[assertions, cmdline]
import ../../src/app/current_logical_download
import ../../src/state/[accumulation_current_update, current_logical]
let outcome = default(CurrentLogicalDownloadResult)
if paramStr(1) == "reason":
  discard outcome.continuationFailure # Default result cannot expose an unrelated source-bound namespace refusal.
else:
  let policy = default(CurrentLogicalDownloadPolicy)
  assert qualifyCurrentDownload(policy, default(PreparedCurrentChainUpdate)).error ==
      CurrentLogicalDownloadError.InvalidPolicy
  let continued = continueCurrentLogicalDownloadPolicy(policy, default(CurrentLogicalState))
  assert qualifyCurrentDownload(continued, default(PreparedCurrentChainUpdate)).error ==
      CurrentLogicalDownloadError.InvalidPolicy
