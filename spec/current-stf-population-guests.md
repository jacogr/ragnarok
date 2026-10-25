# Report-driven guest execution under changing validator populations

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, Safrole,
report credentials/availability, accumulation sequences, host write/yield/checkpoint,
statistics and recent-history equations. Pins and canonical encodings remain unchanged.

Three independently authored complete-map chains run literal write/yield guests,
rollback on panic, and checkpoint-then-panic through six→nine→six validators.
There are no free accumulation allowances. Guarantees select the real current code
hash and sign with the independently selected roster; availability uses the prior
active population. At growth, five prior-six assurers release two reports before
three new assignments. Seven prior-nine assurers release all three reports at
shrinkage before clearing inactive core2. Same-service three-report batches execute
one invocation with three operands and one independently derived guest gas charge.

All signed blocks and complete expected maps are calculated before native execution.
Expected maps include storage footprint, accumulation timestamps, actual gas,
processed-package history and yielded MMR commitments. Literal instruction charges
come from the pinned GP gas table; host charges come from its host definitions.
No other JAM implementation emits answers or vectors. Initial maps combine explicit
population globals with existing authored executable-service inputs before roots
and signatures are calculated.

The shared driver qualifies actual namespaces using declared logical service IDs,
raw storage keys and known payload/code identities. It reads actual values and
histories at those identities; exact inventory comparison refuses unknown or
unaccounted entries. Complete independent posterior comparison checks semantics;
no expected posterior constructs the next native state.

Completion requires exact native agreement for all30 transitions, independent quorum,
effect selection, gas, history and timestamp invariants, unchanged older guest answers,
source inventory and pinned formatting. This bounds report/execution interactions;
full JAM/STF and external client conformance remain separate.

Observed checked macOS ARM64 ARC/Clang non-LTO: all30 new transitions and the
unchanged22-transition/17-refusal offender corpus passed exact complete output
comparison. All15 scoped independent tests passed, including unchanged earlier
guest answers. Pinned formatting and source inventory passed. Finite fetch and
processed-history policies explicitly cover three operands and ten packages.
