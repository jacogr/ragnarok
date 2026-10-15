from std.collections import Array
from codec.assurances import AssuranceAnchor
from crypto.primitives import EdSignature
from crypto.assurance_context import AssuranceParent, AssuranceSigningMessage


# Intentional wrong-domain construction must be rejected before runtime.
def main():
    var value: EdSignature = AssuranceSigningMessage(Array[UInt8, 46](fill=0))
    _ = value
