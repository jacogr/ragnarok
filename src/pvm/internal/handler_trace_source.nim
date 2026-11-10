# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Included neutral complete-original prelude and one ordered no-op-aware source/site traversal.
## Interval-only consumers keep their weaker contract; header policies and execution stay local.
## Standalone source audits import an empty fragment; the owning include supplies private frame types.

when declared(FlatFrame):
  type FlatSourceSummary = object
    ## General complete-header consumers retain only the terminal coordinate and physical count.
    terminal, operations: uint32

  func flatCompleteOriginalHeader(f: FlatFrame, pc, maximum: uint32,
      header: var uint32, source: var FlatSourceInterval): bool =
    ## Bind the original complete PC/price map without execution policy or a copied operation array.
    if int(pc) >= f.compiledForPc.len: return false
    let packed = f.compiledForPc[int(pc)]
    if packed == 0: return false
    let value = packed-1
    if (value and 0x80000000'u32) == 0: return false
    let resolved = value and 0x7fffffff'u32
    if int(resolved) >= f.handlers.len or int(resolved) >= f.sites.len or
        int(resolved) >= f.arguments.len: return false
    let ordinal = f.sites[int(resolved)]
    if int(ordinal) >= f.plan.facts.len: return false
    let first = f.plan.facts[int(ordinal)]
    if first.pc != pc or int(first.priceIndex) >= f.plan.pricePcs.len or
        f.plan.pricePcs[int(first.priceIndex)] != CodeAddress(uint64(pc)): return false
    let span = f.arguments[int(resolved)].y
    if span != first.sourceCount: return false
    if not flatSourceIntervalAt(f, resolved, maximum, source): return false
    header = resolved
    true

  func flatSourceFact(sink: var FlatSourceSummary, fact: FlatFact, node, ordinal: uint32): bool =
    ## Summary specialization has no operation or site array to initialize or copy.
    sink.terminal = node
    inc sink.operations
    true

  template flatWalkCompleteSource(f: FlatFrame, header: uint32,
      source: FlatSourceInterval, sink: untyped): bool =
    ## Static sink selection preserves one ordered walk without callbacks or owning views.
    block:
      var accepted = true
      block sourceWalk:
        var node = header+1
        for at in source.first..source.last:
          # Folded noops retain their priced source span without consuming physical stream nodes.
          let fact = f.plan.facts[int(at)]
          if at != source.last and (fact.ending or not fact.fallthrough):
            accepted = false
            break sourceWalk
          if fact.opcode != 2:
            if int(node) >= f.sites.len or int(node) >= f.handlers.len or
                int(node) >= f.arguments.len or f.sites[int(node)] != at:
              accepted = false
              break sourceWalk
            if not flatSourceFact(sink, fact, node, at):
              accepted = false
              break sourceWalk
            inc node
        if node <= header+1: accepted = false
      accepted
