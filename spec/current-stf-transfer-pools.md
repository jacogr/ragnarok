# Whole-map transfer balance pools

Authority: GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`pvm_invocations.tex` transfer and `accumulation.tex` accseq/accone/M account selection.

Eight authored originals cover all four liquid/protected source/destination pool
combinations with direct credit and deferred delivery. Only the selected source
pool is funded, so substituting another pool cannot accidentally succeed. Direct
credit uses a matching live destination supervisor; its zero memo pointer avoids
any deferred gas/input/recipient invocation. The recipient's last-accumulation
slot remains unchanged for direct credit and advances only for deferred input.
Both paths debit and credit seven tokens, preserve the unselected pools and
conserve total funds. C13 source gas is 678 for direct and 10678 for deferred;
deferred recipient T=1/G=22 is absent entirely for direct credit.

Thirty-two signed children and complete successor maps are independently frozen
before native execution. Full P/B/O bytes, roots, balances, N/T/G, timestamps and
no-replay behavior are compared exactly. New protected-balance inputs belong only
to the trusted fixture constructor; production logic, pins and earlier fixtures
remain unchanged. M1 framing is complete; transfer admission/gas boundaries and
wider service lifecycle remain next, with full serialization/JAM parity open.

Local checked ARC/Clang runs pass all 32 new transitions and the earlier transfer,
supervisor and forwarding corpora. Independent pool/participant invariants, pinned
formatting and verification inventory pass. Local macOS results remain separate
from exact-head Linux CI.
