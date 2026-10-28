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
  DefaultRpcPort* = 19800'u16                 ## Default loopback WebSocket listener port.
  DefaultUiPort* = 8888'u16                   ## Default loopback HTTP listener port.
  MaxPeerTimeoutMs* = 120000                  ## Maximum ordinary bounded peer deadline.
  MaxOffloadTimeoutMs* = 300000               ## Separate maximum for the server offload workload.
  DefaultTimeoutMs* = 10000                   ## Named peer commands use one finite default deadline.
  DefaultPeerMode* = "valid"                  ## Existing bounded peer workload without service fixture behavior.
  DefaultNodeMode* = NodeMode.Full            ## Complete-state startup remains the default mode.
  DefaultStateStorage* = StateStorage.Memory  ## Disk startup always requires an explicit path.
  DefaultStateLayout* = StateDiskLayout.Journal ## Full-state disk layout when no explicit layout is selected.
  DefaultStateWrites* = 1000'u64              ## Independent per-batch mutation-count ceiling.
  DefaultStateWriteBytes* = 100000'u64        ## Independent per-batch mutation-byte ceiling.
  DefaultFuzzWrites* = 1000'u64               ## Conformance-only write-count ceiling.
  DefaultFuzzWriteBytes* = 4194304'u64        ## Existing conformance-only byte ceiling.
  DefaultCompactionBytes* = 64'u64*1024*1024  ## Soft managed maintenance threshold.
  MaximumCompactionBytes* = 128'u64*1024*1024 ## Maximum admitted managed threshold.
  DefaultDownloadBlocks* = 1 ## A download requests one actual successive adoption unless overridden.
  MaxDownloadPeers* = 16                      ## Bounded catalog of primary plus additional pinned peers.
  MaxDownloadArguments* = 8+2*(MaxDownloadPeers-1) ## Internal normalized download shape, derived from the peer cap.
  MaxTraceSteps* = 256                        ## Maximum consecutive offline trace files per run.
  MaxDownloadBlocks* = 64                     ## Finite whole-command adoption cap.
  MaxDownloadAncestors* = 64                  ## Finite explicit/acquired ancestor cap.
