# Checked dependent account footprint

Authority: current GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, accounts.tex
eq:deposits. Compute items = storage-count + 2 request-count, and octets =
34 storage-count + 81 request-count + storage-key bytes + storage-value bytes +
advertised request bytes. Stored preimage payloads add no independent term.

Check E4 item representability before multiplication/addition and E8 octet
representability before each nonnegative product/sum. Nimony wrapping is never
used as overflow detection. Return private reason-only Overflow/default outcomes
and success-guarded nominal AccountStorageItems/AccountStorageBytes values.
This pure arithmetic accepts explicit component aggregates; it neither authenticates
them nor certifies account metadata, balance, deposits, sources or STF validity.

Completion uses independent integer-reference literals, zero and mixed shapes,
maximal item/octet values, exact/one-over boundaries for every sum, monotonic
small cases, strict result guards and nominal item-versus-byte rejection. No
heap or hash work is required; ownership suites belong to the source-bound adapter.

Local checked macOS native and semantic tests pass mixed literal equations,
maximal E4 counts/E8 octets, every exact/overflow sum and monotonic payload cases.
Two strict runtime guards, a genuine representable control and three compiler
privacy/unit rejections pass. Inventory and pinned formatting pass. Evidence:
`build/state-account-footprint-*`, `build/tests/state_account_footprint/`.
This does not authenticate aggregate inputs or establish full state/STF parity.
