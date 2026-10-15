from std.collections import Array, Span, Optional
from std.ffi import external_call, c_int, c_size_t
from std.os import getenv
from std.os.path import exists
from quic.transport import *
from quic.core import Peer, Progress, StreamState, empty_stream, verify_peer, send_packet, on_stream
from quic.integration import IntegrationBank, PreimageKey
import quic.offload as offload
from tests.support import capacity


# Apply pinned JAMNP-S required-connectivity ordering to full public-key byte strings.
def preferred(local: Span[mut=False, UInt8, _], remote: Span[mut=False, UInt8, _]) -> Bool:
    var less = False
    # The first unequal byte determines lexical order; final-byte high bits contribute independently.
    for i in range(32):
        if local[i] != remote[i]:
            less = local[i] < remote[i]
            break
    return (local[31] > 127) ^ (remote[31] > 127) ^ less


# Verify ordering and high-bit parity without any socket, transport engine or private key.
def policy_selftest() raises:
    # Exercise both final-byte high bits in both first-byte orderings.
    for a_high in range(0, 129, 128):
        for b_high in range(0, 129, 128):
            for first in range(0, 3, 2):
                var a = Array[UInt8, 32](fill=0)
                var b = Array[UInt8, 32](fill=0)
                a[0] = UInt8(first)
                b[0] = 1
                a[31] = UInt8(a_high)
                b[31] = UInt8(b_high)
                var actual = preferred(Span(a), Span(b))
                # Direction must match the independent expression and invert when the peers are exchanged.
                if actual != ((a_high != b_high) ^ (first < 1)) or actual == preferred(
                    Span(b), Span(a)
                ):
                    raise Error("mesh ordering policy")
    print("MESH_POLICY_OK")


# Construct a fully owned role before its stable address is registered as a native callback user pointer.
def new_peer(server: Bool, var expected: List[UInt8]) -> Peer:
    return Peer(
        Transport(None, -1, False, False, Array[UInt8, 2048](fill=0), True),
        expected^,
        Progress(
            server,
            False,
            False,
            0,
            0,
            String("valid"),
            0,
            0,
            0,
            False,
            False,
            8,
            True,
            False,
            False,
            0,
            0,
            False,
            False,
            False,
            False,
        ),
        List[StreamState](length=64, fill=empty_stream()),
        IntegrationBank(List[List[UInt8]](), List[PreimageKey]()),
        offload.empty_pool(),
    )


# Open one retained IPv6 role engine; never move its Peer owner after native callbacks borrow its address.
def open_role(
    mut peer: Peer, port: UInt16, profile: Int, var cert: String, var key: String, var alpn: String
) -> Bool:
    var bound: UInt16 = 0
    peer.transport.fd = external_call["rqm_udp_open6", c_int](port, Pointer(to=bound))
    # Failed socket creation owns no native engine and cannot announce a ready role.
    if peer.transport.fd < 0:
        return False
    var c = cert.as_c_string_span()
    var k = key.as_c_string_span()
    var a = alpn.as_c_string_span()
    # Strings are borrowed only during construction; the stable Peer owns every subsequent callback context.
    peer.transport.engine = external_call["rq_transport_new_ipv6_profile", Optional[NativePointer]](
        c_int(profile),
        c_int(peer.progress.server),
        bound,
        c.ptr().as_unsafe_any_origin(),
        k.ptr().as_unsafe_any_origin(),
        a.ptr().as_unsafe_any_origin(),
        Pointer(to=peer).unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        verify_peer,
        send_packet,
        on_stream,
    )
    return Bool(peer.transport.engine)


# Drive both role engines on their one dispatcher while propagating every framing and OS failure.
def poll_roles(mut incoming: Peer, mut outgoing: Peer) -> Bool:
    return (
        poll_pair(incoming.transport, outgoing.transport)
        and not incoming.progress.failed
        and not outgoing.progress.failed
    )


