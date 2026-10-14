// Isolated JAMNP-S authentication proof using a single core:nbio loop and pinned LSQUIC/TLS.
package main
import codec "../codec"
import "base:runtime"
import "core:fmt"
import "core:mem"
import "core:nbio"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

// Primitive owned X.509 observations, ABI-matched to the small reviewed C extractor.
Cert_Fields :: struct {
	ed_key, ed_signature, san_extensions, san_count, san_dns: i32,
	key_length, san_length:                                   uintptr,
	key:                                                      [32]u8,
	san:                                                      [256]u8,
}
// One bounded CE stream owns its framing buffers through read/write/close callbacks.
Stream_State :: struct {
	handle:                                  rawptr,
	received:                                []u8,
	received_length:                         int,
	sending:                                 []u8,
	send_length, send_offset:                int,
	read_fin, write_fin, counted, responder: bool,
	started:                                 time.Time,
	attack:                                  string,
	paused, blocked:                         bool,
	owner:                                   codec.Owned_Frame, // One release owner retained through final native stream close.
	query:                                   Preimage_Key,
	fixture:                                 int,
}
// Native owner outlives every receive/timer/C callback; buffers never refer to expired stack frames.
Peer :: struct {
	transport:                                                              rawptr,
	socket:                                                                 net.UDP_Socket,
	expected:                                                               []u8,
	buffer:                                                                 [2048]u8,
	stopping:                                                               bool,
	saved_context:                                                          runtime.Context,
	server, failed, service, mixed, integrated, mesh, recovering, overload: bool,
	streams:                                                                [64]Stream_State,
	completed:                                                              int,
	capacity_rejected, peak_streams:                                        int,
	attack:                                                                 string,
	opened, healthy, rejected, cancelled, blocked:                          int,
	bank:                                                                   Integration_Bank,
	tracking:                                                               ^mem.Tracking_Allocator, // Borrowed from the service entry point through all callbacks.
	receive_operation:                                                      ^nbio.Operation, // Owned until callback delivery or explicit removal; buffer stays in Peer.
}
// Explicit library build path supplied by the reproducible proof runner.
when ODIN_OS == .Darwin {
	foreign import quic "../../build/quic/libquic_proof.dylib"
} else {
	foreign import quic "../../build/quic/libquic_proof.so"
}
// Opaque C API wraps transport/TLS layouts, leaving all JAM identity and I/O policy in Odin.
foreign quic {
	// Retained IPv6 loopback engines and live stream-initiator observation contain no JAM policy.
	// Proof profiles keep crash expiry/load admission explicit, without changing normal peer settings.
	rq_transport_new_ipv6_profile :: proc "c" (profile, server: i32, port: u16, cert, key, alpn: cstring, user: rawptr, verify: proc "c" (_: rawptr, _: [^]u8, _: uintptr) -> i32, send: proc "c" (_: rawptr, _: [^]u8, _: uintptr, _: u16) -> i32, stream: proc "c" (_: rawptr, _: rawptr, _: i32)) -> rawptr ---
	rq_transport_new_ipv6 :: proc "c" (server: i32, port: u16, cert, key, alpn: cstring, user: rawptr, verify: proc "c" (_: rawptr, _: [^]u8, _: uintptr) -> i32, send: proc "c" (_: rawptr, _: [^]u8, _: uintptr, _: u16) -> i32, stream: proc "c" (_: rawptr, _: rawptr, _: i32)) -> rawptr ---
	// Validated EOF requires an explicit application read-half release before native stream close.
	rq_stream_read_done :: proc "c" (_: rawptr) ---
	rq_stream_local :: proc "c" (_: rawptr, _: rawptr) -> i32 ---
	rq_parse_cert :: proc "c" (der: [^]u8, length: uintptr, fields: ^Cert_Fields) -> i32 ---
	rq_transport_new :: proc "c" (soak, server: i32, port: u16, cert, key, alpn: cstring, user: rawptr, verify: proc "c" (_: rawptr, _: [^]u8, _: uintptr) -> i32, send: proc "c" (_: rawptr, _: [^]u8, _: uintptr, _: u16) -> i32, stream: proc "c" (_: rawptr, _: rawptr, _: i32)) -> rawptr ---
	// Graceful close runs before receive/socket retirement; metric queries expose no borrowed connection handles.
	rq_disconnect :: proc "c" (_: rawptr) ---
	rq_peer_metric :: proc "c" (_: rawptr, _: i32) -> u64 ---
	rq_connect :: proc "c" (_: rawptr, _: u16) -> i32 ---
	rq_packet_in :: proc "c" (_: rawptr, _: [^]u8, _: uintptr, _: u16) -> i32 ---
	rq_process :: proc "c" (_: rawptr) ---
	rq_next_tick :: proc "c" (_: rawptr) -> i64 ---
	rq_status :: proc "c" (_: rawptr) -> i32 ---
	rq_open_stream :: proc "c" (_: rawptr) ---
	rq_stream_read :: proc "c" (_: rawptr, _: [^]u8, _: uintptr) -> i64 ---
	rq_stream_write :: proc "c" (_: rawptr, _: [^]u8, _: uintptr) -> i64 ---
	rq_stream_want_read :: proc "c" (_: rawptr, _: i32) ---
	rq_stream_want_write :: proc "c" (_: rawptr, _: i32) ---
	// Compare only live stream ownership synchronously; no native connection pointer is retained.
	rq_stream_same_peer :: proc "c" (_: rawptr, _: rawptr) -> i32 ---
	rq_stream_flush :: proc "c" (_: rawptr) -> i32 ---
	rq_stream_fin :: proc "c" (_: rawptr) ---
	rq_stream_abort :: proc "c" (_: rawptr) ---
	rq_transport_free :: proc "c" (_: rawptr) ---
}

