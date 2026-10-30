# QUIC transport

[Source guide](../README.md) · [Networking design](../../docs/design/quic.md)

This folder owns the nonblocking transport beneath JAMNP-S. [`io.nim`](io.nim) provides
POSIX UDP readiness and bounded polling. [`transport.nim`](transport.nim) owns the narrow
LSQUIC/TLS bridge, callback lifetimes, UDP endpoints and primitive certificate observations.
The maintained native bridge lives in [`native/quic/`](../../native/quic/README.md).

JAM peer identities, ALPN use, message framing, stream semantics, sessions and download
coordination live in [`src/jamnp-s/`](../jamnp-s/README.md). Native callbacks borrow stable
owners synchronously; endpoints retire callbacks before closing foreign resources.
