# Current final-present account timestamps

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, second
intermediate account state after accumulation statistics. Update lastAccumulation
only for accounts in the final selected domain whose service ID belongs to S.
A missing/ejected service may have transfer/work statistics and must stay absent.

Derive sorted IDs from genuine current statistics, state from its completed
terminal sequence and time from the admitted header. Reuse the existing pure
projector's exact metadata validation, present-only byte accounting and no-op
handling. Apply on a private fork with inherited storage ceilings; preserve the
actual failed projector or store reason and expose no earlier timestamp prefix.
Default/pure/foreign source state cannot replace that owned graph.

Completion witnesses: normal work/transfer services updated to admitted time,
skipped work with N=1/G=0 updated, all-zero services unchanged, ejected recipient
with X=1 absent, present-only byte capacity, backend rollback, source immutability,
strict extraction/nominal boundaries and fresh ARC. Final C13/output/history and
whole-block publication remain subsequent work.

Local validation: 292/292 source modules; new native timestamp suite and the
sequence-driver/continuation consumers; seven runtime extraction guards and six
privacy/nominal compiler rejections; 1,000-cycle ARC evidence; inventory and
formatting passed on macOS ARC/Clang. This is separate from Linux CI evidence.
