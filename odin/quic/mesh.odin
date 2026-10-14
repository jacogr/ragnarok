// Bounded dual-role IPv6 lifecycle proof; each logical peer retains two LSQUIC role engines on one nbio loop.
package main
import "core:fmt"
import "core:mem"
import "core:nbio"
import "core:net"
import "core:os"
import "core:strconv"
import "core:strings"
import "core:time"

// Apply JAMNP-S Required connectivity to full lexicographic key bytes, with final-byte high-bit parity.
preferred :: proc(local, remote: [32]u8) -> bool {
	less := false
	// Stop at the first unequal byte; high-bit selection is independent of this lexicographic ordering.
	for i in 0 ..< 32 {
		if local[i] != remote[i] { less = local[i] < remote[i]; break }
	}
	return (local[31] > 127) != (remote[31] > 127) != less
}

// Cover both key orders, all final-byte high-bit combinations and reversed argument symmetry without sockets.
mesh_self_test :: proc() {
	// Public synthetic keys exercise the exact preferred-initiator expression, including its 127/128 boundary.
	for high_a in ([2]u8{0, 128}) {
		// Change the remote high bit independently of the local key.
		for high_b in ([2]u8{0, 128}) {
			// Exercise both lexicographic orders for this high-bit combination.
			for first_a in ([2]u8{0, 2}) {
				a, b: [32]u8
				a[0] = first_a; b[0] = 1
				a[31] = high_a; b[31] = high_b
				assert(preferred(a, b) == ((high_a != high_b) != (first_a < 1)))
				assert(preferred(a, b) != preferred(b, a))
			}
		}
	}
	a, b: [32]u8
	b[31] = 127
	assert(preferred(a, b))
	b[31] = 128
	assert(!preferred(a, b))
	fmt.println("MESH_POLICY_OK")
}

// Count retained application owners, which outlive a settled message until the native close callback.
mesh_live :: proc(peer: ^Peer) -> int {
	count := 0
	// Nil handles identify only slots whose final close has released their buffers.
	for state in peer.streams { if state.handle != nil { count += 1 } }
	return count
}

// Dispatch both endpoints on the one thread event loop, surfacing any native framing or UDP failure.
mesh_step :: proc(incoming, outgoing: ^Peer) -> bool {
	if nbio.tick(10 * time.Millisecond) != nil { return false } 	// Kernel failures settle the bounded run.
	return !incoming.failed && !outgoing.failed
}

// External gates hold stable live or idle owners for sampling, with an explicit missing-harness deadline.
mesh_gate :: proc(incoming, outgoing: ^Peer, path: string) -> bool {
	started := time.now()
	// Keep both retained engines responsive while awaiting a local control file.
	for !os.exists(path) {
		if !mesh_step(incoming, outgoing) ||
		   time.since(started) > 15 * time.Second { return false }
	}
	return true
}

