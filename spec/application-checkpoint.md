# Application checkpoint context and lifecycle

## Scope and authority

Use the existing complete-map StateStore and local checkpoint primitives. This
work does not modify/import/adopt the independent storage trie, add adapters or
prepare storage integration. PVM execution/certificates remain separate. No GP
0.8.0 protocol equation, pinned vector or network representation changes.

## Captured scalar identity

Capture only from an initialized ApplicationChain selected head and its exact
immutable canonical map owner, using sameStateSnapshot rather than root equality.
Retain sealed block hash, complete posterior map root, nominal block time and the
entire immutable 122-byte parameter tuple. No source map, history or header graph
is retained. Defaults never compare equal or expose initialized accessors.

These facts identify a persistence context; they do not prove consensus validity,
finality or authority to adopt recovered state. Header prior-state roots cannot
replace the selected posterior map root. Recovery must eventually compare against
independent trusted context, not metadata supplied by the same file.

## Completion checks and next layer

Native tests compare exact selected fields, independently changed headers, maps
and profiles, detached producer lifetimes and 1,000 scalar-capture release cycles.
Strict extraction and privacy probes preserve initialization gates. The fixture
is the existing checked-in complete RPC chainspec with an explicit hash contract;
structural fixture variants do not claim valid executed successors.

Next: canonical bounded local encoding of the scalar identity, then an application
envelope binding that context to existing complete checkpoint bytes. Application
startup/shutdown and dispatcher work must remain explicit and nonblocking; no
serialization occurs inside transport callbacks. M1 framing remains complete;
full T(state), whole-block parity and light-state persistence remain open.

## Canonical local identity encoding

The fixed 238-byte local metadata encoding is RAGNAROK-APP-V1 plus LF, sealed
block hash (32), posterior state root (32), E4 little-endian time, all 122 encoded
parameter bytes, then Blake2b-256 of the preceding 206 bytes. The checksum detects
corruption and does not authenticate a head. Decode accepts one exact version and
extent, validates the full parameter tuple and exposes no metadata on failure.
Decoded initialized metadata must still be compared with independent caller
context; a checksum-valid attacker-chosen identity is not a recovery trust anchor.

The native suite uses independently encoded hashlib bytes and existing RPC root/
header goldens, every truncation/octet tamper, exact/short ceilings, valid-checksum
context mismatch, invalid profiles and repeated owned-buffer release. No JAM wire
encoding, chain identity, canonical adoption or storage backend changes.

## Complete application envelope

The application envelope is the fixed 238-byte identity immediately followed by
one existing canonical RAGNAROK-FULL-V1 complete-map checkpoint. The single output
ceiling covers both parts and is bounded by native sequence extent before allocation.
Capture requires exact application head/map owner agreement. Missing context,
metadata/backend failure and complete-map refusal return only selected typed reasons.
Independent golden bytes come from original fixture keys/values and published RPC
root/header expectations. The native suite checks exact whole bytes, every short
output budget, context/map changes and repeated release. No file I/O, canonical
adoption, new database schema or storage integration occurs in this layer.
