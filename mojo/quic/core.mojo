from std.collections import Array, Span, Optional
from std.ffi import external_call, c_int, c_size_t
from std.sys import argv, get_defined_bool
from std.os import getenv
from std.os.path import exists
from quic.transport import *
from quic.selftests import runtime_probe, io_selftest
from quic.integration import *
import quic.offload as offload
from codec.types import Failure, CheckedResult
from tests.support import capacity


comptime INTEGRATION_ENABLED = get_defined_bool["INTEGRATION", False]()


# Exact independent Blake2b fixture key shared by the existing CE 143 interoperability corpus.
def request_hash() -> Array[UInt8, 32]:
    # Local fixed storage is allocation-free and owns the exact independent fixture bytes.
    var result: Array[UInt8, 32] = [
        17,
        192,
        231,
        155,
        113,
        195,
        151,
        108,
        205,
        12,
        2,
        209,
        49,
        14,
        37,
        22,
        192,
        142,
        220,
        157,
        139,
        111,
        87,
        204,
        214,
        128,
        214,
        58,
        77,
        142,
        114,
        218,
    ]
    return result^


# One live native stream owns both application buffers until the final native close callback.
@fieldwise_init
struct StreamState(Copyable, Movable):
    var handle: Optional[NativePointer]
    var received: List[UInt8]
    var sending: List[UInt8]
    var received_length: Int
    var send_length: Int
    var send_offset: Int
    var read_fin: Bool
    var write_fin: Bool
    var counted: Bool
    var started: Int
    var attack: String
    var paused: Bool
    var blocked: Bool
    var responder: Bool
    var query: PreimageKey
    var fixture: Int
    var verified: VerifiedDigest
    var job: offload.JobId


# Application progress is separate from stream storage so the borrow checker can prove disjoint mutations.
@fieldwise_init
struct Progress(Copyable, Movable):
    var server: Bool
    var failed: Bool
    var stopping: Bool
    var completed: Int
    var opened: Int
    var attack: String
    var healthy: Int
    var rejected: Int
    var cancelled: Int
    var mixed: Bool
    var service: Bool
    var target: Int
    var mesh: Bool
    var recovering: Bool
    var overload: Bool
    var capacity_rejected: Int
    var peak_streams: Int
    var integrated: Bool
    var offloading: Bool
    var light: Bool
    var bad_proof: Bool


# One stable native owner outlives all synchronous C callbacks and engine/socket retirement.
@fieldwise_init
struct Peer(Movable):
    var transport: Transport
    var expected: List[UInt8]
    var progress: Progress
    var streams: List[StreamState]
    var bank: IntegrationBank
    var pool: offload.Pool


# A retired slot borrows no stream handle and retains no application buffer allocation.
def empty_stream() -> StreamState:
    return StreamState(
        None,
        List[UInt8](),
        List[UInt8](),
        0,
        0,
        0,
        False,
        False,
        False,
        0,
        String(),
        False,
        False,
        False,
        PreimageKey(Array[UInt8, 32](fill=0)),
        -1,
        empty_verified(),
        offload.JobId(0),
    )


# Settle one stream exactly once, distinguishing authenticated transport from validated application work.
def finish(mut peer: Progress, mut state: StreamState, good: Bool):
    # Reset/close notifications may describe the same terminal outcome repeatedly.
    if state.counted:
        return
    state.counted = True
    # Healthy means exact request/reply bytes and required FIN have been validated.
    if good:
        peer.completed += 1
        peer.healthy += 1
        if peer.attack == "soak":
            # Lifecycle markers describe verified application outcomes, never merely authentication.
            if peer.server:
                print("SERVER_HEALTHY")
            else:
                print("HEALTHY_OK")
    elif (
        peer.attack == "soak" or peer.service or (peer.mesh and peer.recovering) or peer.offloading
    ):
        # Expected adversarial streams settle locally while healthy sibling/peer owners stay live.
        peer.completed += 1
        peer.rejected += 1
        if peer.server:
            print("STREAM_REJECTED")
        else:
            print("EXPECTED_REJECT")
    else:
        # A one-shot malformed application request fails only its bounded attempted exchange.
        peer.failed = True


# Parse one exact incrementally received CE frame; hostile E4 lengths never select an allocation.
def frame_extent(peer: Progress, state: StreamState) -> Tuple[Bool, Bool]:
    var start = Int(state.responder)
    # Incoming requests explicitly select CE 143 before the length header.
    if state.responder and state.received_length > 0 and state.received[0] != 143:
        return (False, False)
    # An incomplete header is pending only while the sender has not ended its direction.
    if state.received_length < start + 4:
        return (False, not state.read_fin)
    var claimed: UInt64 = 0
    # Decode the complete fixed E4 header with shifts bounded to its 32-bit wire extent.
    for i in range(4):
        claimed |= UInt64(state.received[start + i]) << UInt64(8 * i)
    var maximum: UInt64 = 1024
    # Preimage request hashes have exact 32-byte width; replies use the established proof cap.
    if state.responder:
        maximum = 32
    elif peer.integrated:
        # Standalone C.2 digest preimages are bounded by the same integration fixture cap.
        maximum = UInt64(WIRE_CAP)
    elif peer.attack == "soak":
        # The stress profile explicitly allows only the bounded trusted large fixture.
        maximum = 1024 * 1024
    if claimed > maximum:
        # Reject an oversized claim before host conversion, indexing or any response allocation.
        return (False, False)
    var extent = start + 4 + Int(claimed)
    # One-message directions reject trailing bytes even before FIN arrives.
    if state.received_length > extent:
        return (False, False)
    elif not state.read_fin:
        # Even exact bytes remain pending until the required half-close.
        return (False, True)
    elif state.received_length != extent:
        # FIN before the declared payload is truncation, never implicit zero padding.
        return (False, False)
    if peer.integrated:
        # Framing completes before native codec/ownership/hash composition selects a payload response.
        if state.responder and claimed != 32:
            return (False, False)
        return (True, True)
    if state.responder:
        # Lookups require the entire exact fixture key, not merely a valid request size.
        if claimed != 32:
            return (False, False)
        var wanted = request_hash()
        if peer.offloading and state.received[5] == light_hash()[0]:
            # Cheap lookups still compare every key byte before bypassing the fixed proof workers.
            wanted = light_hash()
        elif peer.offloading and state.received[5] == bad_proof_hash()[0]:
            # Negative proof policy must not be inferred from an unrelated shared key prefix.
            wanted = bad_proof_hash()
        # Large fixture lookups still compare all 32 content-key bytes.
        if peer.attack == "soak" and state.received[5] == large_hash()[0]:
            wanted = large_hash()
        for i in range(32):
            if state.received[5 + i] != wanted[i]:
                # Unknown fixture hashes must not select a default preimage.
                return (False, False)
    else:
        var size = 3
        # Only the deliberately slow healthy stream expects the complete one-MiB fixture.
        if state.attack == "slow":
            size = 1024 * 1024
        if claimed != UInt64(size):
            return (False, False)
        # Verify every actual payload byte independently of native transport chunking.
        for i in range(size):
            var start = 1
            if peer.light:
                start = 4
            elif peer.bad_proof:
                # A failed proof never delivers this payload; any fabricated positive reply fails the independent harness.
                start = 7
            var wanted = UInt8((i + start) % 256)
            if size > 3:
                # The large fixture's periodic bytes are independently hashed by the controller.
                wanted = UInt8(i % 251)
            if state.received[4 + i] != wanted:
                return (False, False)
    return (True, True)


