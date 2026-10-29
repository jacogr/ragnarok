# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Journal lease duplication must fail actual native lowering.
# @@Verification={"group":"ownership_compile","build_name":"managed-journal-copy","expected":"'=dup' is not available for type <ManagedJournal>"}
import ../../../src/storage/managed/io as managed_io
proc duplicated(source: ManagedJournal): ManagedJournal =
  ## A borrowed append owner cannot acquire another retirement authority.
  source
var first = default(ManagedJournal)
var second = duplicated(first)
discard first.opened
discard second.close
