from std.collections import Array
from codec.digest import CodeHash, PayloadHash


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var value = PayloadHash(Array[UInt8, 32](fill=0))
    var wrong: CodeHash = value
    _ = wrong
