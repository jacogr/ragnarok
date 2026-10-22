# Expected-root typed checkpoint decoding

Use the current state serialization contracts and unchanged local full-map V1
checkpoint envelope. This bounded synchronous adapter changes no storage format,
repository API, canonical head, Services, proof worker, RPC schema or root policy.
The caller supplies an independently selected expected `StateRoot`, explicit
complete service manifest, shared profile and all restoration/validation policies.
There is deliberately no embedded-root-only overload or automatic installation.

First delegate to `decodeFullCheckpoint` with that expected root. Only then validate
all sixteen globals and exact complete service-manifest coverage through the
existing adapters. Preserve checkpoint format/canonicality/resource/backend/root
reasons; global missing-chapter/configuration/value/resource reasons; and manifest
mapping/opaque/codec/backend reasons through distinct private phase alternatives.
A failed/default result grants no restored store or validated prefix. Do not retry
under another profile, encoding, root source or less restrictive policy.

Success retains the exact newly restored complete-map owner through its immutable
manifest certificate. Temporary decoder stores and composed buffers retire, and
caller input/descriptor mutation or release cannot change retained bytes. Existing
checkpoint integrity/root work and manifest composition remain synchronous and
bounded; they cannot run against a graph under the managed proof worker's ARC lease.
The adapter performs no file I/O, canonical adoption, persistence transaction,
valid-state consistency checks or STF execution. Serialization success is not
full current-pin/JAM/Thin-VRF parity or independent trust in the supplied root.

Completion witnesses: independently assembled complete chapter/service source,
unchanged checkpoint re-encoding, explicit wrong root, format/truncation and
independent policy refusals; internally valid checkpoints containing missing or
malformed globals, undeclared service rows and invalid manifest inputs; early and
post-restoration backend refusal; retained bytes after input release; exact nested
reason guards and private/root-domain compiler rejection; fresh1,000-cycle ARC.
Reuse lower checkpoint codec and composition algorithm evidence without duplication.

## Local verification

The focused native suite passes exact checkpoint re-encoding and restored bytes,
independent expected-root refusal, format/truncation and source/global/manifest
policy alternatives, absent/malformed global routing, undeclared/opaque service
rows and reserved request identities. Fault injection distinguishes restoration
backend failure from the first manifest hash after completed restoration.
A uniquely allocated input buffer is overwritten and freed before retained
restored state is re-encoded. The finalized1,000-cycle success/late-refusal ARC
workload retains270,432 live bytes before and after warmup.

Five strict runtime payload/phase guards, a genuine expected-root success control
and six private-field/root-domain compiler rejections pass. All new modules and
drivers pass pinned semantic checks; unchanged earlier module checks are reused.
Fresh final qualification passes all10 existing lifecycle-model cases, the
production build and668 Python tests with3 individually documented skips.
Inventory, pinned formatting, local documentation links and whitespace checks pass.
Evidence remains under ignored `build/validated-checkpoint-*` and
`build/tests/validated-checkpoint-guards/`. These checked macOS results are distinct
from exact-head Linux CI and full current-pin/JAM/Thin-VRF parity.

This completes the bounded complete-source validation feature. Application/runtime
adoption requires its owners' root/manifest/profile selection and existing ARC
exclusion rules; this feature introduces no automatic selection or installation.
Current-pin complete-state corpus/STF evidence and validity relationships remain
separate gates, rather than inferred consequences of successful serialization.
