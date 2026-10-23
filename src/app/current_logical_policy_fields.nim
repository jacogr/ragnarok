# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Complete explicit logical startup/continuation resource schema; every unsigned leaf is required, with no inferred defaults.
template currentLogicalPolicyFields(policy, context, visit: untyped) {.untyped.} =
  ## Visit each reviewed nominal scalar exactly once; Nimony resolves only the substituted caller fields.
  visit(context, "projection.services", policy.projection.services)
  visit(context, "projection.facts", policy.projection.facts)
  visit(context, "projection.perValue", policy.projection.perValue)
  visit(context, "projection.bytes", policy.projection.bytes)
  visit(context, "profile.blocks", policy.profile.blocks)
  visit(context, "profile.validators", policy.profile.validators)
  visit(context, "profile.viewBytes", policy.profile.viewBytes)
  visit(context, "profile.previousBytes", policy.profile.previousBytes)
  visit(context, "globals.chapter.items", policy.globals.chapter.items)
  visit(context, "globals.chapter.maxBytes", policy.globals.chapter.maxBytes)
  visit(context, "globals.totalBytes", policy.globals.totalBytes)
  visit(context, "logical.inventory.manifest.services", policy.logical.inventory.manifest.services)
  visit(context, "logical.inventory.manifest.serialized.items",
      policy.logical.inventory.manifest.serialized.items)
  visit(context, "logical.inventory.manifest.serialized.perValue",
      policy.logical.inventory.manifest.serialized.perValue)
  visit(context, "logical.inventory.manifest.serialized.totalValueBytes",
      policy.logical.inventory.manifest.serialized.totalValueBytes)
  visit(context, "logical.inventory.manifest.serialized.nodes",
      policy.logical.inventory.manifest.serialized.nodes)
  visit(context, "logical.inventory.manifest.storageKeyBytes",
      policy.logical.inventory.manifest.storageKeyBytes)
  visit(context, "logical.inventory.facts", policy.logical.inventory.facts)
  visit(context, "logical.inventory.bytes", policy.logical.inventory.bytes)
  visit(context, "logical.keys", policy.logical.keys)
  visit(context, "logical.rawKeyBytes", policy.logical.rawKeyBytes)
  visit(context, "logical.bytes", policy.logical.bytes)
  visit(context, "download.identities.blocks", policy.download.identities.blocks)
  visit(context, "download.identities.keys", policy.download.identities.keys)
  visit(context, "download.identities.viewBytes", policy.download.identities.viewBytes)
  visit(context, "download.requests.services", policy.download.requests.services)
  visit(context, "download.requests.requests", policy.download.requests.requests)
  visit(context, "download.requests.bytes", policy.download.requests.bytes)
  visit(context, "download.reconstruction.projection.services",
      policy.download.reconstruction.projection.services)
  visit(context, "download.reconstruction.projection.facts",
      policy.download.reconstruction.projection.facts)
  visit(context, "download.reconstruction.projection.perValue",
      policy.download.reconstruction.projection.perValue)
  visit(context, "download.reconstruction.projection.bytes",
      policy.download.reconstruction.projection.bytes)
  visit(context, "download.reconstruction.checks", policy.download.reconstruction.checks)
  visit(context, "download.reconstruction.wireBytes", policy.download.reconstruction.wireBytes)
  visit(context, "download.logical.profile.validators", policy.download.logical.profile.validators)
  visit(context, "download.logical.profile.bytes", policy.download.logical.profile.bytes)
  visit(context, "download.logical.globals.chapter.items",
      policy.download.logical.globals.chapter.items)
  visit(context, "download.logical.globals.chapter.maxBytes",
      policy.download.logical.globals.chapter.maxBytes)
  visit(context, "download.logical.globals.totalBytes", policy.download.logical.globals.totalBytes)
  visit(context, "download.logical.logical.inventory.manifest.services",
      policy.download.logical.logical.inventory.manifest.services)
  visit(context, "download.logical.logical.inventory.manifest.serialized.items",
      policy.download.logical.logical.inventory.manifest.serialized.items)
  visit(context, "download.logical.logical.inventory.manifest.serialized.perValue",
      policy.download.logical.logical.inventory.manifest.serialized.perValue)
  visit(context, "download.logical.logical.inventory.manifest.serialized.totalValueBytes",
      policy.download.logical.logical.inventory.manifest.serialized.totalValueBytes)
  visit(context, "download.logical.logical.inventory.manifest.serialized.nodes",
      policy.download.logical.logical.inventory.manifest.serialized.nodes)
  visit(context, "download.logical.logical.inventory.manifest.storageKeyBytes",
      policy.download.logical.logical.inventory.manifest.storageKeyBytes)
  visit(context, "download.logical.logical.inventory.facts",
      policy.download.logical.logical.inventory.facts)
  visit(context, "download.logical.logical.inventory.bytes",
      policy.download.logical.logical.inventory.bytes)
  visit(context, "download.logical.logical.keys", policy.download.logical.logical.keys)
  visit(context, "download.logical.logical.rawKeyBytes",
      policy.download.logical.logical.rawKeyBytes)
  visit(context, "download.logical.logical.bytes", policy.download.logical.logical.bytes)
  visit(context, "download.logical.checks", policy.download.logical.checks)
  visit(context, "download.logical.retainedBytes", policy.download.logical.retainedBytes)
