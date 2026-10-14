// Isolated JAMNP-S authentication proof using a single core:nbio loop and pinned LSQUIC/TLS.
package main
import "base:runtime"
import "core:fmt"
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
	handle:                       rawptr,
	received:                     [1050]u8,
	received_length:              int,
	sending:                      [64]u8,
	send_length, send_offset:     int,
	read_fin, write_fin, counted: bool,
}
// Native owner outlives every receive/timer/C callback; buffers never refer to expired stack frames.
Peer :: struct {
	transport:      rawptr,
	socket:         net.UDP_Socket,
	expected:       []u8,
	buffer:         [2048]u8,
	stopping:       bool,
	saved_context:  runtime.Context,
	server, failed: bool,
	streams:        [16]Stream_State,
	completed:      int,
	attack:         string,
}
// Explicit library build path supplied by the reproducible proof runner.
when ODIN_OS == .Darwin {
	foreign import quic "../../build/quic/libquic_proof.dylib"
} else {
	foreign import quic "../../build/quic/libquic_proof.so"
}
// Opaque C API wraps transport/TLS layouts, leaving all JAM identity and I/O policy in Odin.
foreign quic {
	rq_parse_cert :: proc "c" (der: [^]u8, length: uintptr, fields: ^Cert_Fields) -> i32 ---
	rq_transport_new :: proc "c" (server: i32, port: u16, cert, key, alpn: cstring, user: rawptr, verify: proc "c" (_: rawptr, _: [^]u8, _: uintptr) -> i32, send: proc "c" (_: rawptr, _: [^]u8, _: uintptr, _: u16) -> i32, stream: proc "c" (_: rawptr, _: rawptr, _: i32)) -> rawptr ---
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
			   256 {index |= int((key[position / 8] >> uint(position % 8)) & 1) << uint(bit)} 	// Zero-extended high bits.
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
	if rq_parse_cert(der, length, &fields) != 1 {return 0}
	if fields.ed_key != 1 ||
	   fields.ed_signature != 1 ||
	   fields.key_length != 32 ||
	   fields.san_extensions != 1 ||
	   fields.san_count != 1 ||
	   fields.san_dns != 1 {return 0} 	// Exact algorithm/name cardinality.
	name := peer_name(fields.key)
	if fields.san_length != uintptr(len(name)) {return 0} 	// Never accept a NUL-truncated name prefix.
	// Compare every supplied SAN byte with its key-derived name.
	for b, i in name {if fields.san[i] != b {return 0}} 	// Altered SAN is a different identity.
	// Client key pins and optional server fixture pins are checked independently of SAN consistency.
	if len(peer.expected) > 0 {
		if len(peer.expected) != 32 {return 0} 	// No narrowing of malformed identity fixtures.
		for b, i in fields.key {if peer.expected[i] != b {return 0}} 	// Exact expected key.
	}
	return 1
}