// Evaluate the exact pinned least-significant-first formula; it is not standard RFC base32.
peer_name :: proc(key: [32]u8) -> [54]u8 {
	alphabet := "$abcdefghijklmnopqrstuvwxyz234567"
	name: [54]u8
	name[0] = '$'; name[1] = 'e'
	// The final 52nd group zero-extends the key beyond 256 bits.
	for group in 0 ..< 52 {
		index: int
		for bit in 0 ..< 5 {
			position := group * 5 + bit
			if position <
			   256 { index |= int((key[position / 8] >> uint(position % 8)) & 1) << uint(bit) } 	// Zero-extended high bits.
		}
		name[2 + group] = alphabet[index]
	}
	return name
}

// Validate certificate/key/SAN and optional exact peer identity in Odin during the TLS verification callback.
verify_peer :: proc "c" (user: rawptr, der: [^]u8, length: uintptr) -> i32 {
	peer := (^Peer)(user)
	context = peer.saved_context
	fields: Cert_Fields
	// Parse bounded complete DER before inspecting primitive observations.
	if rq_parse_cert(der, length, &fields) != 1 { return 0 }
	if fields.ed_key != 1 ||
	   fields.ed_signature != 1 ||
	   fields.key_length != 32 ||
	   fields.san_extensions != 1 ||
	   fields.san_count != 1 ||
	   fields.san_dns != 1 { return 0 } 	// Exact algorithm/name cardinality.
	name := peer_name(fields.key)
	if fields.san_length != uintptr(len(name)) { return 0 } 	// Never accept a NUL-truncated name prefix.
	// Compare every supplied SAN byte with its key-derived name.
	for b, i in name { if fields.san[i] != b { return 0 } } 	// Altered SAN is a different identity.
	// Client key pins and optional server fixture pins are checked independently of SAN consistency.
	if len(peer.expected) > 0 {
		if len(peer.expected) != 32 { return 0 } 	// No narrowing of malformed identity fixtures.
		for b, i in fields.key { if peer.expected[i] != b { return 0 } } 	// Exact expected key.
	}
	return 1
}

// Nonblocking UDP sends finish before returning, so borrowed C packet storage never escapes this callback.
send_packet :: proc "c" (user: rawptr, bytes: [^]u8, length: uintptr, port: u16) -> i32 {
	peer := (^Peer)(user)
	context = peer.saved_context
	destination := net.Endpoint{net.IP4_Loopback, int(port)}
	// The mesh sockets and C transport addresses must agree on IPv6, without mapped IPv4 endpoints.
	if peer.mesh { destination = {net.IP6_Loopback, int(port)} }
	written, err := net.send_udp(peer.socket, bytes[:int(length)], destination)
	// Would-block/error leaves the datagram with LSQUIC for a later retry.
	if err != nil || written != int(length) { return 0 }
	return 1
}

// Fixture preimage map key uses GP Blake2b-256; no unfinished state/database code is required.
REQUEST_HASH :: [32]u8 {
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
}

// Bounded soak fixture and independently computed Blake2b-256 map key.
LARGE_SIZE :: 1024 * 1024
LARGE_HASH :: [32]u8 {
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
}

// Retire one terminal stream exactly once; malformed input stays local in the soak.
finish_stream :: proc(peer: ^Peer, state: ^Stream_State, good: bool) {
	if state.counted { return } 	// Close/reset callbacks may repeat terminal observations.
	state.counted = true
	if good {
		peer.completed += 1
		peer.healthy += 1
		// Observe progress while another stream's large application write is actually parked.
		if peer.service {
			for other in peer.streams {
				if other.handle != nil &&
				   other.blocked &&
				   !other.counted &&
				   rq_stream_same_peer(state.handle, other.handle) ==
					   0 { fmt.println("ISOLATED_HEALTHY"); break } 	// One marker suffices for this healthy outcome.
			}
		}
		if peer.attack ==
		   "soak" { fmt.println("SERVER_HEALTHY" if peer.server else "HEALTHY_OK") } 	// Expose verified client replies.
	} else if peer.mesh && peer.recovering {
		peer.completed += 1; peer.rejected += 1 // Known peer loss settles work; final close still owns buffer release.
	} else if peer.attack == "soak" {
		peer.completed += 1
		peer.rejected += 1
		fmt.println("STREAM_REJECTED" if peer.server else "EXPECTED_REJECT") // A failed request must not fail the transport owner.
	} else {
		peer.failed = true // Preserve the original single-attempt rejection behaviour.
	}
}

// A CE stream's requester is independent of the connection dialer; legacy workloads keep their role policy.
accepting :: proc(peer: ^Peer, stream: ^Stream_State) -> bool {
	return stream.responder if peer.mesh else peer.server
}

