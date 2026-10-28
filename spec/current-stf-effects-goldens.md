# Whole-map STF goldens for nonempty extrinsics and guest effects

Scope: five authored two-child, same-epoch chains with complete current state. Each first child
submits two requested preimages and executes two real guests; each second child executes those
guests again with an empty body. The Gray Paper pin remains
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, with Draft35 Thin v1/ark-vrf 0.6.0 and vectors
`23061ae1f9b51171c01387e7dde0f15794c98e24`. No production protocol behavior or pin changes.

## Cases and independent calculations

The cases create raw storage key7, replace an existing five-byte value, delete an existing
two-byte value, roll back an uncheckpointed write/yield on panic, and retain a checkpointed
write/yield on panic. The writing service is 99 with an original balance of 1,000,000; service42
executes a halt guest. Each service has one 100,000-gas always-accumulate allowance. The
conflicting-allowance `AmbiguousPrivileges` guard is unchanged.

`tests/fixtures/current-stf-effects.json` freezes the original complete parent inputs produced by
the maintained native fixture builder. Every parent includes all sixteen globals, current
105-byte metadata, a genuine ring root and explicit code/storage/preimage/request namespaces.
Original code preimages and available code histories precede child signing. The two new blob
requests are outstanding in the original parent. No published source or historical fixture is
rewritten, expanded, re-signed or treated as a current valid trace.

`tests/current_stf_effects_oracle.py` independently assembles the literal guest code, envelope
and opcode mask, verifies those exact bytes against the original metadata/code namespace, and
constructs each child with the mathematical Thin reference. Expected complete successor maps
use only original inputs and pinned equations. The second reference parent is the first
**calculated** successor. Neither native output nor a production-derived expected phase map
supplies reference gas, footprints, timestamps, statistics, output commitments or trie roots.

The equations cover:

- `header.tex`: five-family extrinsic commitment with the specified preimage hash projection,
  exact preimage wire bytes, parent root/header binding, Thin entropy proof and seal;
- `pvm_invocations.tex`: self storage write/delete, `34 + key length + value length` footprint,
  funded metadata updates, yield, checkpoint and regular/exceptional implication selection;
- `pvm.tex` and `definitions.tex`: independent table-driven basic-block pipeline gas plus host
  write `2442 + ceil(3358*k/1024) + ceil(216*v/1024)`, yield98 and checkpoint103;
- current accumulation: positive-gas service statistics and last-accumulation timestamps on both
  guests, including a panicking service; selected output log and nonzero output Merklization;
- preimage admission/fulfillment: ordered unique prior-solicited blobs become available at slot2
  after accumulation, preserving pre-reserved storage counters and the first availability slot
  on the next child;
- shared independent no-report STF equations: entropy, time, queue-indexed authorizer pools,
  parent-history correction, header identity, output-root MMR carries and validator activity.

The independent gas simulator reads the pinned GP table as data, with the established wrapped-target
pricing interpretation recorded in [PVM gas](pvm-gas.md). Charges are 22 for the halt guest;
2650 for create/replace/uncheckpointed panic, 2649 for deletion and 2754 for checkpointed panic.
Rolled-back effects do not erase consumed gas. The successful storage deltas are respectively
`(+1 item,+38 bytes)`, `(0 items,-2 bytes)` and `(-1 item,-37 bytes)`; checkpointed panic retains
the create delta, while uncheckpointed panic retains neither storage nor yield.

The frozen fixture records each independently calculated root and complete-checkpoint SHA-256.
The local V1 checkpoint is only a complete-map comparison envelope. Every expected input/output
wire is generated before native compilation/execution, and comparison requires every byte.

## Native verification and limits

`tests/native/state_current_stf_effects_driver.nim` independently constructs the same original maps and
signed child inputs. Each actual child runs through candidate admission, real PVM host execution,
current completion, complete current-state/global qualification and actual chain installation.
Explicit supplied declarations cover code, unchanged namespaces, new preimages and selected
storage effects; they must match the entire actual successor map. Retained original snapshots
remain unchanged. Each case also signs a first child whose final blob is unsolicited, requires
typed `CompletionFailure`, and verifies the original complete map is untouched.

The source-owned `current_stf_effects_corpus` uses the normal checked ARC/Clang non-LTO corpus
builder, production libraries, fixture hash contracts and complete expected/observed comparison.
It runs in `make check-unit`; independent reference and negative cases run in `make check-python`.
The prior twenty empty-body whole-map cases remain in their original registered corpus.

Observed locally on macOS ARM64, checked ARC/Clang release: both registered corpora passed
exact complete output comparison (ten effect-bearing transitions plus the prior twenty empty-body
transitions). All five native late-preimage controls refused with `CompletionFailure` and preserved
the original complete map. Eighteen affected Python reference/harness checks passed; the final
admission-ordering changes reproduced the same native output hash and passed their fourteen
affected checks. Inventory and pinned formatting are recorded with this review unit; exact-head
Linux CI is separate.

This is complete-map parity for these literal guests and preimage-only nonempty extrinsics.
General PVM execution, reports/guarantees/assurances/disputes/tickets, epoch changes, transfers,
service lifecycle and all other host effects need additional independent whole-map cases.
The [epoch/ticket goldens](current-stf-epoch-goldens.md) now cover selected ticket admission,
epoch/marker/sealing paths and multi-epoch skipping separately from these literal guests.
The separately documented published signed-trace and metadata limitations remain open.
