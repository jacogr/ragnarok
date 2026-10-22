# Frozen whole-account audit execution

Scope: execute the exact original source and policies of a complete account audit
plan, checking existing pinned accounts eq:deposits and eq:preimageconstraints
predicates under Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`.

Only an initialized frozen plan is accepted. No caller source or quota argument
can substitute after planning. All resource policies have been admitted before
execution can copy/hash a preimage. Existing semantic checks run deterministically:
footprints, request linkage, content hashes, then exact-owner join. Each failed
phase preserves its actual guarded nested failure; no successful prefix escapes.
Defaults are not vacuous empty audits. Genuine empty complete plans succeed.

Success retains the original complete inventory through targeted same-source
account-invariant evidence. It does not certify economic coverage, history order,
global chapter semantics, root trust, application installation or full STF parity.
No worker, Services or storage API/format changes occur.

Native verification distinguishes early zero-hash footprint/linkage failures,
late content hash mismatch versus backend refusal, original source identity,
caller quota mutation after planning, complete empty success, 1,000 ARC retirements
and strict payload/phase/private/nominal guards. Run `make unit SUITE=state_account_audit_execution`.

Observed locally: selected native suite, 6 strict runtime guards, 7 exact compiler rejections and genuine positive control passed; inventory and pinned formatting passed. 1,000 ARC cycles retained 335,728 bytes before and after.
