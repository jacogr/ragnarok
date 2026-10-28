# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed application defaults and CLI bounds shared by parsing, execution and help.

import ../pvm/backend
export backend

type
  NodeMode* {.pure.} = enum ## Complete and partial state are distinct startup modes.
    Full, Light
  StateStorage* {.pure.} = enum ## Backend selection is independent of full/light mode.
    Memory, Disk
  StateDiskLayout* {.pure.} = enum ## Physical schemas are explicitly selected, never inferred from existing files.
    Journal, Managed, Paged

const
  DefaultMcpPort* = 14141'u16                 ## Default loopback agent query endpoint.
  DefaultDataDirectory* = "./data"            ## Persistent local identity and default storage root.
  DefaultChainFile* = "./chain.json"          ## Conventional operator-supplied chain specification.
  DefaultServerTimeoutMs* = 0                 ## Zero means an interrupted foreground server has no deadline.
  DefaultNetworkPort* = 34100'u16             ## Ordinary JAM peer listener/dial port.
  DefaultDevelopmentAlpn* = "jamnp-s/1/00000000" ## Isolated development domain unless explicitly selected.
  DefaultServerMode* = "listen" ## Serve until interrupted instead of executing a bounded test workload.
  DefaultCertificateDays* = 3650              ## Persistent self-signed transport certificate lifetime.
  DefaultRpcPort* = 9418'u16                  ## Default loopback WebSocket listener port.
  DefaultUiPort* = 8418'u16                   ## Default loopback HTTP listener port.
  MaxPeerTimeoutMs* = 120000                  ## Maximum ordinary bounded peer deadline.
  MaxOffloadTimeoutMs* = 300000               ## Separate maximum for the server offload workload.
  DefaultTimeoutMs* = 10000                   ## Named peer commands use one finite default deadline.
  DefaultPeerMode* = "valid"                  ## Existing bounded peer workload without service fixture behavior.
  DefaultNodeMode* = NodeMode.Full            ## Complete-state startup remains the default mode.
  DefaultStateStorage* = StateStorage.Memory  ## Disk startup uses a mode/layout-specific path when omitted.
  DefaultStateLayout* = StateDiskLayout.Journal ## Full-state disk layout when no explicit layout is selected.
  DefaultStateWrites* = 1000'u64              ## Independent per-batch mutation-count ceiling.
  DefaultStateWriteBytes* = 100000'u64        ## Independent per-batch mutation-byte ceiling.
  DefaultFuzzWrites* = 1000'u64               ## Conformance-only write-count ceiling.
  DefaultFuzzWriteBytes* = 4194304'u64        ## Existing conformance-only byte ceiling.
  DefaultCompactionBytes* = 64'u64*1024*1024  ## Soft managed maintenance threshold.
  MaximumCompactionBytes* = 128'u64*1024*1024 ## Maximum admitted managed threshold.
  DefaultRetainedBlocks* = 8'u64 ## Default accepted block/state window, independent of protocol history.
  DefaultDownloadBlocks* = 1 ## A download requests one actual successive adoption unless overridden.
  MaxDownloadPeers* = 16                      ## Bounded catalog of primary plus additional pinned peers.
  MaxDownloadArguments* = 8+2*(MaxDownloadPeers-1) ## Internal normalized download shape, derived from the peer cap.
  MaxTraceSteps* = 256                        ## Maximum consecutive offline trace files per run.
  MaxDownloadBlocks* = 64                     ## Finite whole-command adoption cap.
  MaxDownloadAncestors* = 64                  ## Finite explicit/acquired ancestor cap.

func defaultDatabase*(directory: string, light: bool, layout: StateDiskLayout): string =
  ## Full/light and physical schemas never share an inferred database namespace.
  let base = directory & (if light: "/light/" else: "/full/")
  case layout
  of StateDiskLayout.Journal: base & "state.db"
  of StateDiskLayout.Managed: base & "managed"
  of StateDiskLayout.Paged: base & "paged"