# Create bounded native buffers and request bytes only after stream admission succeeds.
def new_stream(
    mut peer: Progress,
    mut state: StreamState,
    bank: IntegrationBank,
    handle: NativePointer,
    responder: Bool,
):
    var receive_capacity = 1050
    # The soak's bounded one-MiB replies have an explicit fixture capacity, never an untrusted claimed allocation.
    if not peer.server and peer.attack == "soak":
        receive_capacity = 1024 * 1024 + 5
    # Integrated bodies are independently bounded full digest frames.
    if not responder and peer.integrated:
        receive_capacity = WIRE_CAP + 5
    state = StreamState(
        handle,
        List[UInt8](length=receive_capacity, fill=0),
        List[UInt8](),
        0,
        0,
        0,
        False,
        False,
        False,
        now_ms(),
        peer.attack.copy(),
        False,
        False,
        responder,
        PreimageKey(Array[UInt8, 32](fill=0)),
        -1,
        empty_verified(),
        offload.JobId(0),
    )
    # Acceptors wait for one fully validated request before allocating a reply.
    if responder:
        return
    comptime if INTEGRATION_ENABLED:
        if peer.integrated:
            var index = peer.opened
            if index >= 8:
                # The trusted integrated workload cannot grow a query queue beyond its explicit corpus.
                peer.failed = True
                external_call["rq_stream_abort", NoneType](handle)
                return
            peer.opened += 1
            state.fixture = index
            state.query = bank.keys[index].copy()
            state.attack = "valid"
            if index == 6:
                # Cancellation retains a real large owned snapshot behind withheld response credit.
                state.attack = "cancel"
                state.paused = True
                external_call["rq_stream_want_read", NoneType](handle, c_int(0))
            state.sending = List[UInt8](length=64, fill=0)
            state.sending[0] = 143
            state.sending[1] = 32
            for i in range(32):
                # Keys are complete typed content hashes of the actual independently supplied digest bytes.
                state.sending[5 + i] = state.query.bytes[i]
            if index == 4:
                # Request a deliberately absent key while preserving correct CE framing.
                state.sending[5] ^= 1
            state.send_length = 37
            external_call["rq_stream_want_write", NoneType](handle, c_int(1))
            return
    var wanted = request_hash()
    if peer.light:
        # The cheap preimage skips proof work but retains exact complete content-key lookup semantics.
        wanted = light_hash()
    elif peer.bad_proof:
        # Wrong-domain proof policy is selected only by its own independently checked full fixture key.
        wanted = bad_proof_hash()
    # Five initial streams exercise healthy work, real backpressure, cancellation, bad kind and missing FIN.
    if peer.attack == "soak":
        if peer.opened == 1:
            state.attack = "slow"
            wanted = large_hash()
        elif peer.opened == 2:
            state.attack = "cancel"
            wanted = large_hash()
        elif peer.opened == 3:
            state.attack = "bad-kind"
        elif peer.opened == 4:
            state.attack = "no-fin"
        else:
            # The first and three later siblings use exact normal fixture bytes.
            state.attack = "valid"
    peer.opened += 1
    state.sending = List[UInt8](length=64, fill=0)
    state.sending[0] = 143
    state.sending[1] = 32
    # Every request initially selects the exact independent fixture preimage key.
    for i in range(32):
        state.sending[5 + i] = wanted[i]
    state.send_length = 37
    # Malformed fixtures are introduced only after transport authentication.
    if state.attack == "bad-kind":
        state.sending[0] = 144
    elif state.attack == "oversize":
        # The hostile UInt32 claim must be rejected before an input-derived allocation.
        for i in range(1, 5):
            state.sending[i] = 255
    elif state.attack == "unknown":
        # Retain a valid frame while deliberately selecting a nonexistent database key.
        state.sending[5] ^= 1
    elif state.attack == "truncated":
        # FIN arrives one byte before the declared request hash is complete.
        state.send_length = 36
    elif state.attack == "trailing":
        # One extra byte violates the one-message rule despite an otherwise valid request.
        state.send_length = 38
    elif state.attack not in ("valid", "slow", "cancel", "no-fin", "proof-cancel"):
        # Unknown trusted controls never silently select a valid application request.
        peer.failed = True
        external_call["rq_stream_abort", NoneType](handle)
        return
    # Withhold application reads so transport receive credit genuinely runs out.
    if state.attack in ("slow", "cancel", "proof-cancel"):
        state.paused = True
        external_call["rq_stream_want_read", NoneType](handle, c_int(0))
    external_call["rq_stream_want_write", NoneType](handle, c_int(1))