# Live slots retain application buffers until final native close, independently of settled reply counts.
def live(peer: Peer) -> Int:
    var count = 0
    # Count only currently owned native handles; retired slots contain no outstanding application storage.
    for i in range(len(peer.streams)):
        if peer.streams[i].handle:
            count += 1
    return count


# Prove pending work means four fully transmitted no-FIN queries and four fully received request prefixes.
def pending(peer: Peer) -> Bool:
    var local = 0
    var remote = 0
    # Every retained pending slot must remain unsettled and wait for the vanished peer or its FIN.
    for i in range(len(peer.streams)):
        if not peer.streams[i].handle:
            # Retired slots no longer own application state.
            continue
        if peer.streams[i].counted or peer.streams[i].read_fin:
            # A completed response cannot stand in for an interrupted pending request.
            return False
        if peer.streams[i].responder:
            # Remote request prefixes must actually arrive, rather than merely having allocated buffers.
            if peer.streams[i].received_length != 37:
                return False
            remote += 1
        else:
            # Local no-FIN requests must be fully sent before peer-loss injection.
            if peer.streams[i].send_offset != 37 or peer.streams[i].write_fin:
                return False
            local += 1
    return local == 4 and remote == 4


# Hold an explicit controller barrier while both retained engines continue serving native timers/readiness.
def wait_gate(mut incoming: Peer, mut outgoing: Peer, path: String) -> Bool:
    var started = now_ms()
    # A missing/dead controller cannot park a logical peer indefinitely.
    while not exists(path):
        if not poll_roles(incoming, outgoing) or now_ms() - started > 15000:
            return False
    return True


