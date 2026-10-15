from std.collections import Span
from std.sys import argv
from codec.types import Failure, CheckedResult, fail
from crypto.primitives import *
from crypto.concurrency import concurrent
from tests.support import unhex, hex_text


# Print owned fixed bytes only after selecting the successful result alternative.
def output[kind: Int, length: Int](var result: CheckedResult[PublicBytes[kind, length]]):
    comptime T = PublicBytes[kind, length]
    # Failure must never print a default digest/signature/key.
    if result.isa[Failure]():
        print("error")
        return
    var value = result[T].copy()
    print(hex_text(Span(value.bytes)))


# Native retained-seed tests cover default failure, exact widths, deep copy and alias invalidation.
def ownership() raises:
    var empty = EdSeed(None)
    var initial = CheckedResult[EdPublicKey]()
    var invalid = public_key(empty)
    # Neither default owner nor default result is a usable zero signing identity.
    if not invalid.isa[Failure]() or not initial.isa[Failure]():
        raise Error("default seed/result")
    var bytes = List[UInt8](length=32, fill=0)
    var loaded = import_seed(Span(bytes))
    # A explicitly imported zero seed is valid and owns a separate copy.
    if not loaded.isa[EdSeed]():
        raise Error("seed import")
    var seed = loaded[EdSeed].copy()
    try:
        var alias = seed.copy()
        var before = public_key(seed)
        bytes[0] = 42
        var after = public_key(alias)
        # Later caller mutation cannot alter the retained signing identity.
        if not before.isa[EdPublicKey]() or not after.isa[EdPublicKey]():
            raise Error("public derivation")
        var b = before[EdPublicKey].copy()
        var a = after[EdPublicKey].copy()
        # Compare all 32 public bytes, not just a prefix.
        for i in range(32):
            if b.bytes[i] != a.bytes[i]:
                raise Error("seed mutated through caller")
        var signature = sign(alias, Span(bytes)[:0])
        # Both complete fixed values must exist before verification.
        if not signature.isa[EdSignature]() or not verify(
            a, signature[EdSignature], Span(bytes)[:0]
        ):
            raise Error("retained signature")
        clear_seed(seed)
        var cleared = public_key(alias)
        var rejected = sign(seed, Span(bytes))
        # Clearing one alias invalidates signing and derivation through all aliases.
        if not cleared.isa[Failure]() or not rejected.isa[Failure]():
            raise Error("cleared alias")
    finally:
        # Exactly one original owner frees storage and explicitly wipes its secret bytes.
        release_seed(seed)
    print("ok")


# Test-only command adapter borrows public fixtures; production primitives remain typed native APIs.
def main() raises:
    var args = argv()
    # Bad utility commands must not invoke a guessed production primitive.
    if len(args) < 2:
        raise Error("command")
    var command = args[1]
    # Deliberate wrong-alternative selection must trap even in optimized builds.
    if command == "F":
        var failed = CheckedResult[EdPublicKey]()
        var value = failed[EdPublicKey].copy()
        print(hex_text(Span(value.bytes)))
        return
    elif command == "O":
        # Lifetime/ownership probes use only deterministic test seeds.
        ownership()
        return
    elif command == "T":
        # Bounded native workers test the public callback ABI and backend state isolation.
        concurrent()
        return
    var input = unhex(args[2])
    # Hashing accepts the exact raw message, including an explicit empty token.
    if command == "B":
        output(blake2b256(Span(input)))
    elif command == "K":
        output(keccak256(Span(input)))
    elif command == "V":
        # Import each fixed encoding independently before reading successful values.
        var key = import_public(Span(input))
        var raw = unhex(args[3])
        var signature = import_signature(Span(raw))
        var message = unhex(args[4])
        if not key.isa[EdPublicKey]() or not signature.isa[EdSignature]():
            # Invalid widths do not enter the verifier.
            print("error")
        else:
            print(Int(verify(key[EdPublicKey], signature[EdSignature], Span(message))))
    elif command == "P" or command == "S":
        # Derivation/signing retains a private copy only for this request scope.
        var loaded = import_seed(Span(input))
        if not loaded.isa[EdSeed]():
            # Rejected seeds expose no signature/public-key payload.
            print("error")
            return
        var seed = loaded[EdSeed].copy()
        try:
            if command == "P":
                # Public derivation adds no message or domain.
                output(public_key(seed))
            else:
                # Sign the exact fixture message with ordinary Ed25519.
                var message = unhex(args[3])
                output(sign(seed, Span(message)))
        finally:
            # Wipe and retire the retained native seed even when adapter parsing raises.
            release_seed(seed)
    else:
        # Unknown commands are test-harness errors, never a default primitive choice.
        raise Error("command")
