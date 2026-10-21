# Bounded refinement host execution

## Current unreleased dispatch

The current [Gray Paper upgrade](graypaper-unreleased-upgrade.md) uses
`1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`. Inner hosts are compile9,
machine10, peek11, poke12, pages13, invoke14 and expunge15. Compile now supports
both memory and historical database sources; the package item determines self
and the retained package context determines the lookup anchor. See
[inner lifecycle](pvm-inner-lifecycle.md) for source clipping, gas and bounds.
The source reader remains read-only and grants no block-state publication.
Historical release details below retain their original evidence and host IDs.

Pins: GP 0.8.0 `07f041dabd073f9018b418e9ee72e79dd2185401`,
`pvm_invocations.tex` refinemutator F and Omega_G/Y/H/E, vectors
`d3c089c9a1d5352ad353626d7a2db8589f137b2a`. Grow_heap alone retains the
explicit #533/#538 adoption in pvm-accumulation-heap.md. No pins or gates change.

Prepare an immutable execution environment from an already initialized caller-owned
CPU, complete state snapshot, owned package/current item, parameters, trace, external
input tables, heap geometry and export offset. Derive lookup self/anchor and fetch
current item from the same package selection. Capture zero entropy, present authorizer
trace, canonical package/parameters and all external inputs. Validate table shapes and
extrinsic lengths against package manifests before copying. Caller supplies authenticated
external bytes and trusted machine/code/arguments/geometry; this is not a Psi_R code
eligibility/bootstrap certificate, BAD/BIG decision or full invocation wrapper.

Execution always starts from the original immutable CPU and fresh empty exports.
Host 0, 1, 2, 7 and 8 delegate to shared gas, adopted heap, fetch, historical lookup and
export implementations. Extract heap logic from accumulation into one shared primitive
without changing accumulation behavior. Hosts 9/14 now use the invocation-local
[inner lifecycle](pvm-inner-lifecycle.md). Host 12 uses [inner pages](pvm-inner-pages.md). Hosts 10/11 use [inner transfers](pvm-inner-transfer.md). Host 13 performs [bounded inner invocation](pvm-inner-invoke.md), retaining exact
nested StepError refusals through the existing ExecutionFailure alternative. All other full-width identifiers use
F's unknown fallback, including accumulation-only IDs, and assign WHAT even on OOG.

Step/call/gas-analysis/copy/export budgets are independent local limits. Engine refusal
retains its exact StepError; local failures return no partial CPU or exports. Successful
runs retain raw guest outcomes; only Halt retains exports. Panic/OOG/Fault expose empty
exports. Halt return-buffer copying and gas/output normalization remain separate, as do
state composition and publication. No partial/light-state claim or state writes.

Completion: real multi-host guests, package/current lookup and fetch selection, zero
entropy/trace/input capture, heap parity, protocol unknown versus known unsupported,
paid panic/OOG versus local refusal, engine budgets, export retention/discard, detached
owners/repeat runs, optimized result guards, compiler privacy/nominal rejection and
fresh 1,000-cycle ARC release. Verify shared heap accumulation consumers.

Local evidence: checked optimized native `pvm_refinement_dispatch`,
`pvm_accumulation_heap` and `pvm_accumulation_dispatch` pass, each with fresh
1,000-cycle unchanged ARC occupancy. Six optimized runtime result/reason guards,
five compiler privacy/nominal rejections, verification inventory, 19 inventory/provenance
Python tests and pinned formatting pass. These are local macOS results;
exact-head Linux CI remains independent.

Bootstrap, normalization and bounded inner hosts now have their own feature contracts.
Next: work-package report integration. M1 framing is complete; full state serialization and complete
refinement/whole-block parity remain open.
