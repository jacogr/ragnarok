# Current sealed-header recent history

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, recent
history and accumulation-output root equations. Derive sealed header, exact
parent state commitment, newly guaranteed package/segment dictionary and current
terminal output union from one genuine current ready-state owner. The processed
ready prefix is not the newly guaranteed dictionary. Reuse existing canonical
history codec, ordered output-root and history/belt algorithms without changing
their domains or pins.

Check core/profile, original history/header/output cardinalities and complete
wire capacities before copying/hashing. Preserve exact stored C3 consumption and
actual header/codec/root/history/store failures. Apply only C3 on a private fork
preserving C14/C15/C16 and timestamped account state. Retain the current proof
source separately from legacy history/completion types. Fresh encoded entries
cannot mutate retained state. C13, preimages and complete stage composition remain
subsequent work.

Completion witnesses: processed report excluded from guarantee dictionary, real
incoming guarantee included, exact sealed-header identity, output-root/belt
binding, parent correction, independent count/byte/frame ceilings, hash and late
store rollback, default/private/nominal guards and ARC release.

Local macOS ARC/Clang validation passed: 296 source modules; current recent/ready
and existing recent-history native suites; twelve runtime extraction probes and
six privacy/nominal compiler rejections; 1,000-cycle ARC evidence; inventory and
formatting. Linux CI and complete JAM parity remain separate evidence.
