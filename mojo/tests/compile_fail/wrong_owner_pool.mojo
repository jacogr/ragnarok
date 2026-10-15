from std.collections import Span
from codec.owned import OwnedFrame, copy_owned_blob


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var owner = OwnedFrame(None)
    var wrong_pool: List[UInt8] = [0]
    var output: List[UInt8] = [0]
    _ = copy_owned_blob(owner, Span(wrong_pool), 0, Span(output))
