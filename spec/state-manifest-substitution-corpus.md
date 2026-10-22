# Complete-manifest substitution qualification

Under Gray Paper pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, use the
independently authored [complete typed corpus](state-complete-serialization-corpus.md)
as immutable expected-root sources. Eight shapes cover full-width service IDs,
metadata, empty/nonempty payloads and all four request histories. Each source
first succeeds through typed restoration with the genuine complete manifest.

Sixteen declaration changes per source give 128 negative cases: changed metadata,
service ID, storage key/value, preimage hash/value, request hash/length/history,
omitted child maps, omitted/extra services, duplicate service and opaque capture.
Exact key/value mismatches remain `MappingMismatch`, duplicate identity remains
nested `CompositionFailure/DuplicateKey`, and opaque evidence remains `OpaqueValues`.
Every source re-encodes to the independent original bytes after all failed calls.

No new production rule or root policy is added. These checks qualify exact
serialization matching and preserve existing guarded reason contracts; they do
not infer semantic account validity, STF parity or authority from a root alone.
Run `make unit SUITE=state_manifest_substitutions`.

Observed locally: all 128 substitutions, inventory and pinned formatting passed
with checked ARC/Clang release on macOS ARM64. Source fixture and Python equations
are unchanged from the passing lower layers; exact-head Linux CI remains separate.