// Run sixteen reconnect rounds without replacing either socket, engine, TLS context or event loop.
run_mesh :: proc(tracking: ^mem.Tracking_Allocator) -> bool {
	if len(os.args) != 10 { return false } 	// Fixed trusted CLI shape before indexing.
	local_port, local_ok := strconv.parse_int(os.args[2])
	remote_port, remote_ok := strconv.parse_int(os.args[3])
	rounds_text := os.get_env("RAGNAROK_MESH_ROUNDS", context.allocator)
	defer delete(rounds_text)
	rounds := 16
	// Optional bounded workload controls cannot silently overflow host integers.
	if len(rounds_text) > 0 {
		value, ok := strconv.parse_int(rounds_text)
		if !ok { return false }
		rounds = value
	}
	if !local_ok ||
	   !remote_ok ||
	   local_port < 1 ||
	   local_port > 65535 ||
	   remote_port < 1 ||
	   remote_port > 65535 ||
	   rounds < 1 ||
	   rounds > 64 { return false }
	local_key, local_error := os.read_entire_file(os.args[6], context.allocator)
	defer delete(local_key)
	remote_key, remote_error := os.read_entire_file(os.args[7], context.allocator)
	defer delete(remote_key)
	if local_error != nil ||
	   remote_error != nil ||
	   len(local_key) != 32 ||
	   len(remote_key) != 32 { return false } 	// No malformed identity input.
	a, b: [32]u8
	copy(a[:], local_key); copy(b[:], remote_key)
	if a == b { return false } 	// Reject self-dial and ambiguous preferred selection.
	initiator := preferred(a, b)
	incoming_socket, incoming_error := nbio.create_udp_socket(.IP6)
	if incoming_error != nil { return false } 	// No socket exists to bind or register.
	defer net.close(incoming_socket)
	outgoing_socket, outgoing_error := nbio.create_udp_socket(.IP6)
	if outgoing_error != nil { return false } 	// The incoming socket still retires through its defer.
	defer net.close(outgoing_socket)
	if net.bind(incoming_socket, {net.IP6_Loopback, local_port}) != nil ||
	   net.bind(outgoing_socket, {net.IP6_Loopback, 0}) != nil { return false }
	local, bind_error := net.bound_endpoint(outgoing_socket)
	if bind_error != nil { return false } 	// Retain the actual outgoing port through all reconnects.
	incoming := Peer {
		server        = true,
		mesh          = true,
		socket        = incoming_socket,
		expected      = remote_key,
		saved_context = context,
		attack        = "valid",
	}
	outgoing := Peer {
		mesh          = true,
		socket        = outgoing_socket,
		expected      = remote_key,
		saved_context = context,
		attack        = "valid",
	}
	// Drain every receive/timer before destroying engines; both stack owners and their buffers remain alive.
	defer {
		incoming.stopping = true; outgoing.stopping = true
		if incoming.receive_operation != nil { nbio.remove(incoming.receive_operation) } 	// Cancel borrowed receive storage.
		if outgoing.receive_operation != nil { nbio.remove(outgoing.receive_operation) }
		_ = nbio.run()
		if outgoing.transport != nil { rq_transport_free(outgoing.transport) } 	// Final stream-close callbacks release buffers.
		if incoming.transport != nil { rq_transport_free(incoming.transport) } 	// Global TLS cleanup follows the final engine.
	}
	cert, key, alpn :=
		strings.clone_to_cstring(os.args[4]),
		strings.clone_to_cstring(os.args[5]),
		strings.clone_to_cstring(os.args[8])
	defer delete(cert); defer delete(key); defer delete(alpn)
	incoming.transport = rq_transport_new_ipv6(
		1,
		u16(local_port),
		cert,
		key,
		alpn,
		&incoming,
		verify_peer,
		send_packet,
		on_stream,
	)
	if incoming.transport == nil { return false }
	outgoing.transport = rq_transport_new_ipv6(
		0,
		u16(local.port),
		cert,
		key,
		alpn,
		&outgoing,
		verify_peer,
		send_packet,
		on_stream,
	)
	if outgoing.transport == nil { return false }
	arm_receive(&incoming); arm_timer(&incoming)
	arm_receive(&outgoing); arm_timer(&outgoing)
	fallback_text := os.get_env("RAGNAROK_MESH_FALLBACK", context.allocator)
	defer delete(fallback_text)
	fmt.println("MESH_READY", int(initiator))
	authenticated_in, authenticated_out: u64
	// The same two stable owners and dispatcher live across every independently gated connection round.
	for round in 0 ..< rounds {
		start_path := fmt.aprintf("%s/start-%d", os.args[9], round)
		start_ok := mesh_gate(&incoming, &outgoing, start_path)
		delete(start_path)
		if !start_ok { return false }
		fallback := round == 0 && fallback_text == "1"
		started := time.now()
		// First-round fallback deliberately suppresses the preferred dial for the spec's example five seconds.
		if fallback {
			for time.since(started) < 5 * time.Second {
				if !mesh_step(&incoming, &outgoing) { return false } 	// Listener and timers remain responsive.
			}
			if !initiator && rq_connect(outgoing.transport, u16(remote_port)) == 0 { return false }
		} else {
			if rq_connect(outgoing.transport, u16(remote_port)) == 0 { return false } 	// Deliberately race both directions.
		}
		use_outgoing := !initiator if fallback else initiator
		kept := &outgoing if use_outgoing else &incoming
		discarded := &incoming if use_outgoing else &outgoing
		// Successful generations survive a close race; current status alone would forget the losing handshake.
		if fallback {
			if use_outgoing { authenticated_out += 1 } else { authenticated_in += 1 } 	// One fallback direction.
		} else {
			authenticated_in += 1; authenticated_out += 1 // Require both successful handshakes for this duplicate round.
		}
		started = time.now()
		// Native policy sees authenticated directions before deciding which duplicate to close.
		for rq_status(kept.transport) != 1 ||
		    rq_peer_metric(incoming.transport, 4) < authenticated_in ||
		    rq_peer_metric(outgoing.transport, 4) < authenticated_out {
			if !mesh_step(&incoming, &outgoing) ||
			   time.since(started) > 10 * time.Second { return false }
		}
		if !fallback {
			fmt.println("MESH_DUPLICATE", round)
			rq_disconnect(discarded.transport) // Local project policy keeps the preferred-initiator connection.
		}
		started = time.now()
		// Do not queue CE work until the discarded direction has retired its native connection owner.
		for rq_peer_metric(discarded.transport, 0) != 0 {
			if !mesh_step(&incoming, &outgoing) ||
			   time.since(started) > 10 * time.Second { return false }
		}
		if rq_peer_metric(kept.transport, 0) != 1 { return false }
		fmt.println("MESH_CONNECTED", round, int(use_outgoing))
		// Both sides issue four queries on this same retained connection, independent of its TLS role.
		for _ in 0 ..< 4 { rq_open_stream(kept.transport) }
		started = time.now()
		for kept.healthy != 8 || mesh_live(kept) != 0 {
			if !mesh_step(&incoming, &outgoing) ||
			   time.since(started) > 10 * time.Second { return false }
		}
		fmt.println("MESH_EXCHANGED", round, kept.healthy)
		close_path := fmt.aprintf("%s/close-%d", os.args[9], round)
		close_ok := mesh_gate(&incoming, &outgoing, close_path)
		delete(close_path)
		if !close_ok { return false }
		rq_disconnect(kept.transport)
		started = time.now()
		// Reconnect is released only after both connections and all stream buffer owners have retired.
		for rq_peer_metric(incoming.transport, 0) != 0 ||
		    rq_peer_metric(outgoing.transport, 0) != 0 ||
		    mesh_live(&incoming) != 0 ||
		    mesh_live(&outgoing) != 0 {
			if !mesh_step(&incoming, &outgoing) ||
			   time.since(started) > 10 * time.Second { return false }
		}
		kept.healthy = 0; kept.completed = 0
		fmt.println(
			"MESH_IDLE",
			round,
			tracking.current_memory_allocated,
			rq_peer_metric(incoming.transport, 1),
			rq_peer_metric(outgoing.transport, 1),
			rq_peer_metric(incoming.transport, 2),
			rq_peer_metric(outgoing.transport, 2),
		)
	}
	stop_path := fmt.aprintf("%s/stop", os.args[9])
	defer delete(stop_path)
	return mesh_gate(&incoming, &outgoing, stop_path)
}

// Process-lived nbio state is outside the tracked application scope; cleanup must leave zero operations/allocations.
mesh_main :: proc() {
	if !acquire_loop() { os.exit(2) } 	// Explicit platform/backend setup failure.
	defer nbio.release_thread_event_loop()
	tracking: mem.Tracking_Allocator
	mem.tracking_allocator_init(&tracking, context.allocator)
	defer mem.tracking_allocator_destroy(&tracking)
	context.allocator = mem.tracking_allocator(&tracking)
	if !run_mesh(&tracking) { os.exit(2) } 	// run_mesh has already drained callbacks and destroyed both engines.
	assert(tracking.current_memory_allocated == 0)
	assert(nbio.num_waiting() == 0)
	fmt.println("MESH_CLEAN", tracking.current_memory_allocated, nbio.num_waiting())
}
