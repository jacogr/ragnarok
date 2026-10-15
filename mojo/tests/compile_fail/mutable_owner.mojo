from codec.owned import OwnedFrame


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var owner = OwnedFrame(None)
    owner._opaque.value()[].wire[0] = 7
