# Whole-map supervised transfer scheduling

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`accumulation.tex` fnpartitionxfers/accseq and `accounts.tex` effective supervisor.

Two same-service reports each declare 200000 gas against a 300000 block budget.
The first source invocation emits a real funded transfer; actual gas/refund permits
the next report in another round. With a matching live supervisor, incoming credits
wait while that supervisor executes and both duplicates arrive in one later
transfer-only invocation. Without that conflict, two recipient invocations occur.
Stale incarnation, missing supervisor and self-supervisor originals independently
exercise the effective-supervisor fallback. Both paths debit and credit fourteen
tokens exactly once, but their C13 recipient gas differs (22 versus 44).

Twenty complete signed transitions are independently calculated before native
execution. Full maps, roots, C13 N/T/G, timestamps and processed histories are
compared exactly. Earlier fixtures and upstream vectors remain unchanged.
M1 framing is complete; repeated forwarding, wider lifecycle and full JAM parity
remain later work.

Local checked ARC/Clang verification passes all twenty exact P/B/O transitions,
plus the prior transfer and report-driven guest regressions. Independent Python
invariants freeze per-service N/T/G and both balances; formatting and source-owned
inventory checks pass. This local macOS evidence does not claim Linux CI parity.
