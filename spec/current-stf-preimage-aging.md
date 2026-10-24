# Whole-map strict preimage aging

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, solicit25,
forget26 and expunge period=maxLookupAnchorAge+4800. This explicit tiny profile
sets maxLookupAnchorAge0, hence4800, rather than using the earlier maximal field.

Five chains start with an honestly supplied R preimage and known history. Real
report releases at4801/4803 test equality at removedAt1+4800 and strict expiry
beyond it. Exact equality preserves history/P and the two-item82-byte footprint.
Expired two-slot forgetting removes Q/P and releases both reserved items. Real
solicit restoration at4801 appends a third timestamp; later forgetting compacts
that history to[4801,4803] while preserving P and the footprint. A live history
becomes unavailable at4801 and cannot expire again at4803. Panic and checkpoint
controls verify selected rollback and deletion.

The signed epoch jump, boundary report, assurance attribution, entropy, statistics
and all later full maps are calculated independently. Report operands now use a
literal low-byte slot pattern, preserving all existing small-slot originals while
allowing full uint32 timeslots. Thirty native transitions compare blocks, complete
checkpoint bytes, roots and exact namespace/account effects. Existing request and
epoch cases are regressions. Production logic, historical fixtures and pins remain
unchanged. Local checked ARC/Clang evidence is separate from Linux CI.
