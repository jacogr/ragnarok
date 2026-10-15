from bandersnatch.primitives import BsKey, BsSetup


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var key = BsKey(None)
    var setup: BsSetup = key
    _ = setup