// Nonblocking UDP sends finish before returning, so borrowed C packet storage never escapes this callback.
send_packet :: proc "c" (user: rawptr, bytes: [^]u8, length: uintptr, port: u16) -> i32 {
	peer := (^Peer)(user)
	context = peer.saved_context
	written, err := net.send_udp(peer.socket, bytes[:int(length)], {net.IP4_Loopback, int(port)})
	// Would-block/error leaves the datagram with LSQUIC for a later retry.
	if err != nil || written != int(length) {return 0}
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

// Check an incremental E4 frame before accepting its payload; no untrusted length chooses an allocation.
frame_extent :: proc(peer: ^Peer, stream: ^Stream_State) -> (complete: bool, valid: bool) {
	start := 1 if peer.server else 0
	// The initiator's first byte selects the explicit CE protocol.
	if peer.server &&
	   stream.received_length >= 1 &&
	   stream.received[0] != 143 {return false, false}
	if stream.received_length < start + 4 {return false, !stream.read_fin} 	// Partial length waits for more bytes.
	claimed: u64
	for i in 0 ..< 4 {claimed |= u64(stream.received[start + i]) << uint(8 * i)} 	// E4 network frame header.
	maximum := u64(32) if peer.server else u64(1024)
	if claimed > maximum {return false, false} 	// Reject before allocation or indexing.
	extent := start + 4 + int(claimed)
	if stream.received_length > extent {return false, false} 	// Exactly one message is allowed in this direction.
	if !stream.read_fin {return false, true} 	// CE success requires FIN, not only enough payload bytes.
	if stream.received_length != extent {return false, false} 	// Premature FIN is truncation.
	if peer.server {
		if claimed != 32 {return false, false} 	// Hash is fixed width.
		for b, i in REQUEST_HASH {if stream.received[5 + i] != b {return false, false}} 	// Fixture map lookup.
	} else {
		if claimed != 3 {return false, false} 	// Exact expected preimage size.
		for i in 0 ..< 3 {if stream.received[4 + i] != u8(i + 1) {return false, false}} 	// Compare actual bytes.
	}
	return true, true
}

// Stream callback preserves owned buffers and native CE framing while the bridge exposes only opaque transport handles.
on_stream :: proc "c" (user: rawptr, handle: rawptr, event: i32) {
	peer := (^Peer)(user)
	context = peer.saved_context
	state: ^Stream_State
	// Locate the callback's live owner; no stream memory survives its close event.
	for &slot in peer.streams {if slot.handle == handle {state = &slot; break}}
	if event == 0 {
		// Bound simultaneous streams before assigning application buffers.
		for &slot in peer.streams {if slot.handle == nil {state = &slot; break}}
		if state == nil {peer.failed = true; rq_stream_abort(handle); return} 	// No unbounded per-stream allocation.
		state^ = Stream_State {
			handle = handle,
		}
		if !peer.server {
			state.sending[0] = 143; state.sending[1] = 32
			for b, i in REQUEST_HASH {state.sending[5 + i] = b} 	// Kind + E4 length + fixture hash.
			state.send_length = 37
			// Controlled adversarial fixtures exercise the authenticated server's framing/resource checks.
			switch peer.attack {
			case "valid", "no-fin": // Valid bytes; no-fin withholds clean request termination.
			case "bad-kind":
				state.sending[0] = 144 // Unsupported protocol selector.
			case "oversize":
				for i in 1 ..= 4 {state.sending[i] = 255} 	// Reject declared length before allocation.
			case "unknown":
				state.sending[5] ~= 1 // Missing fixture map entry.
			case "truncated":
				state.send_length = 36 // FIN before the last declared hash byte.
			case "trailing":
				state.send_length = 38 // Extra data after the single framed message.
			case:
				peer.failed = true; rq_stream_abort(handle); return // Unknown trusted test selector.
			}
			rq_stream_want_write(handle, 1)
		}
		return
	}
	if state == nil {peer.failed = true; return} 	// Unexpected callback cannot dereference expired ownership.
	if event == 3 {
		if !state.counted && !peer.stopping {peer.failed = true} 	// Premature reset/close is not CE success.
		state.handle = nil
		return
	}
	if peer.stopping {return} 	// Native transport destruction can issue final close callbacks.
	if event == 1 {
		// Consume partial or coalesced reads into fixed storage and check the length as soon as it arrives.
		for {
			if state.received_length ==
			   len(state.received) {peer.failed = true; rq_stream_abort(handle); return} 	// Bounded receive extent.
			got := rq_stream_read(
				handle,
				raw_data(state.received[state.received_length:]),
				uintptr(len(state.received) - state.received_length),
			)
			if got == -2 {break} 	// Await more transport credit/data.
			if got < 0 {peer.failed = true; rq_stream_abort(handle); return} 	// Reset/fatal read failure.
			if got == 0 {state.read_fin = true} else // A clean FIN completes the read direction.
			{state.received_length += int(got)} 	// Accepted bytes stay owned until close.
			complete, valid := frame_extent(peer, state)
			if !valid {peer.failed = true; rq_stream_abort(handle); return} 	// Malformed or unknown request is rejected.
			if complete {
				rq_stream_want_read(handle, 0) // FIN has been validated; no more read callbacks belong to this direction.
				if peer.server {
					state.sending[0] = 3; state.sending[4] = 1; state.sending[5] = 2; state.sending[6] = 3
					state.send_length = 7
					rq_stream_want_write(handle, 1) // Only send after request FIN validates.
				} else if !state.counted {
					state.counted = true; peer.completed += 1 // Exact response plus both FIN directions completes CE.
				}
				break
			}
		}
	} else if event == 2 {
		// Preserve unsent bytes through would-block/partial writes, never freeing storage at enqueue time.
		for state.send_offset < state.send_length {
			sent := rq_stream_write(
				handle,
				raw_data(state.sending[state.send_offset:state.send_length]),
				uintptr(state.send_length - state.send_offset),
			)
			if sent == -2 || sent == 0 {return} 	// Await stream flow-control credit.
			if sent < 0 {peer.failed = true; rq_stream_abort(handle); return} 	// Failed response/request is not successful.
			state.send_offset += int(sent)
		}
		rq_stream_want_write(handle, 0)
		if !state.write_fin && (peer.server || peer.attack != "no-fin") {
			rq_stream_fin(handle); state.write_fin = true // Half-close writing while response reads remain active.
			if peer.server && !state.counted {state.counted = true; peer.completed += 1} 	// Request FIN and queued response FIN.
		}
	}
}

// Process one owned receive buffer, then rearm only while the native owner remains active.
on_receive :: proc(op: ^nbio.Operation, peer: ^Peer) {
	// Timeout wakes lifecycle checks; only received UDP bytes enter the transport.
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
	if !peer.stopping {arm_receive(peer)}
}

// Keep the receive buffer in the owner until completion; a short timeout bounds shutdown latency.
arm_receive :: proc(peer: ^Peer) {
	nbio.recv_poly(
		peer.socket,
		{peer.buffer[:]},
		peer,
		on_receive,
		timeout = 20 * time.Millisecond,
	)
}

// Schedule QUIC deadlines on the same I/O thread; each callback owns no borrowed TLS buffers.
on_timer :: proc(op: ^nbio.Operation, peer: ^Peer) {
	// Do not touch a transport after shutdown begins.
	if peer.stopping {return}
	rq_process(peer.transport)
	arm_timer(peer)
}

// Use LSQUIC's next deadline with a bounded idle wakeup, rather than one timer thread per connection.
arm_timer :: proc(peer: ^Peer) {
	delay := clamp(rq_next_tick(peer.transport), i64(1000), i64(10000))
	nbio.timeout_poly(time.Duration(delay) * time.Microsecond, peer, on_timer)
}

// Run one bounded authentication attempt and drain I/O callbacks before releasing TLS/native contexts.
run_peer :: proc() -> bool {
	if len(os.args) != 8 &&
	   len(os.args) !=
		   9 {fmt.eprintln("mode port cert key expected-key alpn timeout-ms"); return false} 	// Trusted CLI shape.
	port, port_ok := strconv.parse_int(os.args[2])
	timeout, timeout_ok := strconv.parse_int(os.args[7])
	if !port_ok ||
	   port < 1 ||
	   port > 65535 ||
	   !timeout_ok ||
	   timeout < 1 ||
	   timeout > 10000 {return false} 	// Guard all narrowing.
	server := os.args[1] == "server"
	if !server && os.args[1] != "client" {return false} 	// No guessed role.
	expected: []u8
	if os.args[5] != "-" {
		data, err := os.read_entire_file(os.args[5], context.allocator)
		if err != nil || len(data) != 32 {return false} 	// Bounded fixture identity before transport setup.
		expected = data
	}
	defer delete(expected)
	// Dialers pin the server key; only acceptors may discover a consistent previously unknown peer.
	if !server && len(expected) != 32 {return false}
	if nbio.acquire_thread_event_loop() != nil {return false} 	// One event loop owns every operation.
	defer nbio.release_thread_event_loop()
	socket, socket_err := nbio.create_udp_socket(.IP4)
	if socket_err != nil {return false} 	// Cannot start a transport without nonblocking UDP.
	defer net.close(socket)
	bind_port := port if server else 0
	if net.bind(socket, {net.IP4_Loopback, bind_port}) != nil {return false} 	// Only local proof endpoints.
	local, local_err := net.bound_endpoint(socket)
	if local_err != nil {return false} 	// Native engine needs the actual ephemeral client port.
	peer := Peer {
		socket        = socket,
		expected      = expected,
		saved_context = context,
		server        = server,
		attack        = os.args[8] if len(os.args) == 9 else "valid",
	}
	cert, key, alpn :=
		strings.clone_to_cstring(os.args[3]),
		strings.clone_to_cstring(os.args[4]),
		strings.clone_to_cstring(os.args[6])
	defer delete(cert); defer delete(key); defer delete(alpn)
	peer.transport = rq_transport_new(
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
	if peer.transport == nil {fmt.eprintln("transport setup failed"); return false} 	// No partially initialized engine is used.
	// Destruction is delayed until all UDP/timer callbacks have stopped borrowing this owner.
	defer rq_transport_free(peer.transport)
	arm_receive(&peer); arm_timer(&peer)
	if server {fmt.println("READY")} else // Listener is bound before orchestration starts the other peer.
	if rq_connect(peer.transport, u16(port)) == 0 {peer.stopping = true} 	// Dial setup failure.
	rq_process(peer.transport)
	started := time.now()
	authenticated := false
	opened := false
	// Drive concurrent CE requests with one I/O loop, stopping on protocol rejection or deadline.
	for !peer.stopping &&
	    !peer.failed &&
	    peer.completed < 8 &&
	    time.since(started) < time.Duration(timeout) * time.Millisecond {
		status := rq_status(peer.transport)
		if status < 0 {break} 	// TLS rejection is distinct from successful authentication.
		if status == 1 && !authenticated {fmt.println("AUTH_OK"); authenticated = true} 	// Only after the handshake callback.
		if authenticated && !server && !opened {
			opened = true
			for _ in 0 ..< 8 {rq_open_stream(peer.transport)} 	// Open all requests before waiting for replies.
			rq_process(peer.transport)
		}
		if nbio.tick(10 * time.Millisecond) != nil {peer.stopping = true} 	// Bounded I/O failure.
	}
	if rq_status(peer.transport) == 1 &&
	   !authenticated {fmt.println("AUTH_OK"); authenticated = true} 	// A receive tick may complete all requests before the loop checks status again.
	success := authenticated && !peer.failed && peer.completed == 8
	if success {fmt.println("EXCHANGE_OK 8")} 	// Application success requires all eight framed exchanges.
	// Briefly drain final handshake packets before closing an authenticated connection.
	if success {
		grace := time.now()
		for time.since(grace) < 100 * time.Millisecond {_ = nbio.tick(10 * time.Millisecond)} 	// Keep processing final handshake packets.
	}
	peer.stopping = true
	_ = nbio.run() // Existing callbacks retire without rearming; their owner is still alive.
	if !success {fmt.eprintln("proof rejected or timed out")} 	// Distinguish rejection from successful handshake.
	// The exit code is set after deferred native/socket cleanup by returning through the normal stack.
	return success
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
	copy(stream.received[:], input)
	complete, valid := frame_extent(&peer, &stream)
	// Complete frames are bounded, exact and cleanly terminated.
	if complete {assert(valid && fin && len(input) == (37 if server else 7))}
	// Reject premature header EOF immediately instead of repeatedly reading zero bytes.
	if fin && len(input) < (5 if server else 4) {assert(!valid)}
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
	// Parser fuzz tests do not create an engine or require socket permission.
	if len(os.args) == 2 && os.args[1] == "--selftest" {self_test(); return}
	if !run_peer() {os.exit(2)} 	// A rejected or timed-out peer is not successful authentication.
}
