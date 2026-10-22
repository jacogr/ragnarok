# Inner modules and machine lifecycle

Target: unreleased GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`
(VERSION0.8.0), `pvm_invocations.tex` Omega_Gamma/Omega_M/Omega_X.
Published vectors remain separately pinned release-era evidence; source hashes
are recorded in `pins.json`.

The invocation-local immutable owner holds a catalogue of prepared interpreted
program modules and up to63 running instances. Module handles are the smallest
absent natural in the union of catalogue handles and live-instance handles; at most
128 may be occupied. Preparing a module does not create an instance or compile
native code. Each dispatch run starts with an empty catalogue and instance map.

`compile`=9 accepts m,p,l,f,i in registers7–11. Implemented memory mode0 charges
1862+ceil(264*l/1024), checks the128-handle capacity, reads the complete guest range,
and applies current JAM deblob validation at entry0. Bad memory panics; malformed
code returns HUH. Unknown modes return HUH after their fixed charge. Database mode1
uses the retained complete-state historical reader at the package lookup anchor.
It charges1862+ceil(366*l/1024) on the requested length, then checks handle capacity
before reading the hash. Missing/out-of-domain accounts or unavailable history return
NONE. Clip offset and requested extent against the actual historical blob before
bounded copying and deblob; an empty/clipped malformed program returns HUH. The
service sentinel selects the package item. Source bytes never become guest RAM.

Scope/completion: wire database mode independently of native compilation, preserving
memory mode and all catalogue/instance ownership. Check both source modes, clipped
slices, exact/short gas, absent and unavailable history, invalid full-width service
selectors and pointers, local copy/retained budgets, dispatch/lifecycle consumers and
ARC release. The lower-level module API accepts already authenticated historical
bytes only from a trusted adapter; direct mode1 without that adapter stays an
explicit UnsupportedSource refusal.

`machine`=10 accepts module handle and entry in registers7–8 and charges1862.
Check the63-instance capacity, catalogue membership (WHO), then entry/deblob
validity (HUH). Success creates the smallest absent instance ID with empty
inaccessible RAM, the requested PC, an uncharged flag and its source module handle.
Instances share immutable program storage without counting the same module bytes twice.

`expunge`=15 accepts mode and ID in registers7–8 and charges335. Mode0 removes
an instance and returns its PC. Mode1 removes a catalogue entry and returns OK.
Missing membership returns WHO; other modes return HUH. Removing a catalogue entry
leaves live instances usable, retains the occupied module handle and byte accounting,
and prevents new instantiation from that removed entry. Only the final catalogue or
instance owner releases the module's retained byte budget and handle for reuse.

All host underfunding returns unsigned zero-gas OutOfGas before protocol mutations.
Local item/program/total-byte/jump/page limits remain typed failures without a partial
response or successor. Input/output copies cannot mutate earlier snapshots. No raw
mutable catalogue, program or instance storage is exported.

Current tests cover both capacities, smallest-hole reuse, full-width unknown IDs,
source/entry validation, shared modules, independent local budgets, catalogue removal
with live instances, eventual byte recovery, immutable copied views and guarded errors.
Fresh-memory1,000-cycle compile/create/dual-expunge checks detect retained response
owners; page and invoke suites independently verify their repeated ownership release.
Direct owned response construction avoids the observed nested charge-result retention
with the pinned compiler, without changing gas semantics or compiler dependencies.

Peek/poke/pages/invoke now use IDs11/12/13/14. Complete refinement, historical
compilation and full state serialization remain separate implementation work. M1
framing completion does not imply complete JAM execution or current crypto parity.

## Historical compilation verification

Local macOS checks passed the refinement dispatch, inner lifecycle/pages/transfer/invoke,
refinement outcome and authorized refinement suites, each retaining stable1000-cycle
ARC evidence. The dispatch suite separately exercises1000 complete historical
compile/create/expunge lifecycles. All264 production modules passed semantic compilation.
These are local results; exact-head Linux CI and full upstream PolkaVM fuzzing remain
separate work. No native-code compilation or compiled benchmark path is added.

Direct witnesses prove requested-length pricing against a six-byte retained budget,
FULL before source availability, invalid trusted-adapter arguments and default owners.
Real guests cover both package item identities, explicit other-service reads, exact
availability time, absence, full-width selectors/pointers, clipped valid and malformed
programs, copy/total budgets and gas underfunding. Module creation preserves original
guest execution, and expunge uses the same immutable lifecycle as memory modules.
