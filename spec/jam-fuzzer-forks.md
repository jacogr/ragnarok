# Fuzzer depth-one sibling execution

The pinned davxy/jam-conformance acd4b2da310ff25226c4d41b918712578483fd2c
fuzz-proto/README.md Forking workflow sends valid/invalid mutations sharing one
parent, then the original block, then extends that original. Mutants are never
parents of subsequent blocks in the documented campaign. GP admission/execution
checks remain unchanged for every attempted child.

This increment retains an immutable application parent and its exact ancestor
context for a sibling group. Every sibling executes against that same parent;
a previously accepted mutant cannot contaminate the next candidate. Successful
children retain separate whole maps. Only an actual successful import selects
its child as the last response/head; a later direct extension advances the group
and retires the old sibling parent. Unsupported unknown/retired parents remain
local context failures rather than fabricated consensus-invalid block judgments.

Caller policy explicitly enables forks with a bounded sibling-state window.
The target advertises feature2 and enables the window only when the handshake
intersection includes that bit. A peer without the bit retains linear execution.
The rolling sibling window bounds retained GetState maps; normal selected history
and the exact seed remain separately available. Evicted siblings are unavailable,
not replaced by another fork's state. No production fork-choice, finality or
persistent chain state is changed.

Completion cases compare independently calculated full sibling maps and roots,
invalid-mutant rollback, duplicate imports, cache eviction, original-last order,
and next-height continuation; real socket tests verify negotiated activation.
Live generated campaign validation remains explicitly pending engine availability.

Nonempty reporting siblings are covered separately by the registered report-fork
corpus. Four mutations re-author guaranteed packages and their valid credentials;
each receives an independently calculated complete STF map from the shared
original parent. The original-last block restores that parent's exact map and
ancestry. The corpus compares24 successful imports, retains mutant maps after
the original succeeds, and checks that a failed attempt after a valid mutant
changes neither the selected mutant head nor its complete map. Existing local
missing-evidence and consensus wrong-root report probes remain active.
