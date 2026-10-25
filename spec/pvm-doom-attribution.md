# Bounded pinned DOOM attribution

Use the existing PolkaVM pin, its `test-data/doom_64.elf.zst` and shareware WAD.
Link with the pinned public linker, JamV1 and an explicit16KiB minimum stack;
keep4KiB pages, interpreter-only reference, Sync/Full/L2Hit metering and all native
checks. No guest source rebuild, dependency upgrade or interpreter optimization
belongs in this investigation. The retained decode-once runtime is the parent;
the rejected frame annotation is excluded.

Prepare independent initialization and one-tick inputs. An explicit bounded number
of untimed reference warmup ticks may select the steady-state input. Both runners
must receive identical complete code, registers, gas, permissions and mapped bytes.
Compare normal exit, all final registers, gas and every mapped memory byte. Capture
ordered video/audio/console events outside guest collection and compare their
SHA256 hashes; video dimensions and per-frame hashes remain explicit. Initialization
emits a frame, so tick counts must never be substituted for emitted-frame counts.

First qualify local correctness, including assertion, changed expected-state and
changed output controls. Then profile both engines on CI with calibrated Callgrind
scope, retained raw files/source hashes and annotated hotspots. Instrumented clocks
are discarded. Keep initialization and one-tick attribution separate. Profile
collection must exclude preparation, file I/O, output hashing and final-state
validation consistently. Both selected outer guest-call boundaries include their
in-memory host callbacks (ROM copying and output capture); attribute that embedding
work separately rather than calling it interpreter opcode work. Report one selected
call per phase and all harness work inside that boundary. Counts are not timing claims.


CI also measures native/reference CPU slowdown after correctness and instruction
collection. Each endpoint runs13 fresh-state calls (three warmups, ten measured)
in both process orders on that same runner. Compare the warmed CPU medians and
retain every raw sample and complete per-sample validation. Clock reads are
disabled in local correctness and instrumented processes. Ratios cover the guest
call plus the same in-memory host work; program/memory/price preparation, restoring
snapshots, file I/O, hashing and final validation stay outside both clocks.

Commands: `make check-pvm-doom` performs local untimed parity/refusal checks;
`make profile-pvm-doom` is the opt-in CI entry, with1320 warmup ticks selecting the
upstream frame1320 gameplay golden. A Linux developer can request counters without timings
with `python3 tools/pvm_doom_attribution.py --counts-only`. No runtime optimization
is accepted by this harness increment; attribution must identify the next target.


## Local admission

Checked local runs pass at0 and120 warmup ticks. Both initializers and both
one-tick executions agree on all registers, gas,4285 mapped pages and ordered
output bytes. All six assertion/state/output refusal controls and restored
positive controls pass. The120-warmup output also matches the pinned upstream
frame120 golden after its documented BGR/opaque-alpha normalization. Raw video
hashes remain separate, so this normalization cannot hide a native/reference
byte mismatch. Local runs record no guest timing samples. Focused parser/profile/
workflow checks and verification inventory pass; Linux profiles and CPU ratios
remain pending.


The inspected frame120 golden is the title screen. Frame1320 shows active demo
combat; the final CI default therefore warms1320 ticks and measures the next
single tick, corresponding to that zero-indexed upstream golden. Warmup remains
bounded at1320 ticks and takes place only during shared reference preparation.
The earlier120-tick check is admission evidence, not a gameplay performance result.


The1320-tick admission now passes the gameplay golden (raw video SHA256
`58dee7573bf534ade151ded609039f5b14c5f712cae567c814701a9a5b539168`) and complete
native/reference parity. After moving event serialization outside both selected
calls, both final runners also pass against that saved gameplay input; all six
refusal controls pass on the final untimed harness. No local timing runs exist.
The event byte format is unchanged: callback payload ownership is retained once,
and serialization/hash comparison follows after collection/timing. Warmup output
is read/validated and discarded, because DOOM's transition can emit many frames
within one tick. Measured output remains fully retained and bounded.


The first Linux run40186627565 passes full-state/output controls and collects
all four instruction profiles, but fails before timings because source archival
omitted the helper's required repository argument. Its status remains failed;
no CPU ratio is claimed. Correct the call and move archival before collection,
verify the real local archive (24 generated C files), then rerun the complete
same workload to retain qualified source evidence and paired timings. No runtime,
guest, driver or compiler option changes in that repair.