# Drain available bytes into the same bounded native owner, preserving partial framing across would-block events.
def read_stream(
    mut peer: Progress, mut state: StreamState, bank: IntegrationBank, mut pool: offload.Pool
):
    var handle = state.handle.value()
    # Paused readers retain their existing buffer while deliberately withholding flow-control credit.
    if state.paused:
        return
    # All stream reads share this I/O thread; no per-stream thread or coroutine is created.
    while True:
        var available = len(state.received) - state.received_length
        # A full buffer cannot accept another byte or fabricate a clean FIN.
        if available == 0:
            finish(peer, state, False)
            external_call["rq_stream_abort", NoneType](handle)
            return
        var got = external_call["rq_stream_read", Int64](
            handle,
            state.received.unsafe_ptr().unsafe_offset(state.received_length).as_unsafe_any_origin(),
            c_size_t(available),
        )
        # Would-block preserves the stream owner and all received bytes.
        if got == -2:
            return
        elif got < 0 or got > Int64(available):
            # Reset/impossible extents settle this attempted exchange without out-of-bounds writes.
            finish(peer, state, False)
            external_call["rq_stream_abort", NoneType](handle)
            return
        elif got == 0:
            # Zero is an actual FIN, not an empty data read.
            state.read_fin = True
        else:
            # Positive reads fit the proved available capacity before conversion.
            state.received_length += Int(got)
        var extent = frame_extent(peer, state)
        # Protocol failures never leave a read handler or reply buffer pending.
        if not extent[1]:
            finish(peer, state, False)
            external_call["rq_stream_abort", NoneType](handle)
            return
        elif extent[0]:
            # Stop repeated EOF notifications only after exact framing and FIN validation.
            # Retained IPv6 profiles retire a validated read half explicitly, independently of raw EOF.
            if peer.mesh:
                external_call["rq_stream_read_done", NoneType](handle)
            external_call["rq_stream_want_read", NoneType](handle, c_int(0))
            comptime if offload.ENABLED:
                if peer.offloading and state.responder and state.received[5] != light_hash()[0]:
                    state.job = offload.submit(pool, state.received[5] == bad_proof_hash()[0])
                    if state.job.value == 0:
                        # Capacity refusal settles only this stream; queued/running/completed owners all retain their slots.
                        print("OFFLOAD_REJECT Capacity")
                        finish(peer, state, False)
                        external_call["rq_stream_abort", NoneType](handle)
                    else:
                        # No response is allocated until the I/O thread selects this generation's verified completion.
                        print("OFFLOAD_ADMIT", state.job.value)
                    return
            comptime if INTEGRATION_ENABLED:
                if peer.integrated:
                    if state.responder:
                        var index = find_fixture(bank, Span(state.received)[5:37])
                        if index < 0:
                            # Missing keys never select a default record or filename.
                            print("INTEGRATION_REJECT Lookup")
                            finish(peer, state, False)
                            external_call["rq_stream_abort", NoneType](handle)
                            return
                        state.fixture = index
                        var scratch = bank.wires[index].copy()
                        var checked = capture_digest(Span(scratch), bank.keys[index])
                        if checked.isa[Failure]():
                            # Malformed/trailing/ownership failures remain local to their authenticated stream.
                            print("INTEGRATION_REJECT", reject_reason(checked[Failure]))
                            finish(peer, state, False)
                            external_call["rq_stream_abort", NoneType](handle)
                            return
                        state.verified = checked[VerifiedDigest].copy()
                        # Report actual successful owner capture before queued response/cancellation can retire it.
                        print("OWNED_VERIFIED")
                        var size = len(state.verified.wire)
                        state.sending = List[UInt8](length=size + 4, fill=0)
                        for i in range(4):
                            # E4 frames only the exact owner-derived standalone preimage serialization.
                            state.sending[i] = UInt8((size >> (8 * i)) & 255)
                        for i in range(size):
                            # Original scratch was already overwritten; only the retained snapshot supplies response bytes.
                            state.sending[4 + i] = state.verified.wire[i]
                        if index == 5:
                            # Test-only corruption preserves a valid digest but intentionally breaks its content key.
                            state.sending[8] ^= 1
                        state.send_length = size + 4
                        external_call["rq_stream_want_write", NoneType](handle, c_int(1))
                    else:
                        var checked = capture_digest(
                            Span(state.received)[4 : state.received_length], state.query
                        )
                        if checked.isa[Failure]():
                            # Failed content binding exposes no usable owned digest to the application.
                            print("INTEGRATION_REJECT", reject_reason(checked[Failure]))
                            finish(peer, state, False)
                            external_call["rq_stream_abort", NoneType](handle)
                            return
                        state.verified = checked[VerifiedDigest].copy()
                        print("OWNED_VERIFIED")
                        finish(peer, state, True)
                    return
            if state.responder:
                # Only the exact validated request key can select the trusted bounded reply.
                var size = 3
                # A validated large content key selects exactly the bounded trusted one-MiB fixture.
                if peer.attack == "soak" and state.received[5] == large_hash()[0]:
                    size = 1024 * 1024
                state.sending = List[UInt8](length=size + 4, fill=0)
                # Encode E4 natively before copying fixture bytes; the C bridge contains no CE framing.
                for i in range(4):
                    state.sending[i] = UInt8((size >> (8 * i)) & 255)
                for i in range(size):
                    var start = 1
                    if peer.offloading and state.received[5] == light_hash()[0]:
                        # Exact cheap fixture bytes progress alongside real Rust verification batches.
                        start = 4
                    var byte = UInt8((i + start) % 256)
                    if size > 3:
                        # The large fixture is a deterministic test payload, not protocol-generated data.
                        byte = UInt8(i % 251)
                    state.sending[4 + i] = byte
                state.send_length = size + 4
                external_call["rq_stream_want_write", NoneType](handle, c_int(1))
            else:
                # The requester has verified the exact response bytes and FIN.
                finish(peer, state, True)
            return


