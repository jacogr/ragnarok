# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit test-only full guarantor profile drives parser and actual node startup witnesses without production defaults.

import ../../src/app/node_work_policy
import ../../src/jamnp-s/[work_sharing, work_recovery]
import ../../src/codec/bounded
import ../../src/codec/work/package
import ./[jamnp_guarantee_fixture, jamnp_work_fixture, jamnp_work_report_fixture,
  jamnp_work_recovery_fixture, pvm_input_refinement]

proc guarantorSettings*(): NodeWorkSettings =
  ## Genuine execution fixtures supply only test inputs; production startup never imports these resource policies or derives defaults from them.
  result = default(NodeWorkSettings)
  let raw = workFixture()
  result.admission = raw.limits
  result.execution = executionLimits()
  result.duty = guaranteeLimits().duty
  result.timeoutMs = 120000
  result.sharing = WorkSharingLimits(packageBytes: ByteLimit(MaxBundleBytes),
      bundleBytes: ByteLimit(MaxBundleBytes),
    report: workReportLimits(), eligibility: guaranteeLimits(), retention: guarantorLimits())
  result.storage = guarantorStorageLimits()
  result.serving = guarantorReadLimits()
  result.recovery = recoveryPolicy().limits
  result.recoveryTimeoutMs = 1000
  result.guaranteeBytes = 20000
  result.exchangeTimeoutMs = 120000
  result.peerTimeoutMs = 10000
  result.graceMs = 2000
  result.deliveryWireBytes = 20000
  result.deliveryTargets = 12
  result.deliveryEntries = 4
  result.deliveryBytes = 80000
  result.deliveryTimeoutMs = 8000
  result.deliveryPeerTimeoutMs = 500
  result.deliveryParallel = 16
  result.acquisitionAttempts = 6
  result.acquisitionTimeoutMs = 1000
  result.acquisitionReplyBytes = 16000000
