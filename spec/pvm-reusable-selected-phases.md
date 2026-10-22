# Reusable selected account, provision and global phases

Authority: Gray Paper `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, current
accpar and fnprovide. Later authenticated rounds need the same M/n, original
provision and global selection algorithms as initial execution. Extract each
algorithm once into an explicit-input Phase that retains its exact complete
coverage/preceding phase, without importing concrete initial-round ownership.

Keep the existing Stage types as separate private immutable initial-block wrappers.
Their factories require the same genuine admitted guest/account/provision owners,
retain authenticated profile validation even for empty producers, and delegate
once to the reusable implementation. Public Stage policy/info/error shapes remain
compatible; success/failure payloads stay private and guarded. Pure phases cannot
construct Stage or completed-block/history ownership.

No protocol interpretation, pin, guest execution or selected-map behavior changes.
Verify the complete signed initial pipeline and every existing parent refusal,
plus a genuine explicit-input chain, private fields, default extraction guards,
Phase-to-Stage rejection and fresh ARC. The reusable chain is preparation for
current authenticated continuation/reentry, final statistics/time and publication;
it does not independently authenticate caller frame/Parameters choices.

Checked macOS ARC/Clang evidence: genuine explicit-input reuse and the signed
account/provision/global/current-round consumers, plus the existing explicit guest
runner, all pass fresh1,000-cycle ARC release checks. All288 production modules,
73 affected runtime extraction guards (including29 new pure-phase cases),26
privacy/authority compiler guards, inventory and canonical formatting pass.
The explicit identity witness uses actual halt-only guests under its zero-provision
policy; the generic batch helper intentionally provides values and therefore
requires different execution limits. Evidence: `build/reusable-selected-phases-*`.
Exact-head Linux CI and full current JAM parity remain separate.
