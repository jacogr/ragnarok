# Bounded larger storage workloads

This dependent measurement work preserves merged base `18764f6252e6599ab6b1ddd1c6eb729c6c11a307`,
pinned Nimony `5b51edfedb4d0dbd9028d9e57ac61d69dffe9410` and Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. No production policy, physical layout, defaults,
state/API, checkpoint authority or documented M1 scope changes are planned.

Synthetic fixtures use 32,768/65,536/131,072 entries with independently distinguishable 256-byte
values and four-byte ordered key identities. Full index/revision fields prevent payload deduplication
or truncated-key aliases from understating larger-map work. Publications are bounded to 16/64
four-key sweeps. An explicit 1,024-entry native control exercises fixture semantics cheaply.

Benchmark-only ceilings independently cap items, graph nodes, physical records, aggregate values
and encoded bytes. They do not widen application defaults. Complete-map equality, exact local
head/generation, strict disk reopen and immutable-reader ownership remain prerequisites for accepting
any resource observation. These bounded synthetic sizes alone do not establish production-scale
throughput, out-of-core behavior, cold caches or hardware power-loss durability.

## Independent complete-map fixture checks

Each prepared publication has its exact Merklized successor root. Native fixture qualification
publishes every physical delta, independently compares all seed/current keys and full values,
checks exact generation/root, closes the owner and repeats the retained-map checks. Revision
expectations are closed form rather than derived from the mutation loop. Separate1,024/32,768-entry
controls cover16/64 publications before larger native panels consume the same fixture.

## Native backend lifecycle

A dedicated larger-workload executable populates memory, synchronized journal or managed storage
through unchanged public APIs, then retires prepared fixtures before sampling live owner bytes.
Every current map is compared against independent complete key/value expectations. Disk backends
strictly close/reopen and validate again; the held original view remains complete after final owner
close. Every native owner and synthetic namespace retires, and final allocator usage must match
the starting baseline. Missing memory-reopen observations carry `-1`. Generation and physical
inventory remain explicit scalar witnesses, with no timing or power-loss claim.
