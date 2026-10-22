# Independent full-width account footprint corpus

This evidence increment checks the existing pinned accounts eq:deposits item/octet
formula without a production API or semantic change. A reproducible SHA-pinned
2,048-row corpus uses independent Python arbitrary-precision direct equations,
separate E4/E8 output-domain tests, literal exact/one-over cases and deterministic
small/full-width shapes. No checked production helper generates expected values.

Every native record requires exact success fields or explicit Overflow, without
extracting failed payloads. The shared fixed-word hex transport is test-only;
Python tests verify authored witnesses, fixture reproduction, exact extent and
both positive/overflow populations. Existing production contract/privacy evidence
remains applicable. Run `make unit SUITE=state_account_footprint_corpus`; Python
reference tests run through ordinary unittest discovery. This is arithmetic
coverage, not authenticated input or full state/STF parity.

Observed locally: selected native suite, inventory and pinned formatting passed. Existing production contract/privacy controls are unchanged. Targeted independent Python reference tests passed.
