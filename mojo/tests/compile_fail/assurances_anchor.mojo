from std.collections import Array
from codec.assurances import *


# Intentional nominal-domain misuse must be rejected before runtime.
def main():
    var value = AssuranceAnchor(AssuranceSignature(Array[UInt8, 64](fill=0)))
    _ = value
