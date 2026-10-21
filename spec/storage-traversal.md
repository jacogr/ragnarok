# Physical repository traversal and retained-reader ownership

This storage-only batch starts from merged storage stack #601 at `a000136d`. It preserves the
pinned Gray Paper 0.8.0 commitment rules, public state/store APIs, strict recovery, independent
checkpoint-import trust and all managed file formats. State #6 owns ancestor/download interfaces.

## Measurement contract

`make unit SUITE=storage_traversal_cost` isolates physical repository ownership from temporary
full-state tries and raw transport objects. Three repetitions cover 1,024/8,192 entries, 16/256-byte
values and key offsets zero/29. The latter has a 232-bit common prefix. Sixteen sparse updates
retain the initial root and last eight successor views. Every key/value is checked against authored
mappings before/after owner close; complete scope release must return occupied memory to baseline.

Evidence records occupied bytes with nine readers, after close and with only the final immutable view,
real publication/extraction hash attempts and descriptive phase timing. The publication timing
includes scenario preparation; hash counts are reset immediately before the sixteen updates.
Occupied bytes are current-thread native heap accounting, not RSS or an allocation-event count.
No generic throughput, disk cache or physical power-loss claim follows from these observations.

Generated checked native C shows two candidates: graph traversal duplicates the borrowed
`TrieRecord` including payload, and changed publication duplicates old payloads into every table.
The first experiment will remove only the graph's temporary record copy; a separate dependent
experiment may introduce private immutable record owners while keeping detached public transports.
Both require identical maps, roots, hash counts and rejection behavior, retained-reader lifetime,
independent clones and measured before/after evidence. No caller-controlled trust bypass is planned.

## Merged baseline

All 24 samples pass complete-map and exact scope-release checks. With 8,192 entries and 256-byte
values, nine shallow readers occupy 40,725,264 bytes versus 4,526,272 for only the final reader;
deep readers occupy 44,329,744 versus 5,116,096 bytes. Owner close leaves those readers usable
and does not release their occupied storage. Extraction makes zero hash attempts. The baseline
uses pinned checked Nimony native ARC on macOS ARM64; timing is descriptive only.
