# Authored complete current namespace fixtures

This test-only opt-in seeds storage, preimages and request histories for existing services 42/99
before the original map root, block and guarantee signatures are constructed. Existing code,
gas, balances and account lifetimes stay unchanged. Tiny explicit fixture bounds precede footprint
arithmetic and allocation; the real store rejects duplicate keys. Only complete-state mode accepts
seeds. Legacy empty-namespace/C250 defaults remain unchanged.

The two accounts each have two storage entries, two preimages and two requests, including empty
raw keys, present-empty storage/preimage values and available histories. Authored footprints are
six items each and 236/233 octets. The actual complete original mapping has 30 entries. A genuinely
prepared current successor retains these untouched namespaces. Both full selected-view logical
qualification and existing current-state/logical qualification must match the actual whole mapping.
These signed integration fixtures are not independent published STF goldens or full JAM parity.

Observed locally: selected namespace suite, existing current-logical/report-admission/current-candidate
regressions, inventory and pinned formatting passed. Each existing ARC consumer ran1,000 cycles
with unchanged live allocation. This is local checked ARC/Clang evidence, not exact-head Linux CI.
