# JAMNP-S configured-genesis ALPN

Authority: JAMNP-S at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`, ALPN.
Ordinary peer, mesh, download, ancestor and continuous-sync commands must derive their base
identifier from the first eight lower-case hexadecimal nibbles of the configured genesis
header hash. A restored current head, checkpoint or database tip cannot replace that identity.
Explicit overrides must name the same chain; the builder suffix remains permitted. Missing
serialized genesis header on an explicitly selected chain refuses JAM transport startup. Commands with
no selected chain retain the isolated development domain.

Capture the derived identifier alongside Services startup configuration, before journal replay
or light-state metadata retirement. Retain only the bounded string, not another genesis map.
Preserve ownership hooks and clear the value on close/failure. All ordinary dialing, ancestor
retrieval and reconnect paths consume that captured domain. No dependency pin changes.

Completion checks: independent nibble fixtures and cross-chain/version refusal; full-state and
recovered-genesis selection, stable domain as best head advances; existing command TLS and sync
fixtures adjusted to negotiate their actual configured genesis. Builder capacity/role dispatch
and validator connectivity remain separate work.

Independent process fixtures hash their authored genesis header with Python hashlib and native
standard hex formatting. RPC fixtures capture the domain before mutating a private chain file.
Parameters-only metadata without a serialized header does not identify a JAM network and cannot open a JAM listener; the
existing component metadata APIs retain their optional/unavailable contracts.

Stateless network identity hashes the bounded configured header without constructing a state
map. Full and light state startup retain their independent complete-state/trust validation.