# Keep the unsent native buffer intact through partial writes and transport flow-control stalls.
def write_stream(mut peer: Progress, mut state: StreamState, pool: offload.Pool):
    var handle = state.handle.value()
    # Every accepted byte advances only this stream's cursor into its retained owner.
    while state.send_offset < state.send_length:
        var remaining = state.send_length - state.send_offset
        var sent = external_call["rq_stream_write", Int64](
            handle,
            state.sending.unsafe_ptr()
            .unsafe_offset(state.send_offset)
            .as_imm()
            .as_unsafe_any_origin(),
            c_size_t(remaining),
        )
        # No credit means pending work; preserve subscription and buffer for the next callback.
        if sent == -2 or sent == 0:
            return
        elif sent < 0 or sent > Int64(remaining):
            # Failed/impossible native extents cannot become successful message progress.
            finish(peer, state, False)
            external_call["rq_stream_abort", NoneType](handle)
            return
        state.send_offset += Int(sent)
    # Flush delivers no-FIN requests too, so the receiver can enforce its bounded deadline.
    if external_call["rq_stream_flush", c_int](handle) != 0:
        finish(peer, state, False)
        external_call["rq_stream_abort", NoneType](handle)
        return
    external_call["rq_stream_want_write", NoneType](handle, c_int(0))
    # FIN half-closes writing while keeping the opposite direction available for the response.
    if not state.write_fin and (state.responder or state.attack != "no-fin"):
        external_call["rq_stream_fin", NoneType](handle)
        state.write_fin = True
        if state.responder:
            # Server success includes a validated request and a queued complete reply FIN.
            finish(peer, state, True)
            comptime if offload.ENABLED:
                if (
                    peer.offloading
                    and state.received_length == 37
                    and state.received[5] == light_hash()[0]
                ):
                    # Count only real Rust execution, excluding queued/held owners, at this completed lightweight FIN.
                    print("OFFLOAD_LIGHT_DONE", offload.busy(pool))


# Verify borrowed TLS DER synchronously; no certificate pointer or asynchronous frame escapes the callback.
def verify_peer(
    user: OpaquePointer[mut=True, _], der: Pointer[mut=False, UInt8, _], length: c_size_t
) abi("C") -> c_int:
    ref peer = user.unsafe_bitcast[Peer]()[]
    # Shutdown cannot admit new identity-validation work.
    if peer.progress.stopping:
        return 0
    return c_int(valid_peer(der, length, Span(peer.expected)))


# Borrow and send C-owned packet bytes only during this callback; no packet pointer is retained.
def send_packet(
    user: OpaquePointer[mut=True, _],
    data: Pointer[mut=False, UInt8, _],
    length: c_size_t,
    port: UInt16,
) abi("C") -> c_int:
    ref peer = user.unsafe_bitcast[Peer]()[]
    # Native destruction may attempt sends after the OS socket has already retired.
    if peer.progress.stopping or peer.transport.fd < 0:
        return 0
    # Datagram extent must fit the same bounded transport capacity used for receives.
    if length > 2048:
        peer.transport.failed = True
        return 0
    var sent: Int64 = 0
    # OS address construction is family-specific; packet ownership and transport policy stay native.
    if peer.transport.ipv6:
        sent = external_call["rqm_udp_send6", Int64](
            peer.transport.fd, data.as_unsafe_any_origin(), length, port
        )
    else:
        sent = external_call["rqm_udp_send", Int64](
            peer.transport.fd, data.as_unsafe_any_origin(), length, port
        )
    # Only a complete datagram is delivery; backpressure retries later without a false success marker.
    return c_int(sent == Int64(length))


# Resolve one stable application owner per native stream and retire its buffers only on final close.
def on_stream(
    user: OpaquePointer[mut=True, _], native: OpaquePointer[mut=True, _], event: c_int
) abi("C"):
    ref peer = user.unsafe_bitcast[Peer]()[]
    var handle: NativePointer = native.unsafe_origin_cast[MutUntrackedOrigin]()
    var found = -1
    # Find only a currently retained live handle; retired slots are never dereferenced by a later event.
    for i in range(len(peer.streams)):
        if peer.streams[i].handle and Int(peer.streams[i].handle.value()) == Int(handle):
            found = i
            break
    if event == 0:
        # The fixed 64-slot capacity bounds all concurrent native-language application owners.
        for i in range(len(peer.streams)):
            if not peer.streams[i].handle:
                found = i
                break
        if found < 0:
            # Capacity refusal acquires no application buffer and cannot grow an unbounded queue.
            # A retained service refuses only the new stream; existing application owners are preserved.
            if not peer.progress.service:
                peer.progress.failed = True
            else:
                # Admission refuses only this new owner, leaving all existing connections/streams intact.
                peer.progress.capacity_rejected += 1
            external_call["rq_stream_abort", NoneType](handle)
            return
        var responder = peer.progress.server
        # Bidirectional CE queries follow the actual stream initiator, independently of connection role.
        if peer.progress.mesh:
            responder = external_call["rq_stream_local", c_int](peer.transport.engine, handle) == 0
        new_stream(peer.progress, peer.streams[found], peer.bank, handle, responder)
        if peer.progress.overload:
            var slots = 0
            # Observe actual retained application owners independently of native stream credit.
            for i in range(len(peer.streams)):
                if peer.streams[i].handle:
                    slots += 1
            peer.progress.peak_streams = max(peer.progress.peak_streams, slots)
        return
    elif found < 0:
        # Unexpected native events cannot borrow released application state.
        # Capacity-refused service streams acquired no application buffers and need no final release.
        if not peer.progress.service or (event != 3 and event != 4):
            peer.progress.failed = True
        return
    elif event == 3:
        comptime if offload.ENABLED:
            if peer.progress.offloading:
                # Final close cancels only this stream's generation; running Rust retains its copied inputs until return.
                offload.cancel(peer.pool, peer.streams[found].job)
        # A premature close settles pending work unless the entire endpoint is already shutting down.
        if not peer.streams[found].counted and not peer.progress.stopping:
            finish(peer.progress, peer.streams[found], False)
        # A stream owns its verified snapshot until this final native close, including cancelled parked replies.
        if peer.streams[found].verified.owner._opaque:
            if (
                peer.progress.integrated
                and peer.streams[found].responder
                and peer.streams[found].fixture == 6
            ):
                print("OWNED_CANCEL_RELEASE")
            release_verified(peer.streams[found].verified)
        peer.streams[found] = empty_stream()
        return
    elif event == 4:
        comptime if offload.ENABLED:
            if peer.progress.offloading:
                # Directional reset cannot cancel a different generation after a slot/stream handle is reused.
                offload.cancel(peer.pool, peer.streams[found].job)
        # Directional reset settles pending state before final close retires its buffers.
        if not peer.progress.stopping:
            finish(peer.progress, peer.streams[found], False)
        external_call["rq_stream_abort", NoneType](handle)
        return
    # No application work starts during teardown or after a completed client response.
    if peer.progress.stopping or (
        peer.streams[found].counted and not peer.streams[found].responder
    ):
        return
    if event == 1:
        # Read callbacks validate incremental framing using the same retained buffer.
        var before = peer.progress.healthy
        read_stream(peer.progress, peer.streams[found], peer.bank, peer.pool)
        # Compare live native peer ownership without retaining any connection pointer.
        if peer.progress.service and peer.progress.healthy > before:
            for i in range(len(peer.streams)):
                if (
                    peer.streams[i].handle
                    and peer.streams[i].blocked
                    and not peer.streams[i].counted
                ):
                    if (
                        external_call["rq_stream_same_peer", c_int](
                            handle, peer.streams[i].handle.value()
                        )
                        == 0
                    ):
                        print("ISOLATED_HEALTHY")
                        break
    elif event == 2:
        # Write callbacks retain unsent bytes across flow-control stalls.
        var before = peer.progress.healthy
        write_stream(peer.progress, peer.streams[found], peer.pool)
        # Server completion occurs after its validated response FIN has been queued.
        if peer.progress.service and peer.progress.healthy > before:
            for i in range(len(peer.streams)):
                if (
                    peer.streams[i].handle
                    and peer.streams[i].blocked
                    and not peer.streams[i].counted
                ):
                    if (
                        external_call["rq_stream_same_peer", c_int](
                            handle, peer.streams[i].handle.value()
                        )
                        == 0
                    ):
                        print("ISOLATED_HEALTHY")
                        break
    else:
        # Unknown native event numbers cannot select a guessed application action.
        peer.progress.failed = True


