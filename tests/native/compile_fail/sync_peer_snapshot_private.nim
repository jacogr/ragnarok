# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Callers cannot extract a retained peer view from a default or retired source snapshot.
# @@Verification={"group": "privacy", "expected": "captured"}
import ../../../src/quic/announcement_stream
let observation = default(PeerAnnouncementSnapshot)
discard observation.captured