// Check an incremental E4 frame before accepting its payload; no untrusted length chooses an allocation.
frame_extent :: proc(peer: ^Peer, stream: ^Stream_State) -> (complete: bool, valid: bool) {
	start := 1 if accepting(peer, stream) else 0
	// The initiator's first byte selects the explicit CE protocol.
	if accepting(peer, stream) &&
	   stream.received_length >= 1 &&
	   stream.received[0] != 143 { return false, false }
	if stream.received_length < start + 4 { return false, !stream.read_fin } 	// Partial length waits for more bytes.
	claimed: u64
	for i in 0 ..< 4 { claimed |= u64(stream.received[start + i]) << uint(8 * i) } 	// E4 network frame header.
	maximum :=
		u64(32) if accepting(peer, stream) else u64(INTEGRATION_WIRE_CAP if peer.integrated else (LARGE_SIZE if peer.attack == "soak" else 1024))
	if claimed > maximum { return false, false } 	// Reject before allocation or indexing.
	extent := start + 4 + int(claimed)
	if stream.received_length > extent { return false, false } 	// Exactly one message is allowed in this direction.
	if !stream.read_fin { return false, true } 	// CE success requires FIN, not only enough payload bytes.
	if stream.received_length != extent { return false, false } 	// Premature FIN is truncation.
	// Integrated fixtures are full work digests; CE itself still transports opaque preimage bytes.
	if peer.integrated {
		if accepting(peer, stream) {
			if claimed != 32 { return false, false } 	// Query width stays normative.
			index := find_fixture(&peer.bank, stream.received[5:37])
			if index < 0 { fmt.println("INTEGRATION_REJECT Lookup"); return false, false } 	// No default record after a miss.
			stream.fixture = index
			scratch := make([]u8, len(peer.bank.wires[index]))
			defer delete(scratch)
			copy(scratch, peer.bank.wires[index])
			checked := capture_digest(scratch, peer.bank.keys[index])
			switch value in checked {
			case Integration_Error:
				fmt.println("INTEGRATION_REJECT", value); return false, false // Failed capture retains no resources.
			case Verified_Digest:
				stream.owner = value.owner // Transfer exactly one snapshot release owner to the stream.
				defer delete(value.wire)
				stream.sending = make([]u8, len(value.wire) + 4)
				for i in 0 ..< 4 { stream.sending[i] = u8((len(value.wire) >> uint(8 * i)) & 255) } 	// Native E4 header.
				copy(stream.sending[4:], value.wire)
				if index == 5 { stream.sending[8] ~= 1 } 	// Test-only wrong-hash response remains codec-valid.
				stream.send_length = len(stream.sending)
			}
		} else {
			checked := capture_digest(stream.received[4:extent], stream.query)
			switch value in checked {
			case Integration_Error:
				fmt.println("INTEGRATION_REJECT", value); return false, false // Hash/codec failure is stream-local.
			case Verified_Digest:
				stream.owner = value.owner; delete(value.wire) // The snapshot survives receive-buffer reuse until final close.
			}
		}
		fmt.println("OWNED_VERIFIED")
		return true, true
	}
	if accepting(peer, stream) {
		if claimed != 32 { return false, false } 	// Hash is fixed width.
		wanted :=
			LARGE_HASH if stream.received[5] == LARGE_HASH[0] && peer.attack == "soak" else REQUEST_HASH
		for b, i in wanted { if stream.received[5 + i] != b { return false, false } } 	// Fixture map lookup.
	} else {
		size := LARGE_SIZE if stream.attack == "slow" else 3
		if claimed != u64(size) { return false, false } 	// Fixed fixture ceiling and exact length.
		for i in 0 ..< size {
			wanted := u8(i % 251) if size == LARGE_SIZE else u8(i + 1)
			if stream.received[4 + i] != wanted { return false, false } 	// Validate every preimage byte.
		} // Compare actual bytes.
	}
	return true, true
}

