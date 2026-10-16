# M1 coverage audit — Gray Paper 0.8.0

This audit follows Appendix C.1/C.2 at the exact source/vector revisions in `spec/pins.json`.
M1 remains **in progress**. Complete published fixture-family coverage does not mean every general
encoding or specialized C.2 tuple has a reusable public API. State encoding/Merkle layout needs
its own scope; PVM execution and state transitions are separate client work.

## General encodings (C.1)

| Term | Status and evidence |
| --- | --- |
| Empty value, octet, tuple concatenation | Used by typed codecs; no general tuple combinator API. |
| General natural, fixed-width unsigned | Implemented in `natural.nim` / `fixed_unsigned.nim`; independent boundaries and nominal tests. |
| Byte strings, fixed-width sequences | Implemented in `bounded.nim`; explicit resource budgets and atomic borrowed operations. |
| Optional/tagged alternatives | Implemented for optional blobs, work results and header markers; not a generic schema framework. |
| Boolean | Strict 0/1 paths in disputes; a standalone general Boolean API is still absent. |
| Bitstrings | Fixed profile assurance bitfields, including unused-bit checks, are implemented; general variable bitstrings remain. |
| Canonical sets | Ordered unique prerequisites and evidence are specialized implementations; a reusable general set API remains. |
| Canonical dictionaries | Specialized ordered report lookup paths exist; a reusable general dictionary API remains. |

## Specialized records (C.2)

| Term | Current implementation |
| --- | --- |
| Work outputs, digests and complete reports | `composite.nim`, `work_digest.nim`, `work_report.nim`, retained `report_owned.nim`. |
| Availability specification | Complete wire fields embedded in the report header; standalone public record codec remains. |
| Refinement context, imports, input commitments, work items/packages | `work_package.nim`, standalone components and package aggregate policy. |
| Tickets, preimages, guarantees, assurances, disputes | Dedicated family modules, exact framing and structural policies. |
| Safrole winning ticket, epoch/winner markers, full/signing headers | `header.nim`, distinct sealed/unsigned owners and retained marker access. |
| Complete extrinsic and block | `block_codec.nim`, typed components, complete preflight and retained children. |
| Deferred transfers (`defxfer`) | Not implemented. |
| Accumulation operands (`operandtuple`) | Not implemented. |

The next coherent groups are general encodings and remaining C.2 records. A reusable schema
framework is not required to close these concrete API gaps. State-dependent eligibility, hashing,
signature/point validation, execution and authorization are not properties of the framing layer.

## Published codec fixture inventory

Both `codec/tiny` and `codec/full` contain the following 15 JSON/binary pairs. These are all current
published codec basenames at the pin, not a claim that the corpus exhausts Appendix C.

| Published basename(s) | Verification and outcome |
| --- | --- |
| `work_result_0`, `work_result_1`, `preimages_extrinsic` | `tests/test_codec.py`; original bytes plus independent field/boundary tests. |
| `work_report` | `tests/test_work_report.py`; exact JSON/wire observation and documented tiny core policy. |
| `assurances_extrinsic` | `tests/test_assurances.py`; original profile bitfield framing/order. |
| `tickets_extrinsic`, `guarantees_extrinsic` | `tests/test_tickets.py`, `tests/test_guarantees.py`; original bytes and explicit tiny guarantee core-bound rejection, plus derived valid source. |
| `disputes_extrinsic` | `tests/test_disputes.py`; both raw samples reject descending verdict order; sorted authored counterparts pass. |
| `refine_context`, `work_item`, `work_package` | `tests/test_work_package.py`; exact named-field reconstruction and existing package policies. |
| `header_0`, `header_1` | `tests/test_header.py`; all four exact headers and signing prefixes pass. |
| `extrinsic`, `block` | `tests/test_block.py`; all originals reconstruct exactly, tiny rejects guarantee core 3, full rejects descending disputes; authored counterparts pass structural tests. |

Composite counterparts retain opaque header hashes/proofs/signatures unchanged, so are not
chain-valid examples. See [composition](../spec/block.md), [guarantees](../spec/guarantees.md) and
[disputes](../spec/disputes.md) for the exact rejection/derivation contracts. Vendor files remain
untouched. Specialized tests add independent boundaries, malformed inputs, ownership, atomicity
and negative compilation coverage beyond these finite published examples.

The source-of-truth migration and unresolved crypto gates remain recorded in the
[migration audit](../spec/graypaper-0.8.0.md). This audit does not close those gates or certify a
complete consensus implementation.