# Exact independently checked key of the cheap three-byte fixture served without occupying proof capacity.
def light_hash() -> Array[UInt8, 32]:
    var result: Array[UInt8, 32] = [
        10,
        253,
        74,
        4,
        215,
        114,
        13,
        169,
        146,
        47,
        43,
        64,
        36,
        153,
        137,
        250,
        244,
        255,
        128,
        150,
        225,
        237,
        73,
        190,
        230,
        21,
        187,
        108,
        177,
        238,
        79,
        125,
    ]
    return result^


# Exact independently checked key selecting the wrong-domain proof rejection policy.
def bad_proof_hash() -> Array[UInt8, 32]:
    var result: Array[UInt8, 32] = [
        15,
        96,
        93,
        27,
        146,
        148,
        195,
        111,
        125,
        23,
        196,
        140,
        148,
        61,
        162,
        184,
        119,
        205,
        169,
        96,
        186,
        94,
        51,
        55,
        231,
        178,
        226,
        155,
        206,
        96,
        61,
        24,
    ]
    return result^


# Deliver bounded completed proof decisions only on I/O, resolving live stream ownership afresh after cancellation/reuse.
def offload_tick(mut peer: Peer):
    offload.tick(peer.pool)
    # At most four completed owners exist; a worker cannot grow an unbounded I/O completion drain.
    for _ in range(4):
        var polled = offload.collect(peer.pool)
        if not polled:
            # Pending has neither a readable generation nor a default successful verdict.
            break
        var result = polled.value().copy()
        var found = -1
        for i in range(len(peer.streams)):
            if peer.streams[i].handle and peer.streams[i].job.value == result.id.value:
                # A new stream reusing the same slot/native address has a different job generation.
                found = i
                break
        if found < 0:
            # A completion cannot authorize a reply after its original application owner has retired.
            print("OFFLOAD_STALE", result.id.value)
            continue
        var handle = peer.streams[found].handle.value()
        if not result.verified:
            print("OFFLOAD_REJECT Proof")
            finish(peer.progress, peer.streams[found], False)
            external_call["rq_stream_abort", NoneType](handle)
            continue
        # Only a verified full expected RingVRF output authorizes this controlled preimage reply.
        peer.streams[found].sending = List[UInt8](length=7, fill=0)
        peer.streams[found].sending[0] = 3
        for i in range(3):
            # The CE fixture remains native-language policy, never a Rust codec or scheduler transform.
            peer.streams[found].sending[4 + i] = UInt8(i + 1)
        peer.streams[found].send_length = 7
        external_call["rq_stream_want_write", NoneType](handle, c_int(1))
        print("OFFLOAD_VERIFIED", result.id.value)


# Independent one-MiB fixture key, verified by the shared controller rather than calculated from duplicated bytes.
def large_hash() -> Array[UInt8, 32]:
    var result: Array[UInt8, 32] = [
        138,
        90,
        122,
        157,
        195,
        207,
        32,
        62,
        211,
        116,
        176,
        161,
        238,
        169,
        48,
        96,
        26,
        210,
        172,
        191,
        226,
        180,
        188,
        98,
        207,
        131,
        222,
        78,
        229,
        54,
        82,
        139,
    ]
    return result^


