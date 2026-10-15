from std.ffi import external_call, c_int, c_short, c_size_t, get_errno
from std.collections import Array, Span, Optional
from std.time import perf_counter_ns


comptime NativePointer = OpaquePointer[mut=True, MutUntrackedOrigin]


# POSIX readiness metadata is composed only of public C-compatible scalar fields.
@fieldwise_init
struct PollFd(RegisterPassable):
    var fd: c_int
    var events: c_short
    var revents: c_short


# Socket and engine owners remain at stable native addresses throughout synchronous callback dispatch.
@fieldwise_init
struct Transport(Movable):
    var engine: Optional[NativePointer]
    var fd: c_int
    var stopping: Bool
    var failed: Bool
    var packet: Array[UInt8, 2048]
    var ipv6: Bool


# Native monotonic milliseconds drive application deadlines without wall-clock adjustments.
def now_ms() -> Int:
    return Int(perf_counter_ns() // 1000000)


# Retire UDP readiness before engine destruction; final native close callbacks still see a live peer owner.
def close_transport(mut owner: Transport):
    owner.stopping = True
    # A successful socket creation has exactly one descriptor release owner.
    if owner.fd >= 0:
        _ = external_call["close", c_int](owner.fd)
        owner.fd = -1
    # Native destruction may synchronously deliver final stream-close events.
    if owner.engine:
        external_call["rq_transport_free", NoneType](owner.engine)
        owner.engine = None


# Drive bounded datagram reads and native timers on one I/O thread; no task or thread is created per stream.
def poll_transport(mut owner: Transport) -> Bool:
    # Failed/retired owners cannot restart native callback work.
    if owner.stopping or owner.failed or not owner.engine:
        return False
    var tick = external_call["rq_next_tick", Int64](owner.engine)
    var delay = min(10, max(1, Int((tick + 999) // 1000)))
    var item = PollFd(owner.fd, c_short(1), c_short(0))
    var ready = external_call["rqm_poll", c_int](Pointer(to=item), c_size_t(1), c_int(delay))
    # Interrupted waits retry on the next bounded cycle; invalid descriptors are terminal.
    if ready < 0:
        # Signals may interrupt a valid poll; retry without retiring its socket or connection owner.
        if get_errno() == .EINTR:
            return True
        owner.failed = True
        return False
    # Ready descriptors drain bounded work while unready descriptors still receive scheduled transport ticks.
    if ready > 0:
        if (Int(item.revents) & 56) != 0:
            # POLLERR/POLLHUP/POLLNVAL cannot become valid application progress.
            owner.failed = True
            return False
        if not drain(owner):
            # Receive errors are surfaced independently of authentication and application framing.
            return False
    external_call["rq_process", NoneType](owner.engine)
    return not owner.failed


# Bound one ready socket's datagrams so a flooded endpoint cannot starve its sibling or native deadlines.
def drain(mut owner: Transport) -> Bool:
    # Reuse the same owned receive array until each synchronous packet-processing call returns.
    for _ in range(64):
        var source: UInt16 = 0
        var got: Int64 = 0
        if owner.ipv6:
            # The narrow OS helper handles only IPv6 address layout and loopback validation.
            got = external_call["rqm_udp_recv6", Int64](
                owner.fd,
                owner.packet.unsafe_ptr().as_unsafe_any_origin(),
                c_size_t(2048),
                Pointer(to=source),
            )
        else:
            # Preserve the original IPv4 authentication/framing corpus unchanged.
            got = external_call["rqm_udp_recv", Int64](
                owner.fd,
                owner.packet.unsafe_ptr().as_unsafe_any_origin(),
                c_size_t(2048),
                Pointer(to=source),
            )
        if got == -2:
            # Would-block/interrupt retires this readiness notification without destroying the owner.
            break
        elif got < 0:
            # Other OS failures cannot fabricate a valid packet or peer activity.
            owner.failed = True
            return False
        elif got > 0:
            # Payloads are borrowed by LSQUIC only for this synchronous processing call.
            _ = external_call["rq_packet_in", c_int](
                owner.engine,
                owner.packet.unsafe_ptr().as_imm().as_unsafe_any_origin(),
                c_size_t(got),
                source,
            )
            external_call["rq_process", NoneType](owner.engine)
    return not owner.failed


# Dispatch both retained role engines on one native poll call, with a common earliest timer deadline.
def poll_pair(mut incoming: Transport, mut outgoing: Transport) -> Bool:
    # A retired/failed endpoint must not silently be replaced by a second independent blocking dispatcher.
    if incoming.stopping or outgoing.stopping or incoming.failed or outgoing.failed:
        return False
    var tick = min(
        external_call["rq_next_tick", Int64](incoming.engine),
        external_call["rq_next_tick", Int64](outgoing.engine),
    )
    var delay = min(10, max(1, Int((tick + 999) // 1000)))
    var items: Array[PollFd, 2] = [PollFd(incoming.fd, 1, 0), PollFd(outgoing.fd, 1, 0)]
    var count = external_call["rqm_poll", c_int](items.unsafe_ptr(), c_size_t(2), c_int(delay))
    if count < 0:
        # Interrupted waits retry; other readiness errors settle the bounded logical peer.
        return get_errno() == .EINTR
    if (Int(items[0].revents) & 56) != 0 or (Int(items[1].revents) & 56) != 0:
        # Neither role may hide its sibling's descriptor failure.
        return False
    if items[0].revents != 0 and not drain(incoming):
        # Ready incoming work is bounded before allowing the outgoing role to progress.
        return False
    if items[1].revents != 0 and not drain(outgoing):
        # The outgoing role retains its own socket and receive storage.
        return False
    external_call["rq_process", NoneType](incoming.engine)
    external_call["rq_process", NoneType](outgoing.engine)
    return not incoming.failed and not outgoing.failed


# Copy actual ABI offsets from the C compiler into native bounded scalar metadata once per verification call.
def cert_layout() -> Array[Int, 10]:
    var result = Array[Int, 10](fill=-1)
    # Every field offset is derived from the exact shared extractor header rather than guessed in Mojo.
    for i in range(10):
        var value = external_call["rqm_cert_layout", c_size_t](c_int(i))
        # A foreign layout larger than the bounded proof storage is unsupported and must fail closed.
        if value <= 512:
            result[i] = Int(value)
    return result^


# Validate copied primitive observations and key-derived JAMNP-S SAN bytes entirely in native Mojo.
def valid_peer(
    der: Pointer[mut=False, UInt8, _], length: c_size_t, expected: Span[mut=False, UInt8, _]
) -> Bool:
    var offsets = cert_layout()
    # Foreign aggregate arrays are not register-passable in Mojo; use aligned bounded storage with measured offsets.
    if offsets[0] < 0 or offsets[0] > 512:
        return False
    var record = Array[UInt64, 64](fill=0)
    var raw = record.unsafe_ptr().unsafe_bitcast[UInt8]()
    # The existing strict extractor only supplies observations; no JAM identity policy moves into C.
    if (
        external_call["rq_parse_cert", c_int](
            der.as_unsafe_any_origin(),
            length,
            raw.unsafe_bitcast[NoneType]().as_unsafe_any_origin(),
        )
        != 1
    ):
        return False
    # Require all five algorithm/name flags, after proving each measured scalar slot fits the record.
    for i in range(1, 6):
        if offsets[i] < 0 or offsets[i] > offsets[0] - 4 or offsets[i] % 4 != 0:
            # Unsupported layouts never permit an unaligned/out-of-bounds foreign scalar load.
            return False
        if raw.unsafe_offset(offsets[i]).unsafe_bitcast[c_int]().unsafe_load() != 1:
            # Both Ed25519 algorithms and exactly one DNS SAN must match the JAMNP-S identity contract.
            return False
    # Both size_t observations must fit and be naturally aligned before loading them.
    for i in range(6, 8):
        if offsets[i] < 0 or offsets[i] > offsets[0] - 8 or offsets[i] % 8 != 0:
            return False
    var key_length = raw.unsafe_offset(offsets[6]).unsafe_bitcast[c_size_t]().unsafe_load()
    var san_length = raw.unsafe_offset(offsets[7]).unsafe_bitcast[c_size_t]().unsafe_load()
    # Exact lengths forbid prefix/embedded-NUL acceptance and malformed key narrowing.
    if key_length != 32 or san_length != 54:
        return False
    # Prove both bounded byte-array endpoints before constructing native immutable spans.
    if (
        offsets[8] < 0
        or offsets[8] > offsets[0] - 32
        or offsets[9] < 0
        or offsets[9] > offsets[0] - 54
    ):
        return False
    var key = Span(unsafe_ptr=raw.unsafe_offset(offsets[8]).as_imm(), length=32)
    var san = Span(unsafe_ptr=raw.unsafe_offset(offsets[9]).as_imm(), length=54)
    # JAMNP-S uses the literal least-significant-first alphabet, including dollar as its zero digit.
    if san[0] != 36 or san[1] != 101:
        return False
    var alphabet = String("$abcdefghijklmnopqrstuvwxyz234567")
    var chars = alphabet.as_bytes()
    # Each of the 52 groups gathers five little-endian key bits, zero-extending the final group.
    for group in range(52):
        var index = 0
        for bit in range(5):
            var position = group * 5 + bit
            # Bits above the actual 256-bit public key are zero, never read from adjacent storage.
            if position < 256:
                index |= ((Int(key[position // 8]) >> (position % 8)) & 1) << bit
        if san[2 + group] != chars[index]:
            # Any changed SAN byte rejects the claimed key identity.
            return False
    # Dialers pin an exact expected key; listeners may discover an internally consistent peer identity.
    if len(expected) > 0:
        if len(expected) != 32:
            # Trusted malformed expectations cannot be silently truncated.
            return False
        for i in range(32):
            if key[i] != expected[i]:
                # Compare every identity byte, not a short prefix.
                return False
    return True
