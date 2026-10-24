# Whole-map STF goldens for gas-limited guest exits

Authority remains GP `1fa8cbc7e7ec3e60d09f8e704911a89c6837ce1d`, specifically prepaid basic-block
charging in `pvm.tex`, write/yield/checkpoint host prices and OOG handling, accumulation X/Y
selection, per-service operand gas pooling, statistics and accumulation-statistics-key timestamp updates.
The existing Thin/ark-vrf/vector pins and AmbiguousPrivileges guard remain unchanged.

Twenty-five genuine seven-block chains combine five literal storage modes with per-operand gas
limits1,105,1325,1377,2753. They release one service99 report at5 and two reports together at7.
The latter form one invocation with the sum of both limits. Service42 independently halts at6.
All originals, report fields, code, namespace reservations and signatures are authored inputs.
No observed native gas or successor map supplies an expected result.

The independent model first obtains the whole-block price from the pinned-table simulator.
If the supplied gas cannot pay it, no instruction executes and actual consumption is zero.
Once prepaid, an underfunded write, yield or checkpoint consumes the remaining host gas, selects
uncheckpointed Y and retains no storage/yield implication. A completed checkpoint followed by
panic retains its actual X. Literal ordinary panic rolls its implications back even with ample gas.

Important boundaries include105-gas block/write exhaustion,1325 versus pooled2650 for a retained
ordinary write/yield,1377 versus pooled2754 for an exact checkpoint, and2753 falling one gas short
of that checkpoint. Fully funded guests consume their calculated price rather than the whole
allowance. A report is processed even when its guest exits OOG; every retained accumulation-statistics key stamps
last-accumulation metadata, including a zero-gas invocation with nonzero operand count. These
invocations also contribute their processed package identities to C15.

The registered `current_stf_gas_exits_corpus` compares175 complete P/B/O transitions and100
processed reports. Whole maps include storage footprint replacement/deletion, rollback, timestamps,
preimage/code preservation, C13 gas/counts, C15 history, C16 implications and C3 output-sensitive
commitments. The existing35 report-guest transitions are exact-output regressions for the shared
helper's default behavior. Scoped Python, provenance, formatting and inventory checks accompany
the native run; evidence is under `build/state9-stf-gas-exits/`.

Production and existing fixtures are unchanged. These authored current-profile cases do not
establish full JAM parity. Late code availability, transfers and epoch/expiry interactions remain
separate whole-map work; local evidence does not stand in for exact-head Linux CI.
