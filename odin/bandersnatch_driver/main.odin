// Trusted public-fixture adapter; opaque native owners never escape command scope.
package main
import bs "../bandersnatch"
import "core:encoding/hex"
import "core:fmt"
import "core:os"
import "core:strconv"
import "core:thread"

// Own decoded fixture bytes; dash is the empty context/additional-data value.
bytes :: proc(text: string) -> []u8 {
	// Empty contexts have no input element address.
	if text == "-" { return nil }
	output := make([]u8, len(text) / 2)
	_, ok := hex.decode_into_buffer(transmute([]u8)text, output)
	assert(ok && len(text) % 2 == 0)
	return output
}
// Print successful owned public bytes only; errors have no default proof or verified hash.
output :: proc(value: bs.Bs_Result($T)) {
	// Checked status precedes union selection and hex formatting.
	if bs.error_of(value) !=
	   .None { fmt.println("error:", int(bs.error_of(value)), sep = ""); return }
	raw := bs.success_of(value)
	text := hex.encode(raw[:]); defer delete(text)
	fmt.println(string(text))
}
// Prove scalar copying, nil defaults and single-release key/setup lifetimes through Rust's original allocator.
ownership :: proc() {
	empty: bs.Bs_Key
	assert(bs.error_of(bs.public_key(empty)) == .Invalid_Owner)
	scalar: [32]u8; scalar[0] = 1
	imported := bs.import_scalar(scalar[:]); assert(bs.error_of(imported) == .None)
	key := bs.success_of(imported)
	pub := bs.success_of(bs.public_key(key)); scalar[0] = 2
	assert(pub == bs.success_of(bs.public_key(key)))
	sig := bs.success_of(bs.sign(key, nil, nil))
	assert(bs.error_of(bs.verify(pub, sig, nil, nil)) == .None)
	bs.destroy_key(&key); assert(key == nil)
	bs.destroy_key(&key) // Repeated release of the cleared owner is harmless; no released alias is used.
	loaded := bs.new_setup(8); assert(bs.error_of(loaded) == .None)
	setup := bs.success_of(loaded)
	bs.destroy_setup(&setup); assert(setup == nil)
	bs.destroy_setup(&setup)
	// Setup arithmetic must reject negative, empty and unsupported capacities.
	for size in ([]int{-1, 0, 1024}) { assert(bs.error_of(bs.new_setup(size)) == .Invalid_Length) }
	initial: bs.Bs_Result(bs.Bs_Output)
	assert(bs.error_of(initial) == .Uninitialized)
	fmt.println("ok")
}
// Each worker imports one independent scalar; every proof context remains local to the call.
worker :: proc(t: ^thread.Thread) {
	scalar: [32]u8; scalar[0] = u8(t.user_index + 1)
	loaded := bs.import_scalar(scalar[:]); assert(bs.error_of(loaded) == .None)
	key := bs.success_of(loaded); defer bs.destroy_key(&key)
	pub := bs.success_of(bs.public_key(key))
	// Repeated native operations share no mutable secret or hash state between threads.
	for _ in 0 ..< 32 {
		signature := bs.success_of(bs.sign(key, scalar[:], nil))
		assert(bs.error_of(bs.verify(pub, signature, scalar[:], nil)) == .None)
	}
}
// Join every worker before releasing its OS thread handle.
concurrent :: proc() {
	threads: [4]^thread.Thread
	// Assign fixture identity before starting each independent native owner.
	for i in 0 ..< 4 { threads[i] = thread.create(worker); assert(threads[i] != nil); threads[i].user_index = i; thread.start(threads[i]) }
	// Joined workers have finished all Rust calls and owner destruction.
	for t in threads { thread.join(t); thread.destroy(t) }
	fmt.println("ok")
}
// Load bounded trusted arguments into scoped arrays and dispatch one operation.
main :: proc() {
	a := os.args[1:]; assert(len(a) >= 1)
	// Lifetime/concurrency probes require no payload arguments.
	if a[0] == "O" { ownership(); return }
	if a[0] == "T" { concurrent(); return } 	// Same-process Rust ABI thread safety.
	if a[0] == "F" {
		failed: bs.Bs_Result(bs.Bs_Output)
		fmt.println(bs.success_of(failed)); return // Deliberate checked failed-result selection must trap.
	}
	text := "-"
	// Public-only derivation has no context argument; all other requests supply argument two.
	if len(a) > 2 { text = a[2] }
	input := bytes(text); defer delete(input)
	switch a[0] {
	// This branch owns a canonical scalar until public derivation/signing finishes.
	case "P", "S":
		// For these commands the private scalar is argument one rather than argument two.
		scalar := bytes(a[1]); defer delete(scalar)
		loaded := bs.import_scalar(scalar)
		if bs.error_of(loaded) !=
		   .None { fmt.println("error:", int(bs.error_of(loaded)), sep = ""); return } 	// No default key on failure.
		key := bs.success_of(loaded); defer bs.destroy_key(&key)
		if a[0] == "P" { output(bs.public_key(key)) } else {
			// Signing borrows raw context and additional data separately.
			ad := bytes(a[3]); defer delete(ad); output(bs.sign(key, input, ad))
		}
	// Complete encoded public/proof sizes must pass before union selection.
	case "V":
		encoded := bytes(a[1]); defer delete(encoded)
		pub := bs.import_public_key(encoded); sig := bs.import_signature(input)
		if bs.error_of(pub) !=
		   .None { fmt.println("error:", int(bs.error_of(pub)), sep = ""); return } 	// No invalid point payload.
		if bs.error_of(sig) !=
		   .None { fmt.println("error:", int(bs.error_of(sig)), sep = ""); return } 	// No truncated proof payload.
		context_bytes := bytes(a[3]); defer delete(context_bytes)
		ad := bytes(a[4]); defer delete(ad)
		output(bs.verify(bs.success_of(pub), bs.success_of(sig), context_bytes, ad))
	// Every ring operation owns an explicit domain/SRS setup for this scope.
	case "R", "G", "W":
		capacity, ok := strconv.parse_int(a[1]); assert(ok)
		loaded := bs.new_setup(capacity)
		if bs.error_of(loaded) !=
		   .None { fmt.println("error:", int(bs.error_of(loaded)), sep = ""); return } 	// Invalid setup has no owner.
		setup := bs.success_of(loaded); defer bs.destroy_setup(&setup)
		if a[0] == "R" { output(bs.commit_ring(setup, input)) } else if a[0] == "W" {
			// Root and anonymous proof imports validate their own exact widths.
			proof_bytes := bytes(a[3]); defer delete(proof_bytes)
			root := bs.import_ring_root(input); proof := bs.import_ring_proof(proof_bytes)
			if bs.error_of(root) !=
			   .None { fmt.println("error:", int(bs.error_of(root)), sep = ""); return } 	// No default root.
			if bs.error_of(proof) !=
			   .None { fmt.println("error:", int(bs.error_of(proof)), sep = ""); return } 	// No default proof.
			context_bytes := bytes(a[4]); defer delete(context_bytes)
			ad := bytes(a[5]); defer delete(ad)
			output(
				bs.verify_ring(
					setup,
					bs.success_of(root),
					bs.success_of(proof),
					context_bytes,
					ad,
				),
			)
		} else {
			// A matching scalar/index must be supplied before membership proving can begin.
			key_result := bs.import_scalar(input)
			if bs.error_of(key_result) !=
			   .None { fmt.println("error:", int(bs.error_of(key_result)), sep = ""); return }
			key := bs.success_of(key_result); defer bs.destroy_key(&key)
			index, index_ok := strconv.parse_int(a[3]); assert(index_ok)
			members := bytes(a[4]); defer delete(members)
			context_bytes := bytes(a[5]); defer delete(context_bytes)
			ad := bytes(a[6]); defer delete(ad)
			output(bs.sign_ring(setup, key, index, members, context_bytes, ad))
		}
	// An unknown command is a trusted harness error.
	case:
		os.exit(1)
	}
}
