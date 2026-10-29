# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## A default or rejected handshake cannot expose a partial decoded payload.
# @@Verification={"group": "privacy", "expected": "completed"}
import ../../../src/quic/announcements
let outcome = default(AnnouncementResult[AnnouncementHandshake])
discard outcome.completed
