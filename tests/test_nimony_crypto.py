# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

"""Run the preserved primitive equations against a caller-supplied Nimony binary; never compile on import."""
import argparse
import json
from pathlib import Path
from nimony_crypto import corpus

# Keep compilation/toolchain selection in the parent trial runner and emit a machine-readable corpus result.
def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--binary', type=Path, required=True)
    args = parser.parse_args()
    print(json.dumps(corpus(args.binary.resolve()), sort_keys=True))

# Importing this helper performs no builds or vector queries.
if __name__ == '__main__':
    main()
