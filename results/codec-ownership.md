# Codec ownership round

## Outcome

The owned snapshot layer covers byte strings, optional blobs, work outputs,
complete preimage extrinsics and complete work digests in both languages.
Private copied storage retains only a validated consumed prefix. Metadata has
no detached source spans; payload extraction and canonical re-emission select
the source exclusively through an opaque owner. A same-sized wrong source
buffer cannot be passed to either operation. Original input mutation and
lifetime no longer determine owned payload bytes.

The allocation-free span/pool APIs remain available under explicit borrowed
names. Their identity/mutation/lifetime contract remains caller-managed.
Nim snapshots use acyclic ARC ownership; Odin snapshots use explicit allocators
and release. Odin copied-handle aliases remain subject to its documented
single-release lifetime contract. Neither language prevents deliberate unsafe
access. See [the API and migration guide](../docs/codec-ownership.md).

Gray Paper v0.7.1, compiler and official-vector revisions are unchanged. Wire
formats, canonical checks, resource policies and atomic destination failures
are preserved. This round adds allocation/copying for owned decoding; it does
not change the allocation-free borrowed implementation or QUIC code.

## Verification

Executed locally on macOS with the pinned Nim 2.2.12 ARC and Odin toolchains:

```sh
python3 tools/format.py
python3 tools/format.py --check
PYTHONDONTWRITEBYTECODE=1 python3 interoperability/test_codec.py
git diff --check
```

The shared suite passed 185,373 requests per implementation:

| Family | Requests per implementation | Official checks |
| --- | ---: | --- |
| Naturals | 45,215 | 20 prefixes |
| Fixed-width integers | 73,278 | 24 fields |
| Bounded containers | 26,712 | 12 blobs |
| Composites | 25,890 | 4 complete preimages and 8 work outputs |
| Work digests | 14,278 | 8 complete digests |

Every successful byte-string, optional, work-output, preimage and digest
adapter decode also checks the owned path. Checks compare the entire canonical
prefix, every payload and all relevant copied metadata with the borrowed result
that is independently checked by the shared reference/official vectors.

New regressions cover:

- Snapshot survival after original stack storage goes out of scope.
- Original-buffer mutations after validation, including nested preimages and
  digest payloads; mutations of extracted copies.
- Empty payloads versus absent optionals and decoded work-error values.
- Wrong schema, missing owner and invalid payload indices.
- Whole-destination preservation on insufficient payload/frame output capacity.
- 10,000 deterministic random inputs across all five schemas in each language,
  with exact successful bytes and malformed/truncated failure parity.
- Odin repeated decode/release and late malformed-record cleanup, with zero
  tracked live allocations after each iteration.
- Odin refusal at each record/wire/header allocation stage, plus nil allocation
  without an error; earlier allocations are released on each failure.
- Four new compilation rejection checks: private-storage access and attempts
  to supply an unrelated source pool, in both languages.

All 32 compilation rejection checks and all nine Odin native tests passed.
Nim ownership and result-safety checks passed in debug and ordinary release
builds. Formatting checked 73 source files. These are local results; Linux CI
will execute the same shared suite after publication.

## Remaining limits

Borrowed APIs are explicit opt-ins, not safe retained views. Odin owner lifetime
and alias release are documented contracts rather than compiler-enforced
unique ownership. Caller input must stay stable during a decode, and the
selected allocator must outlive its owned frames. Nim allocation exhaustion
remains an allocation defect. Performance and aggregate live-frame budgets
have not been benchmarked in this correctness round.
