# Accumulation terminal outcome normalization

## Scope and completion contract

Implement pinned GP 0.8.0 revision `07f041dabd073f9018b418e9ee72e79dd2185401`,
`text/pvm.tex` Psi_M/R and `text/pvm_invocations.tex` Psi_A/C. Accept only an
immutable completed `AccumulationDispatchResult`, keeping its CPU and effects bound.
Halt selects regular effects; panic, page fault (Psi_M's otherwise branch) and OOG
select exceptional effects. Gas used is initial credit minus max(final gas, 0),
never initial credit plus terminal debt. Only an accessible exactly 32-byte halt
return replaces the selected yield; other lengths and unreadable return ranges
retain the regular yield. Bound that copy to 32 bytes without materializing other
return blobs. Preserve post-credit account/provenance owners and do not publish state.

The pinned hash-return branch names `imXY`'s provisions, although `imXY` is a pair
and provisions belong to its individual dimensions. Do not infer which dimension
was intended. Current dispatch cannot add provisions; both dimensions have empty
sets. Require both sets empty for this branch, returning a typed
`AmbiguousProvisions` gate otherwise. A focused pending specification test records
that nonempty-provision semantics remain unresolved; no pin upgrade is implied.

Completion tests exercise actual guest halt/panic/fault/OOG histories, checkpoint
selection, empty/31/32/33-byte returns, zero/nonzero override commitments, unreadable
and full-width pointers, bounded gas usage with host debt and instruction OOG,
local-dispatch refusal, immutability, release cycles and guarded default/failed
result extraction. These are authored equation witnesses, not complete Psi_A/STF
vector parity. Other host calls and persistent publication remain separate.


## Ownership and API

`normalizeAccumulationOutcome` takes the private completed dispatch result rather
than detached CPU/effect inputs. `AccumulationOutcome` retains one final context
and copied metadata. `outcomeContext` includes any halt-return override already
applied to its yield; it never exposes a stale pre-override yield alongside final
metadata. `outcomeInfo` reports termination, selected dimension, service, capped
gas use and supported effect counts. Default owners and refused results have no
successful payload. Earlier dispatch results and normalized copies stay immutable.

Gas is obtained from the original effect source's bootstrap service, so callers
cannot substitute the initial credit. No negative-debt addition or signed narrowing
is needed: the machine stores max(final gas, 0) as credit. The existing broader
signed-gas-domain gate remains unchanged.

## Local verification (2026-10-19)

The registered native outcome suite and dispatch consumer passed with pinned
Nimony, ARC and checked Clang LTO through `native_tests.run_units`. Each includes
1,000 release cycles: outcome occupied memory was 635,456 bytes before/after;
dispatch remained 676,880 bytes before/after. Four strict runtime extraction probes
and three privacy probes passed through the existing harness functions. Eleven
selected Python pin/inventory/failure/guard checks passed; one focused nonempty
provision specification test remains explicitly skipped. Inventory validation,
pinned Nim/Rust formatting and `git diff --check` passed.

Evidence is under `build/pvm-outcome/`, including `native.log`, `guards.log`,
`targeted-results.json`, Python logs and `format-check.log`. The sibling's verified
pinned tools and this checkout's existing crypto observer were reused. Complete
six-group local verification and Linux CI are not claimed.

## Remaining boundary

This completes normalization for the dispatcher's currently implemented host scope,
not full Psi_A, authenticated block execution or persistent publication. The next
bounded host tranche can connect provide (27) to existing requested-provision state
effects, retaining the nonempty hash-return gate until its specification decision.
Grow-heap and the remaining account/accumulation host calls stay separate.
