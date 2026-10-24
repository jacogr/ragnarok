# Whole-map manager handoff and sequential authority

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` bless16 and exceptional checkpoint selection.

Five originals cover handoff99-to42, panic rollback, checkpoint-panic retention,
self-manager retention and an unauthorized99 caller under original manager42.
Every guest attempts a second bless restoring99 after its first call. Authority
must be read from the actual earlier mutation: a manager that hands off authority
cannot reclaim it. The checkpoint lies between these two attempts. Two report
releases check that the selected role tuple remains authoritative across blocks.

Both cores retain assigner0, delegator/registrar0 and an empty allowance dictionary.
There is one potential role writer and no conflicting allowance values; the
AmbiguousPrivileges gate remains unchanged. Exact C12 wire bytes, all other global
chapters, metadata, namespaces, N/T/G, timestamps, blocks and roots are independently
calculated over30 signed transitions.

Checked ARC/Clang cases and independent role-reclamation, fixed-role and metadata
invariants pass locally with ejection regressions, pinned formatting and inventory.
Linux CI is separate. Production logic, dependency pins and older fixtures remain
unchanged. M1 framing is complete; checkpoint reconstruction and epoch/lifecycle
composition remain subsequent parity work.
