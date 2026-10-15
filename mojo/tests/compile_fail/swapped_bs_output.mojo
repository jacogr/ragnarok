from std.collections import Array
from bandersnatch.primitives import BsPublicKey, BsOutput


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var value = BsPublicKey(Array[UInt8, 32](fill=0))
    var wrong: BsOutput = value
    _ = wrong
