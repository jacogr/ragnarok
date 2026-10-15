from std.collections import Span
from std.sys import argv
from codec.types import Failure, CheckedResult, fail
from crypto.primitives import PublicBytes
from bandersnatch.primitives import *
from bandersnatch.concurrency import concurrent
from tests.support import unhex, hex_text, signed


# Print the exact owned public encoding or its established native failure ordinal.
def output[kind: Int, length: Int](var result: CheckedResult[PublicBytes[kind, length]]):
    comptime T = PublicBytes[kind, length]
    # Failed proofs/keys must never expose default output bytes.
    if result.isa[Failure]():
        var reason = result[Failure].reason()
        print("error:" + reason[byte=3:])
        return
    var value = result[T].copy()
    print(hex_text(Span(value.bytes)))


# Test shared aliases, explicit close and default results without a networking engine or interpreter.
def ownership() raises:
    var missing = BsKey(None)
    var default = CheckedResult[BsOutput]()
    var absent = public_key(missing)
    # Missing key/default result cannot act as a usable identity or output.
    if not absent.isa[Failure]() or not default.isa[Failure]():
        raise Error("default owner/result")
    var scalar = List[UInt8](length=32, fill=0)
    scalar[0] = 1
    var loaded = import_scalar(Span(scalar))
    if not loaded.isa[BsKey]():
        # Deterministic canonical scalar one must import successfully.
        raise Error("scalar one")
    var key = loaded[BsKey].copy()
    try:
        var alias = key.copy()
        var before = public_key(alias)
        scalar[0] = 2
        var after = public_key(key)
        # Rust owns the imported scalar independently of Mojo's mutable input.
        if not before.isa[BsPublicKey]() or not after.isa[BsPublicKey]():
            raise Error("public derivation")
        var first = before[BsPublicKey].copy()
        var second = after[BsPublicKey].copy()
        # Compare every public byte after original input mutation.
        for i in range(32):
            if first.bytes[i] != second.bytes[i]:
                raise Error("scalar input ownership")
        var sig = sign(alias, Span(scalar), Span(scalar)[:0])
        if not sig.isa[BsSignature]():
            # Failed signing contains no default proof to feed into verification.
            raise Error("contextual signature")
        var verified = verify(first, sig[BsSignature], Span(scalar), Span(scalar)[:0])
        if not verified.isa[BsOutput]():
            # Extraction must occur only after the signature passes verification.
            raise Error("contextual verification")
        close_key(key)
        var closed = public_key(alias)
        # Closing one owner invalidates its aliases before state memory is released.
        if not closed.isa[Failure]():
            raise Error("closed alias")
    finally:
        # Release the original native-language state exactly once; Rust scalar was already closed.
        release_key(key)
    var setup_result = new_setup(3)
    if not setup_result.isa[BsSetup]():
        # The historical tiny domain must be available through the existing Rust ABI.
        raise Error("setup")
    var setup = setup_result[BsSetup].copy()
    var alias = setup.copy()
    close_setup(setup)
    var ring = List[UInt8](length=32, fill=255)
    var closed_commit = commit_ring(alias, Span(ring))
    # Alias-visible closed state must reject work rather than dereferencing freed Rust parameters.
    if not closed_commit.isa[Failure]():
        raise Error("closed setup alias")
    release_setup(setup)
    print("ok")


