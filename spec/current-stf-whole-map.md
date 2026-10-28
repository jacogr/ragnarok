# Complete current-schema STF golden chains

Scope: two authored ten-child chains at slots 1→11, executing the real application candidate
pipeline with empty extrinsics. Gray Paper pin `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`,
Draft35 Thin v1/ark-vrf 0.6.0 and vector pin
`23061ae1f9b51171c01387e7dde0f15794c98e24` remain unchanged. The authority is the pinned
`header.tex`, `safrole.tex`, `authorization.tex`, `recent_history.tex`, `merklization.tex`,
`statistics.tex` and empty-work accumulation equations.

## Inputs and independence

`tests/fixtures/current-stf.json` freezes two original complete parent maps authored by the
maintained signed-block fixture builder, before any child root or signature is made. They contain
all sixteen chapters, two 105-byte service metadata rows and a genuine six-member ring root.
One parent has empty service namespaces (18 entries). The other has storage, preimages and request
histories for both services, including four present-empty values (30 entries). There is no C250
rollback sentinel, omitted chapter, expanded historical metadata or repaired published trace.

`tests/current_stf_oracle.py` constructs each complete child independently using the mathematical
Thin v1 reference. It calculates every expected successor from the original parent and the pinned
equations, then recursively uses that **expected** successor as the next reference parent. It never
uses an observed production successor as reference input. The fixture freezes every expected root
and complete-checkpoint SHA-256; all expected wires exist before the native build/run starts.
The original parent inputs come from the native fixture builder; they are not an independently
implemented genesis generator or external-client output.

The independent reference covers:

- C1 queue-indexed appends and newest-eight pool truncation, preserving duplicate entries;
- C3 parent-state correction, sealed-header identity, newest-eight history eviction, zero empty
  output roots, MMR carries/holes and `peak` domain bagging with independent integer Keccak;
- C6 Thin-derived entropy and C11 advancing slot;
- C13 author block counts and empty per-block core/service activity;
- exact preservation of every other global, service metadata and namespace entry.

The local V1 checkpoint is only a complete-map comparison envelope, not a JAM block/state wire
format. The oracle independently recomputes its root and compares every key/value/length byte,
including the four present-empty values. A correctly recommitted but wrong successor is still
a mismatch. Negative reference cases corrupt every entry, header/root/proof fields and envelope
extent; they cannot turn an observation into a golden answer.

## Native execution and verification

`tests/native/state_current_stf_driver.nim` independently builds the same explicit original maps and
signed child inputs. Every child goes through `prepareCurrentCandidate`, current completion and
actual chain installation. Each successor passes current-profile/global qualification and complete
supplied-service matching before installation. Retained original snapshots remain byte-identical.
This uses the existing production libraries without observer interposition or private hooks.

The normal `current_stf_corpus` in `tools/corpus_state.py` uses the shared checked ARC/Clang native
builder, fixture checksum contracts, full output comparison and hashed request/output evidence.
It is discovered by `make check-unit`; Python reference/negative cases run in `make check-python`.
The fixture itself carries original input maps plus independent golden roots/checkpoint hashes,
not hundreds of kilobytes of captured production output.

Observed locally on macOS ARM64, checked ARC/Clang release: the registered native corpus passed
all twenty transitions and exact complete output comparison. All eleven affected Python reference
and unit-harness checks, verification inventory and pinned formatting passed. The native build
uses the same checked non-LTO profile as normal unit corpora; exact-head Linux CI is separate.

This establishes complete-map parity for the authored empty-body, same-epoch chains. It does not
establish guest-effect, epoch-change, ticket/dispute/report admission or general JAM STF parity.
The [nonempty-extrinsic and guest-effect goldens](current-stf-effects-goldens.md) add selected
preimage/storage/yield/checkpoint chains; broader cases retain their focused native checks and
need further independent whole-map coverage.
The [epoch/ticket goldens](current-stf-epoch-goldens.md) additionally cover complete rotation,
ticket admission, cutoff markers, ticket/fallback sealing and multi-epoch skipping.
Published signed traces at the selected vector pin still have the separately recorded mixed-profile
credentials and historical metadata limitations; these authored cases do not repair those sources.
The conflicting-allowance `AmbiguousPrivileges` guard remains unchanged.
