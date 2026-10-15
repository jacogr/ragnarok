from codec.types import fail


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var failed = fail["truncated"]()
    _ = failed.value