# Stream-local deadlines, paused-reader resumption and cancellation run on the same native I/O thread.
def soak_tick(mut peer: Peer):
    # Final native close may recycle a slot; every iteration resolves its current owner afresh.
    for i in range(len(peer.streams)):
        if not peer.streams[i].handle or peer.streams[i].counted:
            # Retired/settled streams have no pending application timer work.
            continue
        var handle = peer.streams[i].handle.value()
        var elapsed = now_ms() - peer.streams[i].started
        if peer.progress.server:
            var timeout = 500
            if peer.progress.overload:
                # Explicit load holders outlive ordinary stream-local deadline experiments.
                timeout = 30000
            if not peer.streams[i].read_fin and elapsed > timeout:
                # Exact request bytes without FIN cannot retain their application handler indefinitely.
                print("REQUEST_TIMEOUT")
                finish(peer.progress, peer.streams[i], False)
                external_call["rq_stream_abort", NoneType](handle)
            elif (
                peer.streams[i].send_length > 65536
                and peer.streams[i].send_offset < peer.streams[i].send_length
                and not peer.streams[i].blocked
                and elapsed > 100
            ):
                # Observe a real partially unsent large buffer behind exhausted transport receive credit.
                peer.streams[i].blocked = True
                print("BACKPRESSURE")
        elif peer.streams[i].attack == "cancel":
            var delay = 150
            if peer.progress.integrated:
                # Allow real owned snapshot capture and parked native writes before cancellation.
                delay = 500
            if peer.progress.mixed:
                # Retained-service tests overlap other peers during the parked large response.
                delay = 700
            if elapsed > delay:
                peer.streams[i].counted = True
                peer.progress.completed += 1
                peer.progress.cancelled += 1
                print("CANCEL_OK")
                external_call["rq_stream_abort", NoneType](handle)
        elif peer.streams[i].attack == "slow" and peer.streams[i].paused:
            var delay = 350
            if peer.progress.mixed:
                # The controller must observe independent healthy work before this reader resumes.
                delay = 1000
            if elapsed > delay:
                peer.streams[i].paused = False
                external_call["rq_stream_want_read", NoneType](handle, c_int(1))


# Wait without a live native endpoint while the external controller observes fully retired process resources.
def gate_wait(path: String) raises:
    var started = now_ms()
    var item = PollFd(c_int(-1), 0, 0)
    # Missing/dead controllers cannot leave an idle SDK process parked forever.
    while not exists(path):
        if now_ms() - started > 15000:
            raise Error("soak gate timeout")
        _ = external_call["rqm_poll", c_int](Pointer(to=item), c_size_t(0), c_int(10))


