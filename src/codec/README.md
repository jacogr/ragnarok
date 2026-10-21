# Protocol codecs and owned values

[Source guide](../README.md) · [Codec guide](../../docs/codec.md)

This folder implements canonical JAM byte encodings, nominal protocol values and immutable owned
snapshots. Decoders validate lengths, bounds and representation before exposing values; borrowed
input does not become mutable published storage.

| Area | Modules |
| --- | --- |
| Integer, sequence and ownership foundations | `natural`, `fixed_unsigned`, `bounded`, `bitstrings`, `collections`, `composite`, `owned` |
| Blocks and extrinsics | `header`, `block_codec`, `tickets`, `assurances`, `guarantees`, `disputes` |
| Work packages and reports | `work_package`, `work_digest`, `work_report`, `report_owned`, `c2_records` |
| State chapters and service records | `state_accounts`, `state_service_values`, `state_requests` and the other `state_*` chapter codecs |
| State keys and commitments | [`state_layout.nim`](state_layout.nim), [`state_trie.nim`](state_trie.nim) |

The complete-map root calculator in `state_trie.nim` is an independent reference for the
incremental [storage trie](../storage/README.md). Serialization and commitment primitives are
shared across consumers; complete full-state roots and partial light-state proofs retain distinct
contracts.

The [codec design](../../docs/design/codec.md) explains ownership and module boundaries;
[the codec contract](../../spec/codec.md) and [GP migration record](../../spec/graypaper-0.8.0.md)
record exact representations and open interpretation gates. Published vector widths have one
accepted representation, with malformed-input, ownership and compiler-rejection verification.
