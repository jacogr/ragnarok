# Independent full-width account deposit corpus

This evidence increment checks existing pinned accounts eq:deposits arithmetic,
not a new production API or semantic rule. The SHA-pinned 1,024-row fixture is
reproducibly authored by an independent Python arbitrary-precision direct equation
and complete pool sum. It mixes literal cancellation witnesses, safe small values,
full-width sums and products, and partial/full gratis cancellation. No production
helper generates expected values and no Python protocol runtime is introduced.

Native tests require exact refusal or exact nominal minimum and pool coverage for
every record. Test transport is fixed little-endian words plus explicit flags,
with no connection to a wire schema. Python checks authored tiny witnesses,
fixture regeneration, exact row extent and both representable/overflow populations.
Existing production contracts/privacy controls are unchanged and their prior
focused results remain applicable. Run `make unit SUITE=state_account_deposit_corpus`;
Python reference tests run through ordinary unittest discovery.

Observed locally: selected native suite, inventory and pinned formatting passed. Existing production contract/privacy controls are unchanged. Targeted independent Python reference tests passed.