# Open, drive and retire one bounded authenticated endpoint using the identical existing proof CLI.
def run_peer(args: List[String]) raises -> Bool:
    # Role, port, identity files, ALPN and deadline have explicit trusted utility arity.
    if len(args) != 8 and len(args) != 9:
        raise Error("peer arguments")
    var server = args[1] == "server"
    var port = capacity(args[2], 65535)
    var timeout = capacity(args[7], 300000)
    # Trusted utility controls have the same explicit nonzero role/port/deadline contract as the other peers.
    if args[1] not in ("server", "client") or port == 0 or timeout == 0:
        return False
    var expected = List[UInt8]()
    if args[5] != "-":
        # Native file reads retain exact expected public bytes, without importing Python.
        with open(args[5], "r") as file:
            expected = file.read_bytes()
    # Every dialer pins one exact public identity; listeners alone may discover a consistent unknown peer.
    if len(expected) not in (0, 32) or (not server and len(expected) != 32):
        return False
    var attack = String("valid")
    if len(args) == 9:
        # Explicit malformed controls affect application bytes only after authentication.
        attack = args[8].copy()
    var mode = attack.copy()
    var service = server and mode in ("service", "overload", "integration", "offload")
    var integrated = mode in ("integration", "integrated")
    var offloading = mode == "offload"
    if offloading and not offload.ENABLED:
        # Ordinary binaries never claim an unlinked Rust worker path or run proof verification on I/O instead.
        return False
    # Ordinary QUIC binaries cannot claim an unlinked codec/crypto integration path.
    if integrated and not INTEGRATION_ENABLED:
        return False
    var overload = mode == "overload"
    var ipv6 = mode in (
        "overload",
        "holder",
        "idle",
        "probe",
        "offload",
        "proof",
        "light",
        "invalid-proof",
        "proof-cancel",
    )
    var mixed = mode == "mixed"
    var target = 8
    # Clean/probe modes contain normal requests; idle deliberately opens none after authentication.
    if mode in ("probe", "proof", "light", "invalid-proof", "proof-cancel"):
        target = 1
    if mode in ("clean", "probe", "idle", "offload", "proof", "light", "invalid-proof"):
        attack = "valid"
    elif mode == "holder":
        # Saturation holders send complete prefixes while deliberately withholding request FIN.
        attack = "no-fin"
    elif mode in ("soak", "mixed", "service", "overload", "integration", "integrated"):
        # These bounded test profiles share the same exact healthy/adversarial stream corpus.
        attack = "soak"
    var peer = Peer(
        Transport(None, -1, False, False, Array[UInt8, 2048](fill=0), ipv6),
        expected^,
        Progress(
            server,
            False,
            False,
            0,
            0,
            attack^,
            0,
            0,
            0,
            mixed,
            service,
            target,
            ipv6,
            False,
            overload,
            0,
            0,
            integrated,
            offloading,
            mode == "light",
            mode == "invalid-proof",
        ),
        List[StreamState](length=64, fill=empty_stream()),
        IntegrationBank(List[List[UInt8]](), List[PreimageKey]()),
        offload.empty_pool(),
    )
    comptime if INTEGRATION_ENABLED:
        if integrated:
            # Trusted public bank ownership is established before any native callback can perform a lookup.
            peer.bank = load_bank(getenv("RAGNAROK_INTEGRATION_FIXTURES"))
    comptime if offload.ENABLED:
        if offloading and not offload.start_pool(peer.pool):
            # Two worker-owned Rust setups must be ready before TLS/listener advertisement or application admission.
            return False
    var bound: UInt16 = 0
    var bind_port: UInt16 = 0
    if server:
        # Clients bind ephemeral local ports before dialing the requested server port.
        bind_port = UInt16(port)
    if ipv6:
        # IPv6 load/recovery modes bind the same retained loopback family as the existing adapters.
        peer.transport.fd = external_call["rqm_udp_open6", c_int](bind_port, Pointer(to=bound))
    else:
        # Keep the original IPv4 proof and sustained-service workloads byte-for-byte compatible.
        peer.transport.fd = external_call["rqm_udp_open", c_int](bind_port, Pointer(to=bound))
    if peer.transport.fd < 0:
        comptime if offload.ENABLED:
            if offloading:
                # Failed socket creation still joins already-created fixed workers before retiring their stable owner.
                offload.stop_pool(peer.pool)
        # Failed socket creation owns no descriptor or native engine to release.
        return False
    try:
        var cert = args[3].copy()
        var key = args[4].copy()
        var alpn = args[6].copy()
        # Separate native string owners supply NUL-terminated views only during the synchronous engine constructor.
        var c = cert.as_c_string_span()
        var k = key.as_c_string_span()
        var a = alpn.as_c_string_span()
        var user = Pointer(to=peer).unsafe_bitcast[NoneType]().as_unsafe_any_origin()
        var profile = 0
        # Existing pinned transport profiles configure real flow-control windows and multi-peer admission.
        if service:
            profile = 2
        elif peer.progress.attack == "soak":
            profile = 1
        if ipv6:
            var ipv6_profile = 4
            if overload or offloading:
                # Only the listener uses the pinned sixteen-connection saturation profile.
                ipv6_profile = 5
            peer.transport.engine = external_call[
                "rq_transport_new_ipv6_profile", Optional[NativePointer]
            ](
                c_int(ipv6_profile),
                c_int(server),
                bound,
                c.ptr().as_unsafe_any_origin(),
                k.ptr().as_unsafe_any_origin(),
                a.ptr().as_unsafe_any_origin(),
                user,
                verify_peer,
                send_packet,
                on_stream,
            )
        else:
            peer.transport.engine = external_call["rq_transport_new", Optional[NativePointer]](
                c_int(profile),
                c_int(server),
                bound,
                c.ptr().as_unsafe_any_origin(),
                k.ptr().as_unsafe_any_origin(),
                a.ptr().as_unsafe_any_origin(),
                user,
                verify_peer,
                send_packet,
                on_stream,
            )
        # TLS/native construction failure still retires the already-bound UDP owner.
        if not peer.transport.engine:
            return False
        if server:
            # Readiness is announced only after binding and complete native engine setup.
            print("READY")
            _ = external_call["rqm_flush", c_int]()
        elif external_call["rq_connect", c_int](peer.transport.engine, UInt16(port)) == 0:
            # Failed dialing does not count as authenticated application work.
            return False
        var started = now_ms()
        var authenticated = False
        var opened = False
        var stop = getenv("RAGNAROK_SERVICE_STOP")
        var cancel_file = getenv("RAGNAROK_OFFLOAD_CANCEL")
        # A retained service has a concrete external shutdown gate before entering its bounded loop.
        if service and stop == "":
            return False
        var service_stopped = False
        var last_active = -1
        var last_idle: UInt64 = 0
        var last_load: Array[UInt64, 5] = [
            UInt64.MAX,
            UInt64.MAX,
            UInt64.MAX,
            UInt64.MAX,
            UInt64.MAX,
        ]
        # One bounded readiness loop owns every stream, transport timer and callback lifetime.
        while (
            not peer.progress.failed
            and (service or peer.progress.completed < target)
            and now_ms() - started < timeout
        ):
            comptime if offload.ENABLED:
                if offloading:
                    # Workers publish copied verdicts; only this I/O thread resolves stream generations and queues replies.
                    offload_tick(peer)
            # Native transport timers and application stream deadlines share this same I/O dispatcher.
            if peer.progress.attack == "soak":
                soak_tick(peer)
            if service:
                # Retain one listener engine/socket across every independent client reconnect wave.
                var active = external_call["rq_peer_metric", UInt64](
                    peer.transport.engine, c_int(0)
                )
                if Int(active) != last_active:
                    print("PEERS", active)
                    last_active = Int(active)
                var live = 0
                for i in range(len(peer.streams)):
                    if peer.streams[i].handle:
                        # Only final native close releases a live application slot.
                        live += 1
                if overload:
                    var current: Array[UInt64, 5] = [
                        active,
                        UInt64(live),
                        external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(5)),
                        UInt64(peer.progress.capacity_rejected),
                        UInt64(peer.progress.peak_streams),
                    ]
                    var changed = False
                    # Emit only actual admission/retirement state changes, keeping diagnostics bounded under load.
                    for i in range(5):
                        if current[i] != last_load[i]:
                            changed = True
                    if changed:
                        print(
                            "LOAD_STATE", current[0], current[1], current[2], current[3], current[4]
                        )
                        last_load = current^
                var accepted = external_call["rq_peer_metric", UInt64](
                    peer.transport.engine, c_int(1)
                )
                if active == 0 and live == 0 and accepted > last_idle:
                    # Observe actual live process malloc storage after every connection/stream owner has retired.
                    print(
                        "SERVICE_IDLE",
                        accepted,
                        external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(2)),
                        external_call["rqm_heap_used", UInt64](),
                    )
                    last_idle = accepted
                if exists(stop):
                    # Normal service shutdown requires every promoted connection and application owner to retire.
                    service_stopped = offloading or (active == 0 and live == 0)
                    if offloading:
                        # Explicit pending shutdown proves job cancellation and joined worker retirement.
                        print("OFFLOAD_SHUTDOWN_PENDING", live)
                    break
            var status = external_call["rq_status", c_int](peer.transport.engine)
            # A one-shot dial cannot complete after admission refusal or peer loss before its first stream opens.
            if (
                not server
                and external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(2)) > 0
                and external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(0)) == 0
            ):
                print("CONNECTION_CLOSED")
                break
            if status < 0:
                # Rejected authentication/native I/O settles the attempt without creating application streams.
                break
            elif status == 1 and not authenticated:
                # Authentication is recorded separately from verified CE request/reply completion.
                authenticated = True
                print("AUTH_OK")
                _ = external_call["rqm_flush", c_int]()
            if authenticated and not server and not opened and mode != "idle":
                # Open all eight requests before waiting for any response, proving concurrent stream handling.
                opened = True
                var count = target
                # Later healthy siblings prove service after cancellation and missing-FIN expiry.
                if peer.progress.attack == "soak" and not integrated:
                    count = 5
                for _ in range(count):
                    external_call["rq_open_stream", NoneType](peer.transport.engine)
            if (
                not server
                and peer.progress.attack == "soak"
                and opened
                and peer.progress.opened == 5
                and not integrated
            ):
                var delay = 650
                if mixed:
                    # Longer holds let the controller overlap independent healthy peers with parked writers.
                    delay = 1200
                if now_ms() - started > delay:
                    for _ in range(3):
                        # All later siblings use exact ordinary healthy request framing.
                        external_call["rq_open_stream", NoneType](peer.transport.engine)
            if mode == "proof-cancel" and exists(cancel_file):
                for i in range(len(peer.streams)):
                    if peer.streams[i].handle:
                        # The controller releases cancellation only after observing actual worker execution.
                        external_call["rq_stream_abort", NoneType](peer.streams[i].handle.value())
                external_call["rq_disconnect", NoneType](peer.transport.engine)
                var grace = now_ms()
                while now_ms() - grace < 100:
                    # Deliver reset/close while UDP and callback owners still retain their buffers.
                    _ = poll_transport(peer.transport)
                return False
            _ = external_call["rqm_flush", c_int]()
            if not poll_transport(peer.transport):
                # Failed OS readiness or packet I/O cannot become a passing exchange.
                break
        # A final receive may both finish and retire a connection; preserve historical handshake evidence.
        if (
            not authenticated
            and external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(4)) > 0
        ):
            authenticated = True
            print("AUTH_OK")
        if service:
            # Report counters before native engine retirement while the same listener lifetime is still observable.
            print(
                "SERVICE_DONE",
                external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(1)),
                external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(2)),
                external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(3)),
            )
            return (
                service_stopped
                and not peer.progress.failed
                and (
                    offloading
                    or external_call["rq_peer_metric", UInt64](peer.transport.engine, c_int(3)) >= 3
                )
            )
        var good = authenticated and not peer.progress.failed and peer.progress.completed == target
        if good and peer.progress.attack == "soak" and not server:
            # Exactly five healthy, two rejected and one cancelled stream are required, not just eight settled slots.
            var healthy = 5
            var rejected = 2
            if integrated:
                # Three valid digests, four composed rejections and one cancelled large owner are required.
                healthy = 3
                rejected = 4
            good = (
                peer.progress.healthy == healthy
                and peer.progress.rejected == rejected
                and peer.progress.cancelled == 1
            )
        if good:
            # Only exact completed application outcomes produce the shared success marker.
            print("EXCHANGE_OK", target)
            if mode in ("mixed", "clean", "probe", "integrated", "proof", "light"):
                # Retained listeners need an explicit close packet while UDP and callbacks remain live.
                external_call["rq_disconnect", NoneType](peer.transport.engine)
            var grace = now_ms()
            while now_ms() - grace < 100:
                # Drain final FIN/handshake packets while the socket and callback owner remain live.
                if not poll_transport(peer.transport):
                    return False
        return good
    finally:
        # Socket retirement precedes native destruction; final stream callbacks still borrow this stable Peer.
        peer.progress.stopping = True
        close_transport(peer.transport)
        comptime if offload.ENABLED:
            if offloading:
                # Transport close cancels stream generations first; then every running Rust borrow joins before pool retirement.
                offload.stop_pool(peer.pool)


