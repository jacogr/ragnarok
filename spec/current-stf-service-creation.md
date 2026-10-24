# Whole-map service creation and public cursors

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` initialization/new 20, eq:newserviceindex, and current request-length domain.

Five originals cover halt, panic rollback, checkpoint-panic retention, two same-
invocation creations and the reserved length 2^32-2 refusal. New public IDs use
Blake2b(compact creator || posterior eta0 || compact slot), first-four-octet LE
reduction into [65536,2^32-256), then the public 42-step cursor. Initial membership
contains only reserved 42/99, so both explicitly derived public candidates are free.
The frozen first/second IDs are 1187033478/1187033520; no observed native ID is used.

Each retained child publishes exact 105-byte metadata and one empty code request:
code hash/length match the independently encoded halt program; minimum gas 100/19,
two items, 81+length bytes, created 4, last-accumulation 0, parent/supervisor 99 with
supervisor incarnation 0. No preimage, storage or activity row is invented. These
explicit test-chain parameters have zero deposits, so child balances and creator
debits are zero. Two children reach the existing four-service metadata ceiling;
local original-account capture ceilings explicitly admit that complete map.

Twenty signed transitions compare exact P/B/O, roots, child namespaces, source
N/T/G and timestamps. Post-publication qualification names only the expected
created IDs and their sole request; every full-map byte remains independently
compared. Earlier fixtures, upstream vectors, production logic and pins stay
unchanged. M1 framing is complete; request/provision/ejection lifecycle and full
JAM serialization/parity remain subsequent work.

Local checked ARC/Clang validation passes all 20 creation transitions and existing
upgrade, supervisor and memo regressions. Independent fixed ID/cursor, child
metadata/request and no-participation invariants pass, with pinned formatting and
inventory. Local macOS evidence remains distinct from exact-head Linux CI.

The shared driver now selects literal families through a private named helper.
This avoids a pinned formatter defect on a deeply nested inline expression;
two consecutive formatter passes are identical. All eight affected guest-family
corpora pass after the refactor, including original report guests and transfer
pool/admission branches. No formatter, compiler or toolchain source is changed.
