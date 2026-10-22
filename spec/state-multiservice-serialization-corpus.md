# Independent multi-service complete serialization

Under Gray Paper pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, extend the
[complete typed corpus](state-complete-serialization-corpus.md) with eight
four-service complete maps. All metadata and storage/preimage/request identities
remain typed, with wide/zero service IDs and independently expected checkpoint
bytes and roots. Every source runs all 24 declaration orders: 192 comparisons of
complete sorted checkpoint bytes plus explicit-root typed restoration.

Test-only logical input helpers are shared with the original single-service
suite; Python independently builds expected keys, metadata, trie and envelope.
The original SHA-pinned single-service and refusal fixtures remain byte-identical.
No production behavior, API, storage format, RPC or root policy changes. These
authored maps still do not establish upstream current-pin state/STF parity.

Run `make unit SUITE=state_multiservice_serialization` and the affected
`make unit SUITE=state_complete_serialization`; Python discovery checks both
fixtures and source-order independence.

Observed locally: all 192 multi-service cases, the 32-case single-service
regression, five Python reference checks, inventory and pinned formatting passed
under checked ARC/Clang release on macOS ARM64. Linux CI remains separate.
