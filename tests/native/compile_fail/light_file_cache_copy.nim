# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Light file cache duplication must fail actual native lowering.
# @@Verification={"group":"ownership_compile","build_name":"light-file-cache-copy","expected":"'=dup' is not available for type <LightFileCache>"}
import ../../../src/storage/light_file_cache
proc duplicated(source: LightFileCache): LightFileCache =
  ## A borrowed append owner cannot acquire another retirement authority.
  source
var first = default(LightFileCache)
var second = duplicated(first)
discard first.opened
discard second.close
