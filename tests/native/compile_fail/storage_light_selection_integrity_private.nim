# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Selected light journal metadata remains private behind guarded accessors.
# @@Verification={"group": "privacy", "expected": "integrity"}
import ../../../src/storage/light_journal_manifest
let hidden = default(LightJournalManifest)
discard hidden.integrity
