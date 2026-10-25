# Published Genesis framing and independently anchored replay startup

Authority: GP 1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d and unchanged vectors
23061ae1f9b51171c01387e7dde0f15794c98e24, traces/schema.asn.
Published Genesis is one complete Header followed directly by one RawState.

State's trace_genesis module owns those two immutable children, exact prefix
extent and caller-supplied structural/map/byte limits. Header and state failures
retain their actual typed reasons, while defaults/refusals expose no children or
progress. Detached copying preflights the combined extent. Original RawState order
is preserved and no local checkpoint wrapper or alternate scalar representation
is accepted.

App's trace_bootstrap module requires independent configuration of both the
sealed-header hash and the posterior state's complete root, plus explicit full
Parameters. A header commits its parent's state; its hash alone cannot authenticate
the supplied posterior map. The incoming file therefore cannot choose its own
anchors or infer a profile. The existing configured-genesis structural capture
binds actual header, map and Parameters before either anchor is compared. Only
complete agreement initializes a new application chain with the explicitly trusted
finalized initial anchor and inherited writable store policy. It never replaces
an existing chain or claims an executed genesis signature/STF certificate. Later
current candidate preparation performs ordinary authenticated transition validation.

Forty original Genesis files are calculated independently before native execution.
The maintained initial header has slot1, the hash of the literal zero-filled
297-byte ancient header as parent, and otherwise zero fields. The reference builds
its exact297 bytes directly and verifies that every first independently signed
child names that header hash. Initial complete maps, roots and subsequent signed
TraceStep files remain independently authored; no observed native header or
successor supplies an answer.

Each chain compares exact Genesis wire, rejects an incorrect external header hash,
incorrect external state root and default Parameters, then replays its existing
signed descendants from the newly initialized owner.255 complete transitions,
120 explicit bootstrap refusal observations and765 wrong-map/seal observations
cover allowance, gas eligibility, actual incarnation, foreign funding and queued
report behavior. Store policy and every configured parameter byte remain identical
to the independently configured seed across this ownership boundary.

Native units mutate input, release enclosing owners, retain/copy children, refuse
short output capacity and corrupt state roots, and initialize only with frozen
external trust literals. Privacy fixtures deny both wire and startup result
internals. Independent wire/anchor/parent-continuity invariants, file-backed replay
regression, focused semantic/native checks, twice-idempotent formatting and
inventory complete the scope. Local ARC/Clang evidence remains distinct from
exact-head Linux CI. Operator invocation and external differential execution
remain next; all pins, historical fixtures and production STF algorithms are
unchanged.
