# JAMNP-S over QUIC

[Design overview](../design.md) · [JAMNP-S source map](../../src/jamnp-s/README.md) ·
[QUIC source map](../../src/quic/README.md)

[JAMNP-S](../../src/jamnp-s/README.md) owns peer identity, framing and stream policy.
[QUIC](../../src/quic/transport.nim) owns primitive certificate observations and
the native transport bridge. The dispatcher drives transport and timers, while
[Services](../../src/app/services.nim) owns independent worker and listener lifetimes.

## Peer announcements

[UP0 routes](../../src/jamnp-s/announcement_stream.nim) keep bounded peer claims
with their stream incarnation. [Sync targets](../../src/jamnp-s/sync_targets.nim)
compare live claims against independently admitted canonical evidence.

## Canonical development block serving

[Devnet transport](../../src/jamnp-s/devnet.nim) serves detached bytes from the
host-selected catalog. [Download rearming](../../src/jamnp-s/block/download/loop.nim)
follows stream and lease retirement. [Node sync](../../spec/node-sync.md) records
the trust and participation scope.
