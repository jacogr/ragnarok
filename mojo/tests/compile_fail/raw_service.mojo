from codec.types import ServiceIndex


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var service: ServiceIndex = UInt32(1)
    _ = service
