# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default current native results cannot expose successful payloads or unrelated nested failure alternatives.
import std/cmdline
import "../../src/jamnp-s/current/block/download/session" as current_block_download_session
import "../../src/jamnp-s/current/block/download/peers" as current_block_download_peers
let outcome = default(CurrentDownloadSessionResult[uint64])
let reason = outcome.failure
case paramStr(1)
of "schedule": discard reason.scheduleError # Default is not scheduler refusal.
of "download": discard reason.downloadFailure # Default contains no current receiver child.
of "stream": discard reason.streamError # Default contains no native binding error.
of "peer":
  let peerOutcome = default(CurrentDownloadPeerResult[uint64])
  discard peerOutcome.value # The generic result guard is independent of successful payload representation.
else: discard outcome.value # Default session extraction cannot grant a current attempt.