// Stream callback retains bounded owned buffers until native close; soak failures are isolated per stream.
on_stream :: proc "c" (user: rawptr, handle: rawptr, event: i32) {
	peer := (^Peer)(user)
	context = peer.saved_context
	state: ^Stream_State
	// Resolve only the live handle owned by this endpoint.
	for &slot in peer.streams { if slot.handle == handle { state = &slot; break } }
	if event == 0 {
		// A fixed slot ceiling bounds all application allocations, including malformed concurrent requests.
		for &slot in peer.streams { if slot.handle == nil { state = &slot; break } }
		if state == nil {
			if !peer.service { peer.failed = true } else { peer.capacity_rejected += 1 } 	// Reject only the new service stream.
			rq_stream_abort(handle); return
		} // Capacity rejects only new service work. 	// No unbounded queue.
		state^ = Stream_State {
			handle  = handle,
			started = time.now(),
			attack  = peer.attack,
		}
		// IETF stream IDs distinguish local requests from remote queries on either role engine.
		if peer.mesh { state.responder = rq_stream_local(peer.transport, handle) == 0 }
		state.received = make(
			[]u8,
			1050 if accepting(peer, state) else (INTEGRATION_WIRE_CAP + 5 if peer.integrated else (1050 if peer.attack != "soak" else LARGE_SIZE + 5)),
		)
		if !accepting(peer, state) {
			state.sending = make([]u8, 64)
			state.sending[0] = 143; state.sending[1] = 32
			// Select the exact integration key before any read/write callback starts.
			if peer.integrated {
				index := peer.opened
				if index >= 8 { peer.failed = true; rq_stream_abort(handle); return } 	// Bound trusted workload indexing.
				peer.opened += 1
				state.fixture = index
				state.query = peer.bank.keys[index]
				state.attack = "cancel" if index == 6 else "valid"
				for value, i in state.query { state.sending[5 + i] = value } 	// Exact public preimage query.
				if index == 4 { state.sending[5] ~= 1 } 	// Missing-key fixture request.
				state.send_length = 37
				if index == 6 { state.paused = true; rq_stream_want_read(handle, 0) } 	// Cancel a retained snapshot behind transport backpressure.
				rq_stream_want_write(handle, 1)
				return
			}
			wanted := REQUEST_HASH
			// The soak mixes five healthy replies with cancellation, malformed kind and missing FIN.
			if peer.attack == "soak" {
				switch peer.opened {
				case 1:
					state.attack = "slow"; wanted = LARGE_HASH
				case 2:
					state.attack = "cancel"; wanted = LARGE_HASH
				case 3:
					state.attack = "bad-kind"
				case 4:
					state.attack = "no-fin"
				case:
					state.attack = "valid" // All remaining streams must complete normally.
				}
				peer.opened += 1
			}
			// Request framing remains kind + E4 + exact Blake2b fixture key.
			for b, i in wanted { state.sending[5 + i] = b }
			state.send_length = 37
			switch state.attack {
			case "valid", "no-fin", "slow", "cancel": // Valid bytes with distinct lifecycle schedules.
			case "bad-kind":
				state.sending[0] = 144
			case "oversize":
				for i in 1 ..= 4 { state.sending[i] = 255 } 	// Untrusted extent must fail.
			case "unknown":
				state.sending[5] ~= 1
			case "truncated":
				state.send_length = 36
			case "trailing":
				state.send_length = 38
			case:
				peer.failed = true; rq_stream_abort(handle); return // Never guess a test selector.
			}
			// Slow/cancelled readers leave the transport window full while other streams progress.
			if state.attack == "slow" || state.attack == "cancel" {
				state.paused = true
				rq_stream_want_read(handle, 0)
			}
			rq_stream_want_write(handle, 1)
		}
		// Count actual native-language owners, rather than inferring usage from transport credit.
		if peer.overload {
			live := 0
			for slot in peer.streams { if slot.handle != nil { live += 1 } } 	// Final close releases a slot.
			peer.peak_streams = max(peer.peak_streams, live)
		}
		return
	}
	if state == nil {
		// Capacity-rejected service streams have no buffer owner; only their final close/reset may be ignored.
		if !peer.service ||
		   event != 3 &&
			   event != 4 { fmt.eprintln("unexpected stream event", event); peer.failed = true }
		return
	} // Never dereference stale native ownership.
	if event == 3 {
		if !state.counted && !peer.stopping { finish_stream(peer, state, false) } 	// Premature close is a rejection.
		if peer.integrated &&
		   accepting(peer, state) &&
		   state.fixture == 6 &&
		   state.owner != nil { fmt.println("OWNED_CANCEL_RELEASE") } 	// Prove cancellation reached an owned snapshot.
		codec.destroy_owned(&state.owner) // Final close, including cancellation, is the sole release owner.
		delete(state.received); delete(state.sending)
		state^ = {} // Slot reuse cannot retain old buffers or timers.
		return
	}
	if event == 4 {
		if !peer.stopping { finish_stream(peer, state, false) } 	// STOP_SENDING/reset settles pending writes too.
		rq_stream_abort(handle)
		return
	}
	if peer.stopping || state.counted && !accepting(peer, state) { return } 	// Final callbacks have no new application work.
	if event == 1 {
		if state.paused { return } 	// Application consumption resumes from the single event loop's deadline.
		// Partial and coalesced payloads stay in bounded storage until their exact FIN is checked.
		for {
			if state.received_length ==
			   len(
				   state.received,
			   ) { finish_stream(peer, state, false); rq_stream_abort(handle); return }
			got := rq_stream_read(
				handle,
				raw_data(state.received[state.received_length:]),
				uintptr(len(state.received) - state.received_length),
			)
			if got == -2 { break } 	// No readable transport bytes yet.
			if got < 0 { finish_stream(peer, state, false); rq_stream_abort(handle); return } 	// Reset settles this stream.
			if got == 0 { state.read_fin = true } else { state.received_length += int(got) } 	// FIN is not fabricated padding.
			complete, valid := frame_extent(peer, state)
			if !valid { finish_stream(peer, state, false); rq_stream_abort(handle); return } 	// Malformed request/reply.
			if complete {
				if peer.mesh { rq_stream_read_done(handle) } 	// Exact FIN has been checked before retiring reading.
				rq_stream_want_read(handle, 0)
				if accepting(peer, state) {
					if peer.integrated { rq_stream_want_write(handle, 1); break } 	// Reply was built from the owned digest, with its snapshot retained.
					size :=
						LARGE_SIZE if state.received[5] == LARGE_HASH[0] && peer.attack == "soak" else 3
					state.sending = make([]u8, size + 4)
					// Encode a trusted bounded E4 length and fixture bytes in native Odin.
					for i in 0 ..< 4 { state.sending[i] = u8((size >> uint(8 * i)) & 255) }
					for i in 0 ..< size { state.sending[4 + i] = u8(i % 251) if size == LARGE_SIZE else u8(i + 1) }
					state.send_length = len(state.sending)
					rq_stream_want_write(handle, 1)
				} else { finish_stream(peer, state, true) } 	// Exact response and FIN verified.
				break
			}
		}
	} else if event == 2 {
		// Preserve unsent bytes across partial writes and flow-control stalls.
		for state.send_offset < state.send_length {
			sent := rq_stream_write(
				handle,
				raw_data(state.sending[state.send_offset:state.send_length]),
				uintptr(state.send_length - state.send_offset),
			)
			if sent == -2 || sent == 0 { return } 	// Keep storage until credit resumes or native close.
			if sent < 0 { finish_stream(peer, state, false); rq_stream_abort(handle); return } 	// Failed write settles only its stream.
			state.send_offset += int(sent)
		}
		if rq_stream_flush(handle) !=
		   0 { finish_stream(peer, state, false); rq_stream_abort(handle); return } 	// Missing FIN still transmits its request bytes.
		rq_stream_want_write(handle, 0)
		if !state.write_fin && (accepting(peer, state) || state.attack != "no-fin") {
			rq_stream_fin(handle); state.write_fin = true
			if accepting(peer, state) { finish_stream(peer, state, true) } 	// Request and queued reply FIN complete server work.
		}
	}
}

