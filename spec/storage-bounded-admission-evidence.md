# Bounded admission: allocation evidence

The clean baseline is `08bd7723cb8000ee34d9ad8cd4c5050f23a97f47`, after the prior read-memory
batch merged. [Linux run 39829465062](https://github.com/jacogr/ragnarok/actions/runs/39829465062/job/120001454254)
passed the existing scoped allocation diagnosis. Artifact `storage-abort-diagnostics-1` retains
ordinary/symbolized binaries, all backtraces, controls and file fingerprints. Independent local
validation matched all 447 baseline source hashes and both downloaded binary identities, reparsed
the ordinary ceiling panel and all additional control/limit receipts, and checked symbolized
build flags separately. Only C debug information differs from the checked ordinary profile.

The ordinary panel completed 18 of 20 observations, with two expected SIGABRT exits under the
128 MiB address-space ceiling. Four extra unrestricted controls and four debugger traces passed;
all selected bytes remained unchanged. This is address-space allocation refusal, distinct from
local cgroup OOM kills or resident-pressure timeouts. The debugger remained outside the cap and
the native children read back the exact 134,217,728-byte soft bound.

Both ordinary allocating chains are `decodeRecords` → `rawAlloc` → `getBigChunk` →
`requestOsChunks` → `raiseOutOfMem` → Linux `kill`. Journal reaches decoding through
`replayJournalFrame`; managed reaches it through `decodeRepositoryImage` and snapshot admission.
The ordinary return PC is `decodeRecords_0_recqhpeyx +3177` in both traces. Offline LLDB
inspection of that exact ordinary ELF shows a call to `number` at +3142, the value moved into
the allocation-size argument at +3169, and `rawAlloc` called at +3172. The following source pointer
advances by the 72-byte physical leaf prefix. The symbolized trace identifies a 256-byte leaf
payload `newSeq` at this same decoder stage; it does not substitute for the ordinary call site.
Thus the reproduced refusal occurs while materializing payloads in the complete detached record
batch, before private graph admission. The trace does not recover an ordinary optimized-out exact
allocation size or establish that every remaining peak comes from this call site.

Local raw artifacts: `build/storage-db9-diagnostics-39829465062/`.
Independent validation: `independent-validation.json` under that directory.
Ordinary disassembly: `build/storage-db9-ordinary-decode-disassembly.log`.
Ordinary binary SHA-256: `00fdc53aaacd4cf0e4026e6f3adddf82f44f1f78156f8baff8c21cbed8dbf8ba`.
Symbolized binary SHA-256: `03051c62f8c7b19a181150cd9c8130960d9b197ae58fbc1f292749dc142a1c14`.

## Delivery lifetime witness

`make unit SUITE=storage_delivery_footprint` passes both ordered-collection and target-bearing
batch delivery with 32/512-entry fixtures and 32/257-byte values in reversed count/API orders.
Setup drops complete maps and raw transports before observing delivery; stable encoded source
owners remain alive. The nonretaining consumer counts every record/value byte and measures live
Nim allocation relative to the same process immediately before that call. Every callback remains
within one payload plus 4096 bytes, and every delivery returns occupied memory to its baseline.
The largest complete transport descriptor batch could not fit that allowance.

This witness detects hidden full decoded-batch retention during callbacks. It is not a whole-call
allocation high-water mark: duplicate-address scratch is explicitly permitted before callbacks,
and temporary crypto allocations can retire before delivery. Whole-child RSS, retained repository
allocation and Linux resident-pressure behavior require the separate final qualification. Raw
mutable admission still copies and validates; only privately decoded local record owners may
transfer their payload into immutable staged cells.
