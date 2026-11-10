# Codecs and ownership

[Design overview](../design.md) · [Codec source map](../../src/codec/README.md)

Codecs own canonical wire layout and typed, bounded capture. Consumers supply the
schema, policy and chain context. Borrowed codecs serve a synchronous activation.
[Owned snapshots](../../src/codec/owned.nim) bind later extraction to the exact
immutable bytes. [Pinned authority](../../spec/codec.md) records the baseline.
