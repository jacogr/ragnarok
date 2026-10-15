from std.collections import Array, Span
from std.sys import argv
from codec.types import CheckedResult, Failure
from codec.assurances import AssuranceBits, AssuranceConfig, CoreCount, ValidatorCount
from crypto.primitives import EdPublicKey, import_public
from crypto.assurance_context import (
    AssuranceParent,
    AssuranceSigningMessage,
    VerifiedAssuranceCount,
    assurance_message,
    verify_assurances,
)
from tests.assurances_driver import require, unhex, records, logical, equal
from tests.support import unsigned, hex_text


# Render every public-key field independently to check immutable borrowed input after verification.
def key_bytes(keys: Span[mut=False, EdPublicKey, _]) -> List[UInt8]:
    var result = List[UInt8]()
    # Native key domains own the exact encodings selected by validator identity.
    for i in range(len(keys)):
        for j in range(32):
            # Inspect all public bytes, not a checksum or a provider-produced reconstruction.
            result.append(keys[i].bytes[j])
    return result^


# Construct all inputs independently of production decoders and inspect complete success/failure outcomes.
def request(p: List[String]) raises:
    var default_message = CheckedResult[AssuranceSigningMessage]()
    var default_verified = CheckedResult[VerifiedAssuranceCount]()
    require(default_message.isa[Failure]() and default_message[Failure].reason() == "uninitialized")
    require(
        default_verified.isa[Failure]() and default_verified[Failure].reason() == "uninitialized"
    )
    # Direct typed transcript construction cannot inherit a paired encoder/decoder mistake.
    if p[0] == "M":
        require(len(p) == 4)
        var raw_parent = unhex(p[2])
        var raw_bits = unhex(p[3])
        require(len(raw_parent) == 32 and len(raw_bits) == 43)
        var parent = Array[UInt8, 32](fill=0)
        var bits = Array[UInt8, 43](fill=0)
        # Expected parent retains its own nominal domain, separate from assurance anchors.
        for i in range(32):
            parent[i] = raw_parent[i]
        # Preserve every native storage octet, including intentionally invalid unused ones.
        for i in range(43):
            bits[i] = raw_bits[i]
        var value = AssuranceBits(bits^)
        var checked = assurance_message(AssuranceParent(parent^), value, CoreCount(unsigned(p[1])))
        equal(Span(value.bytes), Span(raw_bits))
        if checked.isa[Failure]():
            # No default or partial transcript can be read from a failed result.
            print(checked[Failure].reason())
        else:
            # Every byte of the owned success message is compared by the external oracle.
            var message = checked[AssuranceSigningMessage]
            print(hex_text(Span(message.bytes)))
    else:
        # Verification receives an explicit profile, parent and exact validator-key array.
        require(p[0] == "V" and len(p) == 6)
        var config = AssuranceConfig(CoreCount(unsigned(p[1])), ValidatorCount(unsigned(p[2])))
        var raw_parent = unhex(p[3])
        var raw_keys = unhex(p[4])
        var raw_values = unhex(p[5])
        require(len(raw_parent) == 32 and len(raw_keys) % 32 == 0)
        var parent = Array[UInt8, 32](fill=0)
        # Construct parent bytes independently of every record's own anchor.
        for i in range(32):
            parent[i] = raw_parent[i]
        var keys = List[EdPublicKey]()
        # Existing imports own ordinary public encodings without changing provider point policy.
        for i in range(len(raw_keys) // 32):
            var imported = import_public(Span(raw_keys)[32 * i : 32 * i + 32])
            require(imported.isa[EdPublicKey]())
            keys.append(imported[EdPublicKey])
        var values = records(Span(raw_values))
        var checked = verify_assurances(Span(values), config, AssuranceParent(parent^), Span(keys))
        var after_values = logical(Span(values))
        var after_keys = key_bytes(Span(keys))
        equal(Span(after_values), Span(raw_values))
        equal(Span(after_keys), Span(raw_keys))
        if checked.isa[Failure]():
            # Failure contains its reason alone, never a partially verified count.
            print(checked[Failure].reason())
        else:
            # Count certifies only this stateless context/signature check.
            print("ok " + String(checked[VerifiedAssuranceCount].value))


# The native process reads a trusted batch file; Python/OpenSSL participate only in fixture preparation.
def main() raises:
    var args = argv()
    require(len(args) == 2)
    var text = String()
    with open(args[1], "r") as file:
        # Retain batch text while its synchronous line/token views are in use.
        text = file.read()
    var lines = text.split("\n")
    # Every test request executes the same public production APIs.
    for i in range(len(lines)):
        var line = String(lines[i])
        if line.byte_length() == 0:
            # The final newline must not create a phantom operation.
            continue
        var parts = line.split(" ")
        var p = List[String]()
        for j in range(len(parts)):
            # Own textual tokens throughout the synchronous verification call.
            p.append(String(parts[j]))
        request(p^)
