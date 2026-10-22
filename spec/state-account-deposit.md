# Exact account minimum balance arithmetic

Scope: pure constant-work mathematical observations under pinned Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `text/accounts.tex`, eq:deposits.
Compute max(0, base + item-rate * items + octet-rate * bytes - gratis).
Explicit schedules and footprints are unauthenticated mathematical inputs;
no protocol parameter selection or global account funding invariant is implied.

Credit is consumed against complete product units using division, then any
remaining partial unit, before checking residual representability. Every product
and addition is proved by quotient/capacity checks. A large intermediate deposit
is accepted when gratis makes the final E8 threshold representable. For example,
2 * UINT64_MAX - UINT64_MAX equals UINT64_MAX. A third such term overflows.
Zero costs consume no credit. Default/overflow results expose no payload;
representable success retains nominal AccountBalance with checked extraction.

The supervisor section permits both liquid and protected pools for footprint
coverage. Comparison uses short-circuit liquid coverage or protected coverage of
the remaining deficit, avoiding an overflowing pool sum. This is an observation,
not rejection of every stored underfunded service. No existing PVM deposit or
Services behavior changes; the arithmetic reader has no heap/source ownership.

Native verification includes independent safe small-integer equations, literal
mixed fields, full-width exact/one-over cancellation and residual products,
zero rates/credit, maximal item/byte domains, exhaustive small pool comparisons,
strict payload failures and private/unit compiler rejection. Run
`make unit SUITE=state_account_deposit`.

Observed locally: selected native suite, 2 strict runtime guards, 3 exact compiler rejections and genuine positive control passed; inventory and pinned formatting passed.