# Exercise the exact production DER/framing functions without creating a TLS engine or network endpoint.
def parser_selftest() raises:
    var peer = Progress(
        False,
        False,
        False,
        0,
        0,
        String(),
        0,
        0,
        0,
        False,
        False,
        8,
        False,
        False,
        False,
        0,
        0,
        False,
        False,
        False,
        False,
    )
    # Exact request/reply prefixes distinguish pending input from premature FIN and complete messages.
    for role in range(2):
        var wire = List[UInt8](length=37 if role == 1 else 7, fill=0)
        if role == 1:
            wire[0] = 143
            wire[1] = 32
            var hash = request_hash()
            for i in range(32):
                wire[5 + i] = hash[i]
        else:
            wire[0] = 3
            for i in range(3):
                wire[4 + i] = UInt8(i + 1)
        for length in range(len(wire) + 1):
            var state = empty_stream()
            state.responder = role == 1
            state.received = wire.copy()
            state.received_length = length
            var extent = frame_extent(peer, state)
            if extent[0] or not extent[1]:
                raise Error("open frame prefix")
            state.read_fin = True
            extent = frame_extent(peer, state)
            if extent[0] != (length == len(wire)) or extent[1] != (length == len(wire)):
                raise Error("FIN frame prefix")
    var seed: UInt64 = 0x51554943
    var bytes = Array[UInt8, 128](fill=0)
    var expected = List[UInt8]()
    # Reproducible xorshift input is parser coverage, never cryptographic randomness.
    for iteration in range(10000):
        for i in range(128):
            seed ^= seed << UInt64(13)
            seed ^= seed >> UInt64(7)
            seed ^= seed << UInt64(17)
            bytes[i] = UInt8(seed & 255)
        var length = iteration % 129
        _ = valid_peer(bytes.unsafe_ptr().as_imm(), c_size_t(length), Span(expected))
        var state = empty_stream()
        state.responder = iteration % 2 == 0
        state.read_fin = iteration % 3 == 0
        state.received_length = length
        for i in range(length):
            state.received.append(bytes[i])
        var extent = frame_extent(peer, state)
        if extent[0] and (
            not extent[1] or not state.read_fin or length != (37 if state.responder else 7)
        ):
            raise Error("complete frame invariant")
        if state.read_fin and length < (5 if state.responder else 4) and extent[1]:
            raise Error("partial header FIN")
    print("Mojo QUIC selftest: 10000 malformed DER/frame cases passed")
