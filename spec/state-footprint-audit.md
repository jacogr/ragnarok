# Source-bound account footprint audit

Scope: `src/state/footprint_audit.nim` checks only the dependent item and octet fields
of every service in an existing complete, exact-matched `StateInventory`.
Pinned Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
`text/accounts.tex`, eq:deposits supplies the equations implemented by
`account_footprint.nim`. Preimages do not contribute a separate payload term.

Service and work limits are explicit. Work charges each row, storage fact and
request fact, including empty values, before any dependent equation is checked.
An insufficient budget wins over a later malformed dependent value. Byte sums,
products and E4/E8 widths are checked without wrapping. Default source, resource
refusal, overflow, item mismatch and octet mismatch remain separate. Mismatches
retain only the offending nominal service identity and original inventory ordinal.
No prefix or source-bearing success escapes failure.

Success privately retains the exact original immutable inventory and exposes only
fixed work observations, the original owner and certified fixed footprints.
Default certificates are invalid. Payload and offender accessors have checked
runtime contracts; full-width service ordinals are validated before narrowing.
No hashes, copied payloads or additional arrays are needed. This certificate does
not certify preimage content/linkage, economic coverage, a trusted root or STF validity.

Verification: native `make unit SUITE=state_footprint_audit` uses independently
encoded complete sources, literal 3-item/121-octet expectations, distinct structural
sources with wrong dependent fields, exact/short budgets, empty complete inventory,
full-width ordinal refusal, a hash-disabled observer and 1,000 ARC retirements.
Strict failure probes include genuine complete-source success; compiler fixtures
reject private payload/source/location access and wrong nominal indices.

Observed locally: native suite passed with 1,000 ARC cycles (272,640 bytes before
and after); four strict runtime refusals, seven exact compiler rejections and
the genuine positive control passed. Registration and pinned format checks passed.
An attempted failure template nested inside the service loop hit the pinned
compiler's internal semantic assertion; explicit variant returns preserve the
same checked failure paths without compiler or dependency changes.
