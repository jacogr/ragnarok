# Selected producer storage history

Scope preserves Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`; no mutation/protocol interpretation changes.

`captureStorageHistory` accepts only genuine `CompletedCurrentAccumulationSequence` ownership.
It retains selected producer raw storage identities in actual sequence entry order and original
parallel-outcome positions. It does not invent a cross-invocation host-operation order. Every
surviving executed invocation requires enabled producer raw identity capture; disabled is never
interpreted as an empty trace. Non-executing providers contribute no storage calls.

Annulment explicitly suppresses original identities for a cancelled invocation, just as it restores
the common prior account state. The original outcome remains observable separately. A selected
annulled trace is provably empty even if unused original tracing was disabled. Panic/checkpoint
selection has already chosen the original invocation's correct implication before this stage.

Independent entry/outcome/fact and descriptor-plus-logical-raw-byte retention ceilings admit the
entire history before output allocation. A second pass retains immutable original facts without
key copying or cryptographic work. Defaults, disabled capture, resource limits and full-width
indices have typed guarded failures. The result retains its exact completed source for subsequent
original-parent/successor checks; copied public rows cannot mutate that owner.

This closes selected raw storage trace collection for the automatic continuation consumer. It is
not a complete logical manifest: untouched identities still come from the original qualified
parent; service creation/ejection, requests/preimages and non-guest changes need their own proven
composition. A general supplied-delta API, trusted roots, adoption and finality remain separate.

Verification: `make unit SUITE=accumulation_storage_history` uses actual signed current sequences,
supervised concurrent same-key writes and genuine annulment, disabled/refused/exact capture,
source retirement and 1,000 balanced ARC retain/retire cycles. Existing parallel-annulment and
current-sequence suites, new strict guards/privacy rejections, inventory and both formatting gates
remain required. M1 framing is complete; independent full current-schema STF, current Thin VRF
and ambiguous privilege gates remain outstanding.
