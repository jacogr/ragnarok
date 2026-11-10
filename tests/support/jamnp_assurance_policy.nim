# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit test-owned complete assurance startup settings use a genuine source profile; no production budget defaults are imported or inferred.

import ../../src/app/[node_assurance_policy]
import ../../src/app/proof/assurance_acquisition
import ../../src/jamnp-s/[assurance_duty, assurance_possession, availability_proof, availability_read]
import ../../src/chain/[genesis, parameters]
import ../../src/codec/bounded
import ./jamnp_topology_fixture

proc assuranceSettings*(source: BlockSnapshot, mode = 1'u64): NodeAssuranceSettings =
  ## Finite independent controls are literal test policy; only actual immutable chain dimensions supply profile identity.
  NodeAssuranceSettings(mode: mode, startupMs: 10000,
    period: source.chainParameters.get(slotPeriodSec),
    topology: topologyLimits(int(uint64(source.cores)), int(uint64(source.epochSlots))),
    duty: AssuranceDutyLimits(chapterBytes: ByteLimit(1000000), readBytes: ByteLimit(4000000),
      reports: ElementLimit(341), requests: ElementLimit(341*1023)),
    proof: AvailabilityMerkleLimits(bytes: ByteLimit(64000000), hashes: ElementLimit(100000),
      hashBytes: ByteLimit(64000000)),
    storeEntries: 16, storeScanEntries: 400, storeBytes: 64000000, recordBytes: 16000000,
    acquisition: AssuranceAcquisitionLimits(wireBytes: ByteLimit(16000000),
        workspaceBytes: ByteLimit(128000000)),
    acquisitionRequests: 1023, acquisitionDials: 1023, acquisitionBytes: 64000000,
    acquisitionPeerMs: 1000, acquisitionJobMs: 2000, acquisitionRoundMs: 6000,
    acquisitionRetryMs: 500, acquisitionAttempts: 3,
    signing: AssurancePossessionLimits(shards: ElementLimit(1023), hashes: ElementLimit(1000000),
      ioBytes: ByteLimit(256000000), hashBytes: ByteLimit(256000000), workspaceBytes: ByteLimit(
          128000000)),
    plannedBytes: ByteLimit(1000000), restoreIoBytes: ByteLimit(256000000),
        restoreWorkspaceBytes: ByteLimit(128000000),
    reply: AvailabilityReadLimits(computation: AvailabilityMerkleLimits(bytes: ByteLimit(128000000),
      hashes: ElementLimit(1000000), hashBytes: ByteLimit(128000000)), wireBytes: ByteLimit(
          32000000)),
    batchSources: ElementLimit(6144), receiptEntries: 1023, receiptMs: 1000,
    broadcastRequests: 1023, broadcastDials: 1023, broadcastBytes: 147312,
    broadcastParallel: 8, broadcastPeerMs: 1000, broadcastJobMs: 2000)