// Deadline work shares the existing I/O loop, with no timer thread per stream.
soak_tick :: proc(peer: ^Peer) {
	// Check only live, unsettled streams; close callbacks may immediately recycle their slot.
	for &state in peer.streams {
		if state.handle == nil || state.counted { continue } 	// Retired stream owns no deadline work.
		elapsed := time.since(state.started)
		if peer.server {
			if !state.read_fin && elapsed > (30000 if peer.overload else 500) * time.Millisecond {
				fmt.println("REQUEST_TIMEOUT") // A complete hash without FIN cannot retain a handler.
				finish_stream(peer, &state, false); rq_stream_abort(state.handle) // Bound missing request FIN.
			} else if state.send_length > 65536 &&
			   state.send_offset < state.send_length &&
			   !state.blocked &&
			   elapsed > 100 * time.Millisecond {
				state.blocked = true; peer.blocked += 1; fmt.println("BACKPRESSURE") // Observe a genuinely pending large write.
			}
		} else if state.attack == "cancel" &&
		   elapsed >
			   (500 if peer.integrated else (700 if peer.mixed else 150)) * time.Millisecond {
			state.counted = true; peer.completed += 1; peer.cancelled += 1
			fmt.println("CANCEL_OK"); rq_stream_abort(state.handle) // Cancel with a server write still pending.
		} else if state.attack == "slow" &&
		   state.paused &&
		   elapsed > (1000 if peer.mixed else 350) * time.Millisecond {
			state.paused = false; rq_stream_want_read(state.handle, 1) // Resume consumption and transport credit.
		}
	}
}

// Process one owned receive buffer, then rearm only while the native owner remains active.
on_receive :: proc(op: ^nbio.Operation, peer: ^Peer) {
	peer.receive_operation = nil // This callback retires the old operation before another receive is armed.
	// Receives have no linked timeout; standalone timers already wake lifecycle and QUIC deadline checks.
	if op.recv.err != nil { peer.failed = true; return } 	// Surface an I/O failure through the bounded session result.
	// Mesh traffic must retain its full IPv6 loopback identity, rather than attributing arbitrary addresses by port.
	if peer.mesh {
		address, ok := op.recv.source.address.(net.IP6_Address)
		if !ok || address != net.IP6_Loopback {
			if !peer.stopping && !peer.failed { arm_receive(peer) } 	// Teardown must never rearm a borrowed receive buffer.
			return
		} // Ignore out-of-scope packets without stopping the listener.
	}
	// Only completed UDP bytes enter the transport.
	if op.recv.err == nil && op.recv.received > 0 {
		_ = rq_packet_in(
			peer.transport,
			raw_data(peer.buffer[:]),
			uintptr(op.recv.received),
			u16(op.recv.source.port),
		)
		rq_process(peer.transport)
	}
	// Stop before destruction and let pending callbacks drain with their buffers still alive.
	if !peer.stopping && !peer.failed { arm_receive(peer) }
}

// Keep one untimed receive owned by Peer; shutdown removes it before releasing its borrowed buffer.
arm_receive :: proc(peer: ^Peer) {
	peer.receive_operation = nbio.recv_poly(peer.socket, {peer.buffer[:]}, peer, on_receive)
}

// Schedule QUIC deadlines on the same I/O thread; each callback owns no borrowed TLS buffers.
on_timer :: proc(op: ^nbio.Operation, peer: ^Peer) {
	// Do not touch a transport after shutdown begins.
	if peer.stopping { return }
	rq_process(peer.transport)
	arm_timer(peer)
}

// Use LSQUIC's next deadline with a bounded idle wakeup, rather than one timer thread per connection.
arm_timer :: proc(peer: ^Peer) {
	delay := clamp(rq_next_tick(peer.transport), i64(1000), i64(10000))
	nbio.timeout_poly(time.Duration(delay) * time.Microsecond, peer, on_timer)
}

// Acquire the current thread's shared I/O loop, preserving the actual platform error for CI diagnostics.
acquire_loop :: proc() -> bool {
	err := nbio.acquire_thread_event_loop()
	if err != nil {
		fmt.eprintln("event-loop acquisition failed:", err)
		return false // Never hide a kernel/backend setup failure behind an assertion.
	}
	return true
}

