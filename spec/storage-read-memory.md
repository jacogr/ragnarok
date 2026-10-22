# Storage read-memory reduction

The next storage tranche starts at merged `56e8686f2b96012acd20179f6a6ea775540828e2`.
Controlled Linux pressure and ordinary allocation traces selected transient read buffers and
owned byte-sequence extraction before retained graph layout. Preserve selected bytes, typed
limits/error ordering, full roots/maps/generations, immutable retained views and explicit leases.
Compiler, crypto, allocator, checked ARC/Clang release/LTO and physical formats remain fixed.

The clean-master native fresh-reopen panel passed locally on macOS ARM64. At131,072 entries,
journal peaked at349,159,424 native RSS bytes and managed at420,429,824. Retained open Nim
bytes were77,811,120 and77,811,152 respectively. The frozen baseline report/binary are
under ignored `build/storage-db8-baseline/`; these are not new Linux qualification results.
Measurements will compare the same native workload and profile before any improvement claim.

`storage_read_buffers` exercises actual managed files at0/1/4095/4096/4097/16384 bytes,
three short-read sizes, exact-limit EOF, over-limit refusal before payload reads and independent
copy access. Existing short/EINTR, post-stat growth, lifetime and malformed snapshot/journal
checks remain required for reader changes. Metadata may guide bounded capacity; actual reads
and final EOF must remain authoritative. No allocation-failure recovery or out-of-core claim.
