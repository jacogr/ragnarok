# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Private policy alternatives enforce actual runtime extraction contracts, including genuine successful control.

import std/cmdline
import std/assertions
import ../../src/app/current_download_policy as app_current_download_policy
import ../../src/quic/current_block_download_loop as quic_current_block_download_loop
import ../../src/quic/current_block_download_stream as quic_current_block_download_stream
import ../../src/app/download_schedule as app_download_schedule
import ../../src/codec/bounded as codec_bounded

proc admitted(): CurrentDownloadPolicyResult =
  ## Explicit outer budgets permit a complete policy snapshot without certifying later stage semantics.
  var policy = default(CurrentDownloadLoopLimits)
  policy.schedule = DownloadScheduleLimits(peers: ElementLimit(1), attempts: 1,
    retryDelay: DownloadRetryDelay(1))
  policy.input.blockBytes = ByteLimit(1)
  policy.stream = CurrentDownloadStreamLimits(readBytes: ByteLimit(1), writeBytes: ByteLimit(1),
    timeout: CurrentDownloadTimeout(1))
  policy.attemptTimeout = CurrentDownloadAttemptTimeout(1)
  result = decodeCurrentDownloadPolicy(encodeCurrentDownloadPolicy(policy))
  assert result.error == CurrentDownloadPolicyError.None

let mode = paramStr(1)
case mode
of "positive", "success-field":
  let good = admitted()
  if mode == "positive": discard good.value.schedule.attempts # Real success is extractable without mutable snapshot access.
  else: discard good.fieldName # Successful results contain no failed-field alternative.
of "refused":
  let refused = decodeCurrentDownloadPolicy("not a v1 policy")
  discard refused.value # A failed parse never exposes partially assigned policy values.
else:
  let outcome = default(CurrentDownloadPolicyResult)
  discard outcome.value # Default construction cannot grant startup authority.