// Run one bounded authentication attempt and drain I/O callbacks before releasing TLS/native contexts.
run_peer :: proc(tracking: ^mem.Tracking_Allocator = nil) -> bool {
	if len(os.args) != 8 &&
	   len(os.args) !=
		   9 { fmt.eprintln("mode port cert key expected-key alpn timeout-ms"); return false } 	// Trusted CLI shape.
	port, port_ok := strconv.parse_int(os.args[2])
	timeout, timeout_ok := strconv.parse_int(os.args[7])
	if !port_ok ||
	   port < 1 ||
	   port > 65535 ||
	   !timeout_ok ||
	   timeout < 1 ||
	   timeout > 120000 { return false } 	// Guard all narrowing.
	server := os.args[1] == "server"
	if !server && os.args[1] != "client" { return false } 	// No guessed role.
	expected: []u8
	if os.args[5] != "-" {
		data, err := os.read_entire_file(os.args[5], context.allocator)
		if err != nil || len(data) != 32 { return false } 	// Bounded fixture identity before transport setup.
		expected = data
	}
	defer delete(expected)
	// Dialers pin the server key; only acceptors may discover a consistent previously unknown peer.
	if !server && len(expected) != 32 { return false }
	if !acquire_loop() { return false } 	// One event loop owns every operation.
	defer nbio.release_thread_event_loop()
	mode := os.args[8] if len(os.args) == 9 else "valid"
	load := mode == "overload" || mode == "holder" || mode == "idle" || mode == "probe"
	target := 1 if mode == "probe" else 8
	socket, socket_err := nbio.create_udp_socket(.IP6 if load else .IP4)
	if socket_err != nil { return false } 	// Cannot start a transport without nonblocking UDP.
	defer net.close(socket)
	bind_port := port if server else 0
	if net.bind(
		   socket,
		   net.Endpoint{net.IP6_Loopback, bind_port} if load else net.Endpoint{net.IP4_Loopback, bind_port},
	   ) !=
	   nil { return false } 	// Only local proof endpoints.
	local, local_err := net.bound_endpoint(socket)
	if local_err != nil { return false } 	// Native engine needs the actual ephemeral client port.
	// Mixed clients retain the soak workload without the old per-session gate; service is listener-only.
	if (mode == "service" || mode == "integration" || mode == "overload") &&
	   !server { return false }
	peer := Peer {
		tracking      = tracking,
		mixed         = mode == "mixed",
		service       = mode == "service" || mode == "integration" || mode == "overload",
		mesh          = load,
		overload      = mode == "overload",
		integrated    = mode == "integration" || mode == "integrated",
		socket        = socket,
		expected      = expected,
		saved_context = context,
		server        = server,
		attack        = "soak" if mode == "service" || mode == "mixed" || mode == "integration" || mode == "integrated" || mode == "overload" else ("valid" if mode == "clean" || mode == "probe" else ("no-fin" if mode == "holder" else mode)),
	}
	// The fixture bank outlives engine destruction; each stream snapshot is destroyed by its final close callback first.
	defer destroy_bank(&peer.bank)
	if peer.integrated {
		directory := os.get_env("RAGNAROK_INTEGRATION_FIXTURES", context.allocator)
		defer delete(directory)
		if !INTEGRATION || !load_bank(&peer.bank, directory) { return false } 	// Ordinary binaries cannot silently claim integration coverage.
	}
	cert, key, alpn :=
		strings.clone_to_cstring(os.args[3]),
		strings.clone_to_cstring(os.args[4]),
		strings.clone_to_cstring(os.args[6])
	defer delete(cert); defer delete(key); defer delete(alpn)
	// Explicit load profiles use IPv6 and liveness probes; all existing proof modes retain their constructor.
	if load {
		profile := IPv6_Profile.Saturated_Service if peer.overload else IPv6_Profile.Crash_Recovery
		peer.transport = rq_transport_new_ipv6_profile(
			i32(profile),
			i32(int(server)),
			u16(local.port),
			cert,
			key,
			alpn,
			&peer,
			verify_peer,
			send_packet,
			on_stream,
		)
	} else {
		peer.transport = rq_transport_new(
			2 if peer.service else (1 if peer.attack == "soak" else 0),
			1 if server else 0,
			u16(local.port),
			cert,
			key,
			alpn,
			&peer,
			verify_peer,
			send_packet,
			on_stream,
		)
	}
	if peer.transport == nil { fmt.eprintln("transport setup failed"); return false } 	// No partially initialized engine is used.
	// Destruction is delayed until all UDP/timer callbacks have stopped borrowing this owner.
	defer rq_transport_free(peer.transport)
	arm_receive(&peer); arm_timer(&peer)
	if server { fmt.println("READY") } else // Listener is bound before orchestration starts the other peer.
	if rq_connect(peer.transport, u16(port)) == 0 { peer.stopping = true } 	// Dial setup failure.
	rq_process(peer.transport)
	started := time.now()
	stop_file := os.get_env("RAGNAROK_SERVICE_STOP", context.allocator)
	defer delete(stop_file)
	last_active := -1
	last_live, last_capacity := -1, -1
	last_load_active := -1
	last_connections := u64(0)
	last_idle := u64(0)
	service_stopped := false
	authenticated := false
	opened := false
	// Drive concurrent CE requests with one I/O loop, stopping on protocol rejection or deadline.
	for !peer.stopping &&
	    !peer.failed &&
	    (peer.service || peer.completed < target) &&
	    time.since(started) < time.Duration(timeout) * time.Millisecond {
		// Connection and stream retirement is observed without replacing the engine or the event loop.
		if peer.service {
			active := int(rq_peer_metric(peer.transport, 0))
			if active != last_active { fmt.println("PEERS", active); last_active = active } 	// Report actual overlap.
			live := 0
			// Buffer ownership ends only at the final native stream-close callback.
			for state in peer.streams { if state.handle != nil { live += 1 } }
			// Emit only changed load state, retaining exact connection and stream capacity observations.
			if peer.overload &&
			   (active != last_load_active ||
					   live != last_live ||
					   peer.capacity_rejected != last_capacity ||
					   rq_peer_metric(peer.transport, 5) != last_connections) {
				fmt.println(
					"LOAD_STATE",
					active,
					live,
					rq_peer_metric(peer.transport, 5),
					peer.capacity_rejected,
					peer.peak_streams,
				)
				last_load_active = active
				last_live = live
				last_capacity = peer.capacity_rejected
				last_connections = rq_peer_metric(peer.transport, 5)
			}
			accepted := rq_peer_metric(peer.transport, 1)
			if active == 0 && live == 0 && accepted > last_idle {
				fmt.println(
					"SERVICE_IDLE",
					accepted,
					rq_peer_metric(peer.transport, 2),
					peer.tracking.current_memory_allocated,
					nbio.num_waiting(),
				)
				last_idle = accepted
			}
			if len(stop_file) == 0 ||
			   os.exists(
				   stop_file,
			   ) { service_stopped = len(stop_file) > 0 && active == 0 && live == 0; break } 	// Require explicit idle shutdown.
		}
		status := rq_status(peer.transport)
		if status < 0 { break } 	// TLS rejection is distinct from successful authentication.
		if status == 1 && !authenticated { fmt.println("AUTH_OK"); authenticated = true } 	// Only after the handshake callback.
		if authenticated && !server && !opened && mode != "idle" {
			opened = true
			for _ in 0 ..< (5 if peer.attack == "soak" else target) { rq_open_stream(peer.transport) } 	// Open all requests before waiting for replies.
			rq_process(peer.transport)
		}
		if peer.attack == "soak" {
			soak_tick(&peer) // Local deadlines never abort the whole connection.
			if !server &&
			   opened &&
			   peer.opened == 5 &&
			   time.since(started) > (1200 if peer.mixed else 650) * time.Millisecond {
				for _ in 0 ..< 3 { rq_open_stream(peer.transport) } 	// Prove continued service after rejection.
				rq_process(peer.transport)
			}
		}
		if nbio.tick(10 * time.Millisecond) != nil { peer.stopping = true } 	// Bounded I/O failure.
	}
	if rq_status(peer.transport) == 1 &&
	   !authenticated { fmt.println("AUTH_OK"); authenticated = true } 	// A receive tick may complete all requests before the loop checks status again.
	success := authenticated && !peer.failed && peer.completed == target
	// The service ends at an external idle barrier, never at the first completed client's stream count.
	if peer.service { success = service_stopped && !peer.failed && rq_peer_metric(peer.transport, 3) >= 3 }
	if success && peer.attack == "soak" && !server {
		success =
			peer.healthy == 3 && peer.rejected == 4 && peer.cancelled == 1 if peer.integrated else peer.healthy == 5 && peer.rejected == 2 && peer.cancelled == 1 // Intentional failures are exact.
	}
	if success && !peer.service { fmt.println("EXCHANGE_OK", target) } 	// Application success requires every requested exchange, including the single admission probe.
	// Briefly drain final handshake packets before closing an authenticated connection.
	if success && !peer.service {
		// Close before stopping UDP, allowing the listener to observe connection retirement between waves.
		if mode == "mixed" ||
		   mode == "clean" ||
		   (mode == "integrated" ||
				   mode == "probe") { rq_disconnect(peer.transport); rq_process(peer.transport) }
		grace := time.now()
		for time.since(grace) < 100 * time.Millisecond { _ = nbio.tick(10 * time.Millisecond) } 	// Keep processing final handshake packets.
	}
	// Failure diagnostics show unsettled owners without exposing any identity private-key bytes.
	if peer.attack == "soak" && !success {
		// Empty slots have already released their application buffers.
		for state in peer.streams {
			if state.handle !=
			   nil { fmt.eprintln("LIVE", state.received_length, state.send_length, state.send_offset, state.read_fin, state.counted, state.attack, time.since(state.started)) }
		}
	}
	peer.stopping = true
	// remove suppresses a pending receive callback, including a completion already queued for delivery.
	// The kernel may still borrow buffer storage until cancellation is drained by run below.
	nbio.remove(peer.receive_operation)
	peer.receive_operation = nil
	_ = nbio.run() // Drain cancellation and standalone timers while Peer and its buffer are still alive.
	if peer.service { fmt.println("SERVICE_DONE", rq_peer_metric(peer.transport, 1), rq_peer_metric(peer.transport, 2), rq_peer_metric(peer.transport, 3)) } 	// Final counters precede engine destruction.
	if !success { fmt.eprintln("proof rejected or timed out", peer.completed, peer.healthy, peer.rejected, peer.cancelled, peer.failed) } 	// Distinguish rejection from successful handshake.
	// The exit code is set after deferred native/socket cleanup by returning through the normal stack.
	return success
}

