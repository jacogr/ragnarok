# Current-schema source qualification

Gray Paper target: `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`.
Reference vectors remain `d3c089c9a1d5352ad353626d7a2db8589f137b2a`.
Neither source nor toolchain pins change in this qualification.

The seven already SHA-pinned trace blobs yield fourteen complete pre/post maps
and twenty-six metadata observations. Independent reconstruction still verifies every
original published map root. Every original metadata row is 89 bytes; current
production metadata is 105 bytes. The current decoder must refuse each unmodified
row as `Truncated`, without accepting a release-format fallback.

Existing test references explicitly insert a zero supervisor identity/incarnation
and zero protected balance. This is a test-only derivation. It changes every
selected complete-map root, and supplies no network migration/default policy.
The checked-in source audit records original and derived roots separately, exact
blob identities, metadata extents and opaque service-row counts. Hashed rows
without original logical keys remain opaque even after metadata expansion.
Neither transformation nor raw root agreement grants current-pin complete typed
state/STF parity. Authored current-schema corpora remain separately labelled.

Run `make unit SUITE=state_current_source_metadata`; Python tests reproduce the
audit and metadata fixture directly from exact SHA-verified pinned Git blobs.
Regeneration: `python3 tests/state_current_source_audit.py`. No upstream script is
executed and no published root is replaced by a derived expectation.

Observed locally: all 26 native historical/derived pairs, two independent source
audit checks, inventory and pinned formatting passed under checked ARC/Clang
release on macOS ARM64. Original root verification is independent Python evidence;
exact-head Linux CI and complete current-pin upstream/STF parity remain separate.
