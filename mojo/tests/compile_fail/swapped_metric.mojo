from codec.types import ImportCount, ExportCount


# Deliberate type/API misuse must fail for its intended domain or inaccessible payload.
def main():
    var imports = ImportCount(1)
    var exports: ExportCount = imports
    _ = exports