// Test-only operation owner keeps stack buffer storage alive through cancellation completion.
Cancellation_Probe :: struct {
	operation: ^nbio.Operation,
	buffer:    [1]u8,
	callbacks: int,
}

// A delivered receive retires its handle before recording completion; removed handles must never callback.
on_cancel_probe :: proc(op: ^nbio.Operation, probe: ^Cancellation_Probe) {
	probe.operation = nil
	probe.callbacks += 1
	assert(op.recv.err == nil && op.recv.received == 1 && probe.buffer[0] == 99) // Exact self-sent test datagram.
}

// Exercise idle and ready receive cancellation directly on the host I/O backend.
io_self_test :: proc() {
	// The event-loop owner is process-lived; repeated cancellation must not create a fresh kernel ring each iteration.
	if !acquire_loop() { os.exit(2) }
	defer nbio.release_thread_event_loop()
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	// Retire each socket and operation while reusing the same asynchronous dispatcher, as the soak does.
	for iteration in 0 ..< 256 {
		socket, err := nbio.create_udp_socket(.IP4)
		assert(err == nil)
		assert(net.bind(socket, {net.IP4_Loopback, 0}) == nil)
		local, local_err := net.bound_endpoint(socket)
		assert(local_err == nil)
		probe: Cancellation_Probe
		probe.operation = nbio.recv_poly(socket, {probe.buffer[:]}, &probe, on_cancel_probe)
		// Half the cases also put a completion in flight before removal; the callback may have already retired it.
		if iteration % 2 == 0 {
			payload := [1]u8{99}
			sent, send_err := net.send_udp(socket, payload[:], local)
			assert(send_err == nil && sent == 1)
			assert(nbio.tick(0) == nil)
		}
		before := probe.callbacks
		// Never remove a handle after its callback: nil denotes already retired ownership.
		if probe.operation != nil {
			nbio.remove(probe.operation)
			probe.operation = nil
		}
		assert(nbio.run() == nil) // Drain kernel completions before stack buffer storage goes out of scope.
		assert(probe.callbacks == before) // Removal is final and suppresses queued callback delivery.
		net.close(socket)
		assert(nbio.num_waiting() == 0) // No user operation can borrow the retiring stack buffer or socket.
		assert(tracking.current_memory_allocated == 0) // Application ownership returns to baseline; loop storage is process-lived.
	}
	fmt.println("Odin I/O selftest: 256 idle/ready receive cancellations passed")
}

