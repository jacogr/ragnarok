# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Exact independently required namespace continuation/producer resource leaves; lexicographic output is canonical and no hidden defaults are supplied.
template currentNamespacePolicyFields(policy, context, visit: untyped) {.untyped.} =
  ## Visit each reviewed unsigned nominal scalar exactly once; failed assignment remains private to the parser.
  visit(context, "continuation.checks", policy.continuation.checks)
  visit(context, "continuation.globals.chapter.items", policy.continuation.globals.chapter.items)
  visit(context, "continuation.globals.chapter.maxBytes",
      policy.continuation.globals.chapter.maxBytes)
  visit(context, "continuation.globals.totalBytes", policy.continuation.globals.totalBytes)
  visit(context, "continuation.identity.blocks", policy.continuation.identity.blocks)
  visit(context, "continuation.identity.keys", policy.continuation.identity.keys)
  visit(context, "continuation.identity.viewBytes", policy.continuation.identity.viewBytes)
  visit(context, "continuation.logical.bytes", policy.continuation.logical.bytes)
  visit(context, "continuation.logical.inventory.bytes",
      policy.continuation.logical.inventory.bytes)
  visit(context, "continuation.logical.inventory.facts",
      policy.continuation.logical.inventory.facts)
  visit(context, "continuation.logical.inventory.manifest.serialized.items",
      policy.continuation.logical.inventory.manifest.serialized.items)
  visit(context, "continuation.logical.inventory.manifest.serialized.nodes",
      policy.continuation.logical.inventory.manifest.serialized.nodes)
  visit(context, "continuation.logical.inventory.manifest.serialized.perValue",
      policy.continuation.logical.inventory.manifest.serialized.perValue)
  visit(context, "continuation.logical.inventory.manifest.serialized.totalValueBytes",
      policy.continuation.logical.inventory.manifest.serialized.totalValueBytes)
  visit(context, "continuation.logical.inventory.manifest.services",
      policy.continuation.logical.inventory.manifest.services)
  visit(context, "continuation.logical.inventory.manifest.storageKeyBytes",
      policy.continuation.logical.inventory.manifest.storageKeyBytes)
  visit(context, "continuation.logical.keys", policy.continuation.logical.keys)
  visit(context, "continuation.logical.rawKeyBytes", policy.continuation.logical.rawKeyBytes)
  visit(context, "continuation.profile.bytes", policy.continuation.profile.bytes)
  visit(context, "continuation.profile.validators", policy.continuation.profile.validators)
  visit(context, "continuation.projection.bytes", policy.continuation.projection.bytes)
  visit(context, "continuation.projection.facts", policy.continuation.projection.facts)
  visit(context, "continuation.projection.perValue", policy.continuation.projection.perValue)
  visit(context, "continuation.projection.services", policy.continuation.projection.services)
  visit(context, "continuation.scratchBytes", policy.continuation.scratchBytes)
  visit(context, "initial.requests", policy.initial.requests)
  visit(context, "initial.storage.items", policy.initial.storage.items)
  visit(context, "initial.storage.perKey", policy.initial.storage.perKey)
  visit(context, "initial.storage.totalKeyBytes", policy.initial.storage.totalKeyBytes)
  visit(context, "requests.bytes", policy.requests.bytes)
  visit(context, "requests.entries", policy.requests.entries)
  visit(context, "requests.facts", policy.requests.facts)
  visit(context, "requests.outcomes", policy.requests.outcomes)
  visit(context, "round.requests", policy.round.requests)
  visit(context, "round.storage.items", policy.round.storage.items)
  visit(context, "round.storage.perKey", policy.round.storage.perKey)
  visit(context, "round.storage.totalKeyBytes", policy.round.storage.totalKeyBytes)
  visit(context, "services.bytes", policy.services.bytes)
  visit(context, "services.creations", policy.services.creations)
  visit(context, "services.deletions", policy.services.deletions)
  visit(context, "services.entries", policy.services.entries)
  visit(context, "services.outcomes", policy.services.outcomes)
  visit(context, "storage.bytes", policy.storage.bytes)
  visit(context, "storage.entries", policy.storage.entries)
  visit(context, "storage.facts", policy.storage.facts)
  visit(context, "storage.outcomes", policy.storage.outcomes)