# Dispatch trusted published/JAM fixtures to the full historical primitive API with scoped owners.
def main() raises:
    var args = argv()
    # An absent command cannot select a default primitive or schema.
    if len(args) < 2:
        raise Error("command")
    var command = args[1]
    if command == "O":
        # Deterministic ownership tests retain no production secrets.
        ownership()
        return
    elif command == "F":
        # Deliberate wrong-alternative access must trap even in an optimized binary.
        var failed = CheckedResult[BsOutput]()
        var value = failed[BsOutput].copy()
        print(hex_text(Span(value.bytes)))
        return
    elif command == "T":
        # Real native callbacks exercise independent Rust proof state in the same process.
        concurrent()
        return
    if command == "P" or command == "S":
        # Exact canonical scalar import precedes any derivation or contextual signature.
        var scalar = unhex(args[2])
        var loaded = import_scalar(Span(scalar))
        if not loaded.isa[BsKey]():
            # Preserve the established test protocol's ordinal failure response.
            print("error:" + loaded[Failure].reason()[byte=3:])
            return
        var key = loaded[BsKey].copy()
        try:
            if command == "P":
                # Derivation owns its full public encoding.
                output(public_key(key))
            else:
                # Raw context and additional data stay separate across the FFI boundary.
                var context = unhex(args[3])
                var additional = unhex(args[4])
                output(sign(key, Span(context), Span(additional)))
        finally:
            # Every path zeroizes and retires one original scalar owner.
            release_key(key)
    elif command == "V":
        # Key validation and fixed signature width are distinct import gates.
        var bytes = unhex(args[2])
        var raw = unhex(args[3])
        var key = import_public(Span(bytes))
        var proof = import_bytes[11, 96](Span(raw))
        if not key.isa[BsPublicKey]():
            # Invalid points never enter the contextual verifier.
            print("error:" + key[Failure].reason()[byte=3:])
            return
        elif not proof.isa[BsSignature]():
            # Wrong signature widths expose no default proof.
            print("error:" + proof[Failure].reason()[byte=3:])
            return
        var context = unhex(args[4])
        var additional = unhex(args[5])
        output(verify(key[BsPublicKey], proof[BsSignature], Span(context), Span(additional)))
    elif command == "R" or command == "G" or command == "W":
        # Root/proving/verification all bind to one explicit historical SRS/domain capacity.
        var loaded = new_setup(signed(args[2]))
        if not loaded.isa[BsSetup]():
            # Bad capacities create no parameter owner.
            print("error:" + loaded[Failure].reason()[byte=3:])
            return
        var setup = loaded[BsSetup].copy()
        try:
            if command == "R":
                # Member normalization belongs to Mojo before commitment generation in Rust.
                var ring = unhex(args[3])
                output(commit_ring(setup, Span(ring)))
            elif command == "W":
                # Exact root and anonymous proof widths are separate gates before verification.
                var root_bytes = unhex(args[3])
                var proof_bytes = unhex(args[4])
                var root = import_bytes[13, 144](Span(root_bytes))
                var proof = import_bytes[12, 784](Span(proof_bytes))
                if not root.isa[BsRingRoot]():
                    # No truncated root is supplied to the backend.
                    print("error:" + root[Failure].reason()[byte=3:])
                    return
                elif not proof.isa[BsRingProof]():
                    # No default anonymous proof can be extracted from an import failure.
                    print("error:" + proof[Failure].reason()[byte=3:])
                    return
                var context = unhex(args[5])
                var additional = unhex(args[6])
                output(
                    verify_ring(
                        setup, root[BsRingRoot], proof[BsRingProof], Span(context), Span(additional)
                    )
                )
            else:
                # Anonymous proving retains a distinct live scalar owner inside the setup scope.
                var scalar = unhex(args[3])
                var imported = import_scalar(Span(scalar))
                if not imported.isa[BsKey]():
                    # Invalid scalar imports cannot prove ring membership.
                    print("error:" + imported[Failure].reason()[byte=3:])
                    return
                var key = imported[BsKey].copy()
                try:
                    var ring = unhex(args[5])
                    var context = unhex(args[6])
                    var additional = unhex(args[7])
                    output(
                        sign_ring(
                            setup, key, signed(args[4]), Span(ring), Span(context), Span(additional)
                        )
                    )
                finally:
                    # Secret retirement completes before setup parameters leave scope.
                    release_key(key)
        finally:
            # All aliases stop using domain parameters before their sole original owner is released.
            release_setup(setup)
    else:
        # Unknown commands are harness errors, never a fallback crypto operation.
        raise Error("command")
