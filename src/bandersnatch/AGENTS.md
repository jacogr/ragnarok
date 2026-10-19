# Bandersnatch implementation instructions

- Use pinned ark-vrf 0.2.2, the draft-29 release-designated IETF Bandersnatch reference. Preserve
  its nonce separation and 96/784-byte contracts. Record the draft-text 16-byte versus reference
  32-byte challenge discrepancy; never substitute newer suite profiles or invent proof padding.
  Keep Rust behind the maintained primitive ABI, locked builds, source/SRS hash checks and native
  ring/domain policy. Never enable unsafe deterministic/non-ZK test-vector features in the adapter
  build. Passing vectors does not establish an audit.

See [the migration record](../../spec/graypaper-0.8.0.md) and pinned primitive ABI.
