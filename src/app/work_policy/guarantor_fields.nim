# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit guarantor-profile schema extends the unchanged v1 submission leaves; every resource value must be present.
template guarantorPolicyFields(profile, context, visit: untyped) {.untyped.} =
  ## Reading and serialization share this reviewed scalar schema without runtime reflection or hidden fixture-derived budgets.
  workPolicyFields(profile, context, visit)
  visit(context, "sharing.packageBytes", profile.sharing.packageBytes)
  visit(context, "sharing.bundleBytes", profile.sharing.bundleBytes)
  visit(context, "sharing.report.bundleBytes", profile.sharing.report.bundleBytes)
  visit(context, "sharing.report.layoutBytes", profile.sharing.report.layoutBytes)
  visit(context, "sharing.report.reportBytes", profile.sharing.report.reportBytes)
  visit(context, "sharing.report.transcriptBytes", profile.sharing.report.transcriptBytes)
  visit(context, "sharing.report.bundle.bytes", profile.sharing.report.bundle.bytes)
  visit(context, "sharing.report.bundle.products", profile.sharing.report.bundle.products)
  visit(context, "sharing.report.exports.bytes", profile.sharing.report.exports.bytes)
  visit(context, "sharing.report.exports.products", profile.sharing.report.exports.products)
  visit(context, "sharing.report.exports.commitment.exports",
      profile.sharing.report.exports.commitment.exports)
  visit(context, "sharing.report.exports.commitment.nodes",
      profile.sharing.report.exports.commitment.nodes)
  visit(context, "sharing.report.exports.commitment.hashBytes",
      profile.sharing.report.exports.commitment.hashBytes)
  visit(context, "sharing.report.availability.bytes", profile.sharing.report.availability.bytes)
  visit(context, "sharing.report.availability.hashBytes",
      profile.sharing.report.availability.hashBytes)
  visit(context, "sharing.report.availability.hashes", profile.sharing.report.availability.hashes)
  visit(context, "sharing.eligibility.anchors.history.cores",
      profile.sharing.eligibility.anchors.history.cores)
  visit(context, "sharing.eligibility.anchors.history.blocks",
      profile.sharing.eligibility.anchors.history.blocks)
  visit(context, "sharing.eligibility.anchors.history.perBlock",
      profile.sharing.eligibility.anchors.history.perBlock)
  visit(context, "sharing.eligibility.anchors.history.totalPackages",
      profile.sharing.eligibility.anchors.history.totalPackages)
  visit(context, "sharing.eligibility.anchors.history.peaks",
      profile.sharing.eligibility.anchors.history.peaks)
  visit(context, "sharing.eligibility.anchors.history.maxBytes",
      profile.sharing.eligibility.anchors.history.maxBytes)
  visit(context, "sharing.eligibility.anchors.ancestors.header.cores",
      profile.sharing.eligibility.anchors.ancestors.header.cores)
  visit(context, "sharing.eligibility.anchors.ancestors.header.authorValidators",
      profile.sharing.eligibility.anchors.ancestors.header.authorValidators)
  visit(context, "sharing.eligibility.anchors.ancestors.header.epochSlots",
      profile.sharing.eligibility.anchors.ancestors.header.epochSlots)
  visit(context, "sharing.eligibility.anchors.ancestors.header.maxBytes",
      profile.sharing.eligibility.anchors.ancestors.header.maxBytes)
  visit(context, "sharing.eligibility.anchors.ancestors.headers",
      profile.sharing.eligibility.anchors.ancestors.headers)
  visit(context, "sharing.eligibility.anchors.ancestors.maxBytes",
      profile.sharing.eligibility.anchors.ancestors.maxBytes)
  visit(context, "sharing.eligibility.population.validators.cores",
      profile.sharing.eligibility.population.validators.cores)
  visit(context, "sharing.eligibility.population.validators.validators",
      profile.sharing.eligibility.population.validators.validators)
  visit(context, "sharing.eligibility.population.validators.maxBytes",
      profile.sharing.eligibility.population.validators.maxBytes)
  visit(context, "sharing.eligibility.population.epochSlots",
      profile.sharing.eligibility.population.epochSlots)
  visit(context, "sharing.eligibility.population.maxAccumulator",
      profile.sharing.eligibility.population.maxAccumulator)
  visit(context, "sharing.eligibility.population.maxBytes",
      profile.sharing.eligibility.population.maxBytes)
  visit(context, "sharing.eligibility.duty.chapterBytes",
      profile.sharing.eligibility.duty.chapterBytes)
  visit(context, "sharing.eligibility.duty.disputeItems",
      profile.sharing.eligibility.duty.disputeItems)
  visit(context, "sharing.eligibility.policy.pools.cores",
      profile.sharing.eligibility.policy.pools.cores)
  visit(context, "sharing.eligibility.policy.pools.maxHashes",
      profile.sharing.eligibility.policy.pools.maxHashes)
  visit(context, "sharing.eligibility.policy.pools.maxBytes",
      profile.sharing.eligibility.policy.pools.maxBytes)
  visit(context, "sharing.eligibility.policy.accountBytes",
      profile.sharing.eligibility.policy.accountBytes)
  visit(context, "sharing.eligibility.policy.reportGas",
      profile.sharing.eligibility.policy.reportGas)
  visit(context, "sharing.eligibility.policy.refinementGas",
      profile.sharing.eligibility.policy.refinementGas)
  visit(context, "sharing.eligibility.pipeline.availability.guarantee.cores",
      profile.sharing.eligibility.pipeline.availability.guarantee.cores)
  visit(context, "sharing.eligibility.pipeline.availability.guarantee.validators",
      profile.sharing.eligibility.pipeline.availability.guarantee.validators)
  visit(context, "sharing.eligibility.pipeline.availability.guarantee.maxBytes",
      profile.sharing.eligibility.pipeline.availability.guarantee.maxBytes)
  visit(context, "sharing.eligibility.pipeline.availability.maxPresent",
      profile.sharing.eligibility.pipeline.availability.maxPresent)
  visit(context, "sharing.eligibility.pipeline.availability.maxBytes",
      profile.sharing.eligibility.pipeline.availability.maxBytes)
  visit(context, "sharing.eligibility.pipeline.queues.epochSlots",
      profile.sharing.eligibility.pipeline.queues.epochSlots)
  visit(context, "sharing.eligibility.pipeline.queues.cores",
      profile.sharing.eligibility.pipeline.queues.cores)
  visit(context, "sharing.eligibility.pipeline.queues.perSlot",
      profile.sharing.eligibility.pipeline.queues.perSlot)
  visit(context, "sharing.eligibility.pipeline.queues.totalItems",
      profile.sharing.eligibility.pipeline.queues.totalItems)
  visit(context, "sharing.eligibility.pipeline.queues.perDependencies",
      profile.sharing.eligibility.pipeline.queues.perDependencies)
  visit(context, "sharing.eligibility.pipeline.queues.totalDependencies",
      profile.sharing.eligibility.pipeline.queues.totalDependencies)
  visit(context, "sharing.eligibility.pipeline.queues.reportBytes",
      profile.sharing.eligibility.pipeline.queues.reportBytes)
  visit(context, "sharing.eligibility.pipeline.queues.maxBytes",
      profile.sharing.eligibility.pipeline.queues.maxBytes)
  visit(context, "sharing.eligibility.pipeline.indexItems",
      profile.sharing.eligibility.pipeline.indexItems)
  visit(context, "sharing.eligibility.reportBytes", profile.sharing.eligibility.reportBytes)
  visit(context, "sharing.retention.bytes", profile.sharing.retention.bytes)
  visit(context, "sharing.retention.hashBytes", profile.sharing.retention.hashBytes)
  visit(context, "sharing.retention.hashes", profile.sharing.retention.hashes)
  visit(context, "storage.entries", profile.storage.entries)
  visit(context, "storage.computation.bytes", profile.storage.computation.bytes)
  visit(context, "storage.computation.hashBytes", profile.storage.computation.hashBytes)
  visit(context, "storage.computation.hashes", profile.storage.computation.hashes)
  visit(context, "serving.computation.bytes", profile.serving.computation.bytes)
  visit(context, "serving.computation.hashBytes", profile.serving.computation.hashBytes)
  visit(context, "serving.computation.hashes", profile.serving.computation.hashes)
  visit(context, "serving.wireBytes", profile.serving.wireBytes)
  visit(context, "recovery.catalog.blocks", profile.recovery.catalog.blocks)
  visit(context, "recovery.catalog.reports", profile.recovery.catalog.reports)
  visit(context, "recovery.catalog.keys", profile.recovery.catalog.keys)
  visit(context, "recovery.catalog.retentionEpochs", profile.recovery.catalog.retentionEpochs)
  visit(context, "recovery.catalog.chapterBytes", profile.recovery.catalog.chapterBytes)
  visit(context, "recovery.catalog.readBytes", profile.recovery.catalog.readBytes)
  visit(context, "recovery.pair.bytes", profile.recovery.pair.bytes)
  visit(context, "recovery.pair.hashBytes", profile.recovery.pair.hashBytes)
  visit(context, "recovery.pair.products", profile.recovery.pair.products)
  visit(context, "recovery.pair.hashes", profile.recovery.pair.hashes)
  visit(context, "recovery.pair.proof.siblings", profile.recovery.pair.proof.siblings)
  visit(context, "recovery.pair.proof.payloadBytes", profile.recovery.pair.proof.payloadBytes)
  visit(context, "recovery.pair.proof.hashBytes", profile.recovery.pair.proof.hashBytes)
  visit(context, "recovery.transfer.bytes", profile.recovery.transfer.bytes)
  visit(context, "recovery.transfer.hashBytes", profile.recovery.transfer.hashBytes)
  visit(context, "recovery.transfer.hashes", profile.recovery.transfer.hashes)
  visit(context, "recovery.items", profile.recovery.items)
  visit(context, "recovery.requests", profile.recovery.requests)
  visit(context, "recovery.dials", profile.recovery.dials)
  visit(context, "recovery.hashes", profile.recovery.hashes)
  visit(context, "recovery.peersPerPoll", profile.recovery.peersPerPoll)
  visit(context, "recovery.bytes", profile.recovery.bytes)
  visit(context, "recovery.hashBytes", profile.recovery.hashBytes)
  visit(context, "recovery.replyBytes", profile.recovery.replyBytes)
  visit(context, "recovery.products", profile.recovery.products)
  visit(context, "recovery.timeoutMs", profile.recoveryTimeoutMs)
  visit(context, "guaranteeBytes", profile.guaranteeBytes)
  visit(context, "exchangeTimeoutMs", profile.exchangeTimeoutMs)
  visit(context, "peerTimeoutMs", profile.peerTimeoutMs)
  visit(context, "graceMs", profile.graceMs)
  visit(context, "deliveryWireBytes", profile.deliveryWireBytes)
  visit(context, "deliveryTargets", profile.deliveryTargets)
  visit(context, "deliveryEntries", profile.deliveryEntries)
  visit(context, "deliveryBytes", profile.deliveryBytes)
  visit(context, "deliveryTimeoutMs", profile.deliveryTimeoutMs)
  visit(context, "deliveryPeerTimeoutMs", profile.deliveryPeerTimeoutMs)
  visit(context, "deliveryParallel", profile.deliveryParallel)
  visit(context, "acquisitionAttempts", profile.acquisitionAttempts)
  visit(context, "acquisitionTimeoutMs", profile.acquisitionTimeoutMs)
  visit(context, "acquisitionReplyBytes", profile.acquisitionReplyBytes)