# Retain exactly two IPv6 engines through fallback, duplicate arbitration, bidirectional queries and reconnects.
def run_mesh(args: List[String]) raises -> Bool:
    # Validate trusted utility controls before opening sockets or narrowing ports.
    if len(args) != 10:
        return False
    var local_port = capacity(args[2], 65535)
    var remote_port = capacity(args[3], 65535)
    var rounds = capacity(getenv("RAGNAROK_MESH_ROUNDS", "16"), 64)
    if local_port == 0 or remote_port == 0 or rounds == 0:
        # Missing ports/extent cannot start a retained listener with guessed controls.
        return False
    var local: List[UInt8]
    var remote: List[UInt8]
    # Both identities are native owned file bytes; no TLS-owned pointer survives verification.
    with open(args[6], "r") as file:
        local = file.read_bytes()
    with open(args[7], "r") as file:
        remote = file.read_bytes()
    if len(local) != 32 or len(remote) != 32:
        # No identity truncation or implicit zero padding is permitted.
        return False
    var equal = True
    for i in range(32):
        if local[i] != remote[i]:
            # Reject self/ambiguous peers using complete byte equality.
            equal = False
    if equal:
        return False
    var initiator = preferred(Span(local), Span(remote))
    var disrupted = getenv("RAGNAROK_MESH_DISRUPT") == "1"
    var profile = 3
    if disrupted:
        # The pinned short-expiry crash profile is an explicit experiment, not a changed normal peer timeout.
        profile = 4
    var gate = args[9].copy()
    var incoming = new_peer(True, remote.copy())
    var outgoing = new_peer(False, remote.copy())
    try:
        # These exact stable owners remain alive throughout every role-engine generation and close callback.
        if not open_role(
            incoming, UInt16(local_port), profile, args[4].copy(), args[5].copy(), args[8].copy()
        ):
            return False
        if not open_role(
            outgoing, UInt16(0), profile, args[4].copy(), args[5].copy(), args[8].copy()
        ):
            return False
        print("MESH_READY", Int(initiator))
        _ = external_call["rqm_flush", c_int]()
        var authenticated_in: UInt64 = 0
        var authenticated_out: UInt64 = 0
        # Every externally gated round retains the same four engine/socket owners across the pair of logical peers.
        for index in range(rounds):
            if not wait_gate(incoming, outgoing, gate + "/start-" + String(index)):
                return False
            var loss = disrupted and not exists(gate + "/healthy-final")
            var fallback = index == 0 and getenv("RAGNAROK_MESH_FALLBACK") == "1"
            var started = now_ms()
            if fallback:
                # Suppress the preferred dial and keep listeners responsive during the documented five-second fallback.
                while now_ms() - started < 5000:
                    if not poll_roles(incoming, outgoing):
                        return False
                if (
                    not initiator
                    and external_call["rq_connect", c_int](
                        outgoing.transport.engine, UInt16(remote_port)
                    )
                    == 0
                ):
                    # The nonpreferred peer must genuinely initiate the fallback connection.
                    return False
            else:
                # Race both outgoing engines so duplicate retirement is observed on authenticated connections.
                if (
                    external_call["rq_connect", c_int](
                        outgoing.transport.engine, UInt16(remote_port)
                    )
                    == 0
                ):
                    return False
            var use_outgoing = initiator
            if fallback:
                # The single nonpreferred fallback direction is deliberately kept for the first round.
                use_outgoing = not initiator
                if use_outgoing:
                    authenticated_out += 1
                else:
                    # Only one direction is attempted in the fallback proof.
                    authenticated_in += 1
            else:
                # Both handshake generations are required before preferred-direction arbitration runs.
                authenticated_in += 1
                authenticated_out += 1
            started = now_ms()
            # Wait for real handshake evidence in both attempted directions, not just a live socket.
            while True:
                var status = external_call["rq_status", c_int](incoming.transport.engine)
                if use_outgoing:
                    status = external_call["rq_status", c_int](outgoing.transport.engine)
                if (
                    status == 1
                    and external_call["rq_peer_metric", UInt64](incoming.transport.engine, c_int(4))
                    >= authenticated_in
                    and external_call["rq_peer_metric", UInt64](outgoing.transport.engine, c_int(4))
                    >= authenticated_out
                ):
                    break
                if not poll_roles(incoming, outgoing) or now_ms() - started > 10000:
                    # Wrong expected identities and dead peers are bounded failures without any CE exchange.
                    return False
            if not fallback:
                print("MESH_DUPLICATE", index)
                if use_outgoing:
                    # Keep the preferred outgoing connection and retire the incoming duplicate.
                    external_call["rq_disconnect", NoneType](incoming.transport.engine)
                else:
                    # The preferred incoming connection stays live while the outgoing duplicate closes.
                    external_call["rq_disconnect", NoneType](outgoing.transport.engine)
            started = now_ms()
            # Application work never starts while a losing duplicate still owns a live connection.
            while True:
                var active = external_call["rq_peer_metric", UInt64](
                    outgoing.transport.engine, c_int(0)
                )
                if use_outgoing:
                    active = external_call["rq_peer_metric", UInt64](
                        incoming.transport.engine, c_int(0)
                    )
                if active == 0:
                    break
                if not poll_roles(incoming, outgoing) or now_ms() - started > 10000:
                    return False
            var active = external_call["rq_peer_metric", UInt64](
                incoming.transport.engine, c_int(0)
            )
            if use_outgoing:
                active = external_call["rq_peer_metric", UInt64](
                    outgoing.transport.engine, c_int(0)
                )
            if active != 1:
                # The chosen authenticated connection must survive duplicate retirement.
                return False
            print("MESH_CONNECTED", index, Int(use_outgoing))
            # Four local queries share the same connection with four queries opened by the remote peer.
            for _ in range(4):
                if use_outgoing:
                    external_call["rq_open_stream", NoneType](outgoing.transport.engine)
                else:
                    external_call["rq_open_stream", NoneType](incoming.transport.engine)
            started = now_ms()
            while True:
                var healthy = incoming.progress.healthy
                var slots = live(incoming)
                if use_outgoing:
                    healthy = outgoing.progress.healthy
                    slots = live(outgoing)
                if healthy == 8 and slots == 0:
                    break
                if not poll_roles(incoming, outgoing) or now_ms() - started > 10000:
                    # Settled replies alone cannot conceal retained application buffers/native stream owners.
                    return False
            print("MESH_EXCHANGED", index, 8)
            _ = external_call["rqm_flush", c_int]()
            if loss:
                # The controller injects peer death only after healthy work has completely retired on both sides.
                if not wait_gate(incoming, outgoing, gate + "/pending-" + String(index)):
                    return False
                if use_outgoing:
                    outgoing.progress.recovering = True
                    outgoing.progress.attack = "no-fin"
                else:
                    # Pending queries follow the selected connection's actual stream direction.
                    incoming.progress.recovering = True
                    incoming.progress.attack = "no-fin"
                for _ in range(4):
                    if use_outgoing:
                        external_call["rq_open_stream", NoneType](outgoing.transport.engine)
                    else:
                        external_call["rq_open_stream", NoneType](incoming.transport.engine)
                started = now_ms()
                while True:
                    var ready = pending(incoming)
                    if use_outgoing:
                        ready = pending(outgoing)
                    if ready:
                        break
                    if not poll_roles(incoming, outgoing) or now_ms() - started > 10000:
                        # Actual sent/received prefixes are required before a process is killed.
                        return False
                print("MESH_PENDING", index, 8)
                _ = external_call["rqm_flush", c_int]()
            if not wait_gate(incoming, outgoing, gate + "/close-" + String(index)):
                return False
            if not loss:
                # Graceful rounds queue close while UDP readiness still owns both role engines.
                if use_outgoing:
                    external_call["rq_disconnect", NoneType](outgoing.transport.engine)
                else:
                    external_call["rq_disconnect", NoneType](incoming.transport.engine)
            started = now_ms()
            # Both connection roles and all application stream slots must retire before the next reconnect gate.
            while (
                external_call["rq_peer_metric", UInt64](incoming.transport.engine, c_int(0)) != 0
                or external_call["rq_peer_metric", UInt64](outgoing.transport.engine, c_int(0)) != 0
                or live(incoming) != 0
                or live(outgoing) != 0
            ):
                if not poll_roles(incoming, outgoing) or now_ms() - started > 10000:
                    return False
            if loss:
                var rejected = incoming.progress.rejected
                if use_outgoing:
                    rejected = outgoing.progress.rejected
                if rejected != 8:
                    # Every interrupted owner settles once, rather than disappearing silently on connection close.
                    return False
                print("MESH_RECOVERED", index, rejected)
            # Reset only per-round counters/policy; engine/socket/identity owners remain unchanged.
            incoming.progress.healthy = 0
            incoming.progress.completed = 0
            incoming.progress.rejected = 0
            incoming.progress.recovering = False
            incoming.progress.attack = "valid"
            outgoing.progress.healthy = 0
            outgoing.progress.completed = 0
            outgoing.progress.rejected = 0
            outgoing.progress.recovering = False
            outgoing.progress.attack = "valid"
            print(
                "MESH_IDLE",
                index,
                external_call["rqm_heap_used", UInt64](),
                external_call["rq_peer_metric", UInt64](incoming.transport.engine, c_int(1)),
                external_call["rq_peer_metric", UInt64](outgoing.transport.engine, c_int(1)),
                external_call["rq_peer_metric", UInt64](incoming.transport.engine, c_int(2)),
                external_call["rq_peer_metric", UInt64](outgoing.transport.engine, c_int(2)),
            )
            _ = external_call["rqm_flush", c_int]()
        # Preserve the last fully retired observation until the controller explicitly requests normal shutdown.
        return wait_gate(incoming, outgoing, gate + "/stop")
    finally:
        # Final close callbacks borrow both still-live Peer owners; retire outgoing before incoming TLS globals.
        incoming.progress.stopping = True
        outgoing.progress.stopping = True
        close_transport(outgoing.transport)
        close_transport(incoming.transport)