// Arbitrary-input entry point exercises strict DER and incremental frames without native stream handles.
fuzz_peer :: proc(input: []u8, server, fin: bool) {
	fields: Cert_Fields
	_ = rq_parse_cert(raw_data(input), uintptr(len(input)), &fields)
	peer := Peer {
		server = server,
	}
	stream := Stream_State {
		received_length = len(input),
		read_fin        = fin,
	}
	stream.received = make([]u8, len(input))
	defer delete(stream.received)
	copy(stream.received[:], input)
	complete, valid := frame_extent(&peer, &stream)
	// Complete frames are bounded, exact and cleanly terminated.
	if complete { assert(valid && fin && len(input) == (37 if server else 7)) }
	// Reject premature header EOF immediately instead of repeatedly reading zero bytes.
	if fin && len(input) < (5 if server else 4) { assert(!valid) }
}

// Deterministic malformed-input coverage leaves the parsers independently fuzzable.
self_test :: proc() {
	state := u64(0x51554943)
	for iteration in 0 ..< 10000 {
		input: [128]u8
		// Xorshift supplies reproducible coverage bytes, not cryptographic randomness.
		for &b in input {
			state ~= state << 13; state ~= state >> 7; state ~= state << 17
			b = u8(state & 255)
		}
		fuzz_peer(input[:iteration % 129], iteration % 2 == 0, iteration % 3 == 0)
	}
	fmt.println("Odin QUIC selftest: 10000 malformed DER/frame cases passed")
}

// Exit only after the attempt returns through all deferred transport/socket/event-loop cleanup.
main :: proc() {
	// Mesh policy tests require no sockets; dual-role runs retain both engines on one dispatcher.
	if len(os.args) == 2 && os.args[1] == "--mesh-selftest" { mesh_self_test(); return }
	if len(os.args) > 1 && os.args[1] == "mesh" { mesh_main(); return }
	// Composition tests own no transport; tracking asserts every decode/hash outcome releases its storage.
	if len(os.args) == 2 &&
	   os.args[1] ==
		   "--integration-selftest" { if !INTEGRATION { os.exit(2) }; integration_self_test(); return }

	// Parser fuzz tests do not create an engine or require socket permission.
	if len(os.args) == 2 && os.args[1] == "--selftest" { self_test(); return }
	// This regression probes cancellation ownership on the actual host backend before opening TLS sessions.
	if len(os.args) == 2 && os.args[1] == "--io-selftest" { io_self_test(); return }
	if len(os.args) == 9 &&
	   (os.args[8] == "service" || os.args[8] == "integration" || os.args[8] == "overload") {
		// A process-lived dispatcher keeps its allocations outside the application ownership baseline.
		if !acquire_loop() { os.exit(2) }
		defer nbio.release_thread_event_loop()
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		defer mem.tracking_allocator_destroy(&tracking)
		context.allocator = mem.tracking_allocator(&tracking)
		if !run_peer(&tracking) { os.exit(2) } 	// Native/socket cleanup completes before measuring retained application allocations.
		assert(tracking.current_memory_allocated == 0)
		assert(nbio.num_waiting() == 0)
		fmt.println("SERVICE_CLEAN", tracking.current_memory_allocated, nbio.num_waiting())
		return
	}
	if len(os.args) == 9 && os.args[8] == "soak" {
		// Hold one dispatcher across sessions; run_peer's nested acquire/release borrows this process-lived owner.
		if !acquire_loop() { os.exit(2) }
		defer nbio.release_thread_event_loop()
		tracking: mem.Tracking_Allocator
		mem.tracking_allocator_init(&tracking, context.allocator)
		defer mem.tracking_allocator_destroy(&tracking)
		context.allocator = mem.tracking_allocator(&tracking) // Track all native application ownership across sessions.
		rounds_text := os.get_env("RAGNAROK_SOAK_ROUNDS", context.allocator)
		gate := os.get_env("RAGNAROK_SOAK_GATE", context.allocator)
		defer delete(rounds_text); defer delete(gate)
		rounds, ok := strconv.parse_int(rounds_text)
		if !ok || rounds < 1 || rounds > 1000 || len(gate) == 0 { os.exit(2) } 	// Trusted controls still have hard ceilings.
		baseline := tracking.current_memory_allocated // Only the round/gate controls remain owned between sessions.
		// Keep the same allocator/process while repeatedly rebuilding and retiring native transport resources.
		for iteration in 0 ..= rounds {
			control := fmt.aprintf("%s/%s-%d", gate, os.args[1], iteration)
			started := time.now()
			for !os.exists(control) {
				if time.since(started) > 15 * time.Second { os.exit(2) } 	// A dead harness cannot retain peers indefinitely.
				time.sleep(10 * time.Millisecond)
			}
			delete(control)
			if iteration == rounds { break } 	// Final idle snapshot precedes normal process exit.
			if !run_peer() { os.exit(2) } 	// Every deferred cleanup completes before the idle snapshot.
			if tracking.current_memory_allocated != baseline {
				fmt.eprintln(
					"application allocations retained",
					tracking.current_memory_allocated,
					baseline,
				)
				// Source locations identify leaked ownership without printing buffer contents.
				for _, entry in tracking.allocation_map { fmt.eprintln(entry.location, entry.size) }
				os.exit(2)
			}
			fmt.println("ALLOC_BYTES", tracking.current_memory_allocated)
			fmt.println("SESSION_DONE", iteration)
		}
	} else if !run_peer() { os.exit(2) } 	// A rejected or timed-out peer is not successful authentication.
}
