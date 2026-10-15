from std.collections import Array
from codec.assurances import AssuranceAnchor
from crypto.primitives import EdSignature
from crypto.assurance_context import AssuranceParent, AssuranceSigningMessage


# Intentional wrong-domain construction must be rejected before runtime.
def main():
    var value: AssuranceParent = AssuranceAnchor(Array[UInt8, 32](fill=0))
    _ = value
