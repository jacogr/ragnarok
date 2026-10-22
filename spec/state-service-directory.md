# Complete-source service directory

Scope: immutable sorted identity lookup over an exact complete `StateInventory`.
The service domain and account dictionary follow pinned Gray Paper
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, `text/accounts.tex`, eq:serviceaccounts.
This is a logical query index; no storage API/format or root-policy change occurs.

Construction bounds service rows, retained native descriptor bytes and full
worst-case insertion comparisons before allocation. Halving an even factor and
dividing by the other proves n(n-1)/2 without wrapping. In-place insertion moves
fixed descriptors only. Exact complete-map matching has already rejected duplicate
physical metadata keys, so one service identity has one original capture ordinal.
Retained-byte accounting covers the directory array, not the pre-existing source.

Binary search returns the original inventory ordinal, or `NoService` established
from complete source enumeration. Default provenance, absence, bad sorted index
and resource refusal remain separate. Sorted indices have their own full-width
nominal type. Private immutable data retains the exact original inventory; copied
entries/accounting do not mutate it or grant source-construction authority.

Native coverage includes descending input order, original ordinal mapping, exact
and short count/byte/work limits, complete absence at domain boundaries, maximal
sorted indices, vacuous empty complete directories, hash-disabled operation,
1,000 ARC retirements, strict payload guards and privacy/nominal rejection.
Run `make unit SUITE=state_service_directory`.

Observed locally: native suite passed including zero/singleton/even/odd comparison
ceilings and exact/short budgets. 1,000 ARC cycles retained 270,912 bytes before
and after. Three strict runtime guards, four compiler rejections and genuine
complete-source lookup control passed; inventory and pinned formatting passed.
Pinned alias checking requires explicit fixed-field copies between array slots;
test fixture order is built in a separate array rather than an aliased swap.
