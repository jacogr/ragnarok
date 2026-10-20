# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Strict result and explicit-close contracts use actual initialized native endpoints as positive controls.

import std/[cmdline, assertions]
import ../../src/quic/[block_download_peers, block_download_session]
import ../../src/app/download_schedule
import ../../src/codec/bounded

proc lifecycle(mode: string) =
  ## The native provider prepares fresh identities before this driver is linked/executed.
  var catalog = default(BlockDownloadPeers)
  assert catalog.configure(ElementLimit(1)) == DownloadPeerError.None
  let key = DownloadPeerKey(default(array[32, byte]))
  let opened = catalog.openPeer(DownloadPeerId(1), key, 1,
    "build/quic/nimony-fixtures/a.cert.pem", "build/quic/nimony-fixtures/a.key.pem", "jamnp-s/1/00000000")
  assert opened == DownloadPeerError.None
  if mode == "positive": catalog.close() # A real endpoint's valid explicit retirement must exit successfully.
  # The unclosed alternative deliberately reaches the destructor with actual retained native resources.

let mode = paramStr(1)
if mode in ["unclosed", "positive"]:
  lifecycle(mode)
else:
  var catalog = default(BlockDownloadPeers)
  let outcome = if mode == "default": default(DownloadPeerResult[DownloadSessionFailure])
    else: catalog.bindingFailure(DownloadPeerId(99))
  discard outcome.value # Defaults and missing peers expose no selected child.
