# Whole-map transfer admission and gas boundaries

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` transfer preflight/charges and `accumulation.tex` accseq/accone.

Fourteen authored originals cover absent source/destination, unauthorized funding,
one-token insufficient funding, undefined pool flags, a fixed memo range crossing
uint64, a below-minimum offer, exact minimum delivery, exact outgoing host budget
and one above, recipient block budget one short/exact, and full-width endpoint
values whose low 32 bits alias an existing service. The latter cannot become a
valid lookup after narrowing. All cases process the admitted work item; only a
retained successful transfer debits and later credits its seven tokens.

With 100000 report gas, an outgoing offer 99322 fits exactly after the independent
103 instruction gas plus 575 host fee. Offer 99323 exhausts the host budget without
producing a record. Accepted incoming offers 10 and 21 cannot prepay the recipient's
22-gas block: T=1/G=0 and credited balance/timestamp still survive. Offer 22 executes
exactly that block. Preflight-only refusals cost 678 and preserve both balances.
These whole-map witnesses check observable gas and state; exact host return codes
remain covered by the component dispatch tests.

Fifty-six signed transitions compare every P/B/O byte, root, balance, N/T/G,
timestamp and no-replay result against independently calculated maps. Earlier
fixtures, upstream vectors, production logic and dependency pins stay unchanged.
M1 framing is complete; service lifecycle is next, while full JAM serialization
and historical trace parity remain open.

Local checked ARC/Clang validation passes the 56 boundary transitions and earlier
transfer, forwarding and pool corpora. Independent map invariants and current CI
matrix safeguards pass, along with pinned formatting and source-owned inventory.
These are local macOS results; exact-head Linux CI remains separate.
