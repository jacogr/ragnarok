# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Frozen work-policy v1 schema visits explicit scalar resource ceilings and named backends; logging is a separate host borrow.

template workPolicyFields(policy, context, visit: untyped) {.untyped.} =
  ## One private schema defines complete typed reading and canonical serialization without runtime reflection or inferred defaults.
  visit(context, "admission.pools.cores", policy.admission.pools.cores)
  visit(context, "admission.pools.maxHashes", policy.admission.pools.maxHashes)
  visit(context, "admission.pools.maxBytes", policy.admission.pools.maxBytes)
  visit(context, "admission.history.cores", policy.admission.history.cores)
  visit(context, "admission.history.blocks", policy.admission.history.blocks)
  visit(context, "admission.history.perBlock", policy.admission.history.perBlock)
  visit(context, "admission.history.totalPackages", policy.admission.history.totalPackages)
  visit(context, "admission.history.peaks", policy.admission.history.peaks)
  visit(context, "admission.history.maxBytes", policy.admission.history.maxBytes)
  visit(context, "admission.authorization.preimage", policy.admission.authorization.preimage)
  visit(context, "admission.authorization.package", policy.admission.authorization.package)
  visit(context, "admission.authorization.encoding", policy.admission.authorization.encoding)
  visit(context, "admission.authorization.copy", policy.admission.authorization.copy)
  visit(context, "admission.authorization.steps", policy.admission.authorization.steps)
  visit(context, "admission.authorization.calls", policy.admission.authorization.calls)
  visit(context, "admission.authorization.backend", policy.admission.authorization.backend)
  visit(context, "admission.authorization.cycles", policy.admission.authorization.cycles)
  visit(context, "admission.authorization.output", policy.admission.authorization.output)
  visit(context, "admission.authorization.initialization.envelope",
      policy.admission.authorization.initialization.envelope)
  visit(context, "admission.authorization.initialization.program",
      policy.admission.authorization.initialization.program)
  visit(context, "admission.authorization.initialization.jumps",
      policy.admission.authorization.initialization.jumps)
  visit(context, "admission.authorization.initialization.pages",
      policy.admission.authorization.initialization.pages)
  visit(context, "admission.extrinsics.entries", policy.admission.extrinsics.entries)
  visit(context, "admission.extrinsics.payloadBytes", policy.admission.extrinsics.payloadBytes)
  visit(context, "admission.extrinsics.hashBytes", policy.admission.extrinsics.hashBytes)
  visit(context, "admission.imports.entries", policy.admission.imports.entries)
  visit(context, "admission.imports.witnessBytes", policy.admission.imports.witnessBytes)
  visit(context, "admission.proof.siblings", policy.admission.proof.siblings)
  visit(context, "admission.proof.payloadBytes", policy.admission.proof.payloadBytes)
  visit(context, "admission.proof.hashBytes", policy.admission.proof.hashBytes)
  visit(context, "execution.inputBytes", policy.execution.inputBytes)
  visit(context, "execution.authorization.preimage", policy.execution.authorization.preimage)
  visit(context, "execution.authorization.package", policy.execution.authorization.package)
  visit(context, "execution.authorization.encoding", policy.execution.authorization.encoding)
  visit(context, "execution.authorization.copy", policy.execution.authorization.copy)
  visit(context, "execution.authorization.steps", policy.execution.authorization.steps)
  visit(context, "execution.authorization.calls", policy.execution.authorization.calls)
  visit(context, "execution.authorization.backend", policy.execution.authorization.backend)
  visit(context, "execution.authorization.cycles", policy.execution.authorization.cycles)
  visit(context, "execution.authorization.output", policy.execution.authorization.output)
  visit(context, "execution.authorization.initialization.envelope",
      policy.execution.authorization.initialization.envelope)
  visit(context, "execution.authorization.initialization.program",
      policy.execution.authorization.initialization.program)
  visit(context, "execution.authorization.initialization.jumps",
      policy.execution.authorization.initialization.jumps)
  visit(context, "execution.authorization.initialization.pages",
      policy.execution.authorization.initialization.pages)
  visit(context, "execution.refinement.trace", policy.execution.refinement.trace)
  visit(context, "execution.refinement.refinement.items",
      policy.execution.refinement.refinement.items)
  visit(context, "execution.refinement.refinement.exports",
      policy.execution.refinement.refinement.exports)
  visit(context, "execution.refinement.refinement.blobs",
      policy.execution.refinement.refinement.blobs)
  visit(context, "execution.refinement.refinement.bootstrap.preimage",
      policy.execution.refinement.refinement.bootstrap.preimage)
  visit(context, "execution.refinement.refinement.bootstrap.package",
      policy.execution.refinement.refinement.bootstrap.package)
  visit(context, "execution.refinement.refinement.bootstrap.arguments",
      policy.execution.refinement.refinement.bootstrap.arguments)
  visit(context, "execution.refinement.refinement.bootstrap.initialization.envelope",
      policy.execution.refinement.refinement.bootstrap.initialization.envelope)
  visit(context, "execution.refinement.refinement.bootstrap.initialization.program",
      policy.execution.refinement.refinement.bootstrap.initialization.program)
  visit(context, "execution.refinement.refinement.bootstrap.initialization.jumps",
      policy.execution.refinement.refinement.bootstrap.initialization.jumps)
  visit(context, "execution.refinement.refinement.bootstrap.initialization.pages",
      policy.execution.refinement.refinement.bootstrap.initialization.pages)
  visit(context, "execution.refinement.refinement.invocation.capture.trace",
      policy.execution.refinement.refinement.invocation.capture.trace)
  visit(context, "execution.refinement.refinement.invocation.capture.package",
      policy.execution.refinement.refinement.invocation.capture.package)
  visit(context, "execution.refinement.refinement.invocation.capture.encoding",
      policy.execution.refinement.refinement.invocation.capture.encoding)
  visit(context, "execution.refinement.refinement.invocation.capture.inputs",
      policy.execution.refinement.refinement.invocation.capture.inputs)
  visit(context, "execution.refinement.refinement.invocation.copy",
      policy.execution.refinement.refinement.invocation.copy)
  visit(context, "execution.refinement.refinement.invocation.steps",
      policy.execution.refinement.refinement.invocation.steps)
  visit(context, "execution.refinement.refinement.invocation.calls",
      policy.execution.refinement.refinement.invocation.calls)
  visit(context, "execution.refinement.refinement.invocation.backend",
      policy.execution.refinement.refinement.invocation.backend)
  visit(context, "execution.refinement.refinement.invocation.cycles",
      policy.execution.refinement.refinement.invocation.cycles)
  visit(context, "execution.refinement.refinement.invocation.output",
      policy.execution.refinement.refinement.invocation.output)
  visit(context, "execution.refinement.refinement.invocation.exports.items",
      policy.execution.refinement.refinement.invocation.exports.items)
  visit(context, "execution.refinement.refinement.invocation.exports.bytes",
      policy.execution.refinement.refinement.invocation.exports.bytes)
  visit(context, "execution.refinement.refinement.invocation.inner.items",
      policy.execution.refinement.refinement.invocation.inner.items)
  visit(context, "execution.refinement.refinement.invocation.inner.program",
      policy.execution.refinement.refinement.invocation.inner.program)
  visit(context, "execution.refinement.refinement.invocation.inner.total",
      policy.execution.refinement.refinement.invocation.inner.total)
  visit(context, "execution.refinement.refinement.invocation.inner.jumps",
      policy.execution.refinement.refinement.invocation.inner.jumps)
  visit(context, "execution.refinement.refinement.invocation.inner.pages",
      policy.execution.refinement.refinement.invocation.inner.pages)
  visit(context, "execution.refinement.refinement.invocation.inner.steps",
      policy.execution.refinement.refinement.invocation.inner.steps)
  visit(context, "execution.refinement.refinement.invocation.inner.backend",
      policy.execution.refinement.refinement.invocation.inner.backend)
  visit(context, "execution.refinement.refinement.invocation.inner.cycles",
      policy.execution.refinement.refinement.invocation.inner.cycles)
  visit(context, "execution.refinement.digests.items", policy.execution.refinement.digests.items)
  visit(context, "execution.refinement.digests.payload",
      policy.execution.refinement.digests.payload)
  visit(context, "execution.refinement.digests.totalPayload",
      policy.execution.refinement.digests.totalPayload)
  visit(context, "execution.refinement.digests.encoding",
      policy.execution.refinement.digests.encoding)
  visit(context, "execution.refinement.digests.totalEncoding",
      policy.execution.refinement.digests.totalEncoding)
  visit(context, "execution.identity.packageBytes", policy.execution.identity.packageBytes)
  visit(context, "execution.identity.authorizerBytes", policy.execution.identity.authorizerBytes)
  visit(context, "duty.chapterBytes", policy.duty.chapterBytes)
  visit(context, "duty.disputeItems", policy.duty.disputeItems)
  visit(context, "timeoutMs", policy.timeoutMs)
