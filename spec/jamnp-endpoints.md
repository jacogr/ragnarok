# JAMNP-S complete network endpoints

Authority: JAMNP-S `simple.md` at `aa0e2b8498c0b1bc1725af2903704d701c6577ab`,
“Required connectivity”. Validator metadata begins with sixteen IPv6 bytes followed by a
two-byte little-endian port. Projection copies those fields, ignores trailing metadata, and
refuses truncated/unavailable destinations without publishing a partial endpoint.

`quic/address.nim` provides private fixed copied address/port values. Numeric parsing uses
inet_pton with no DNS or retained native pointers; formatting uses caller-owned fixed storage.
IPv4 is normalized as sixteen mapped bytes while retaining its distinct socket family.
Unspecified addresses are allowed for local wildcard binding but cannot be dialed as peers.
Remote port zero and family mismatch are refused before native connection setup.

The full-address UDP API binds an explicit IP and returns the complete source IP/port tuple.
The native QUIC bridge receives that tuple unchanged and returns each outgoing datagram's
complete destination. Startup copies the actual bound IP before any network processing.
Neither a source nor destination is fabricated from a port. Datagram buffers remain bounded
and borrowed only during synchronous calls. Existing port-only proof entry points explicitly
retain loopback binding, targets and exact source filtering; they do not silently become
public listeners. Readiness, socket flags, retirement and bounded polling remain unchanged.

`make unit SUITE=jamnp_endpoints` checks numeric address roundtrips, family preservation,
failed-parser clearing, all truncated metadata prefixes, metadata port byte order, real IPv4
and IPv6 wildcard UDP receives with exact source tuples, stale-source clearing on would-block,
and mutual TLS through full-address wildcard listeners. On Linux the IPv4 client binds
127.0.0.2, so replying to a reconstructed127.0.0.1 would fail the same test. These local tests
require no DNS or external host and do not claim an external-network interoperability run.
The existing `quic_io`, `jamnp_alpn` and `jamnp_persistent` suites remain consumer checks.

This layer supplies addressed transport and metadata projection. Ordinary command address
configuration, validator-set dialing and dynamic epoch/connectivity scheduling are separate
runtime integrations; adding a tuple API alone does not complete those compliance rows.

Linux-specific regression coverage also binds127.0.0.2 and127.0.0.3 to the same UDP source
port and requires both distinct source tuples to arrive unchanged. A copied endpoint is a
routing observation only; projecting validator metadata does not establish membership,
authenticate the advertised endpoint, or authorize a protocol request.

The native Transport aggregate explicitly rejects copies and live relocation: its engine
retains the original owner address as callback context. Scope destruction requires the engine
to have completed explicit close before child UDP/selector retirement. The focused
`quic_transport_copy` lowering guard protects this borrowed-callback/teardown boundary.
