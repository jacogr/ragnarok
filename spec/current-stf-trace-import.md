# Actual current-profile STF trace import

Pinned authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d` and the
unchanged published TraceStep schema at vectors `23061ae1f9b51171c01387e7dde0f15794c98e24`.

`app/trace/import` bridges framed traces to ordinary authenticated current candidate
preparation. The caller supplies the actual selected `ApplicationChain`, ancestry
and candidate limits. The trace supplies neither a trusted parent nor Parameters.
Before executing, the importer compares its entire advertised pre-state against the
actual selected full map: count, root, every sorted key and every value, including
empty values. It then executes the exact captured signed block through the existing
`prepareCurrentCandidate` path, with the chain's retained profile/provenance.

Only complete equality between the genuine prepared successor and the advertised
post-state releases the actual opaque `PreparedCurrentChainUpdate`. A mismatch
retires that preparation without exposing an installable prefix. Defaults, absent
parents and original admission/execution failures remain typed refusals. The import
function never installs or mutates the application chain; ordinary chain-bound
installation and stale-head checks remain the caller's separate responsibility.

Forty chains replay255 independently calculated signed transitions. Full published
TraceStep bytes enter unchanged; child headers and signatures are not rebuilt by
the native fixture signer. Original trusted chain setup, explicit full Parameters,
all complete successor maps, logical identity exports and fresh-store continuation
remain independently compared across allowance, gas-eligibility, incarnation,
foreign-funding and queued-report families.

Each transition additionally compares three typed refusal observations: a different
fully committed pre-state, a different fully committed post-state, and a wire-valid
block with one altered seal byte. Every refusal preserves the entire selected
parent map and exposes no successful prepared update.765 refusal observations
supplement the255 positive complete-map comparisons. The wrong-post witness runs
the actual STF before failing comparison, distinguishing output authentication from
mere wire/root validation.

Native units cover default owners and the explicit missing-actual-parent boundary;
privacy fixtures prohibit direct success/candidate-field access. Independent trace
framing/continuity/refusal invariants, current queued-report regressions, focused
semantic/native checks, pinned formatter idempotence and inventory cover completion.
Local ARC/Clang evidence remains separate from exact-head Linux CI. Bounded file
input and external-client differential conformance remain next; pins, historical
vectors, production STF algorithms and AmbiguousPrivileges are unchanged.
