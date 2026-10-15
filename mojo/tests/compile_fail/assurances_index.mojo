from std.collections import Array
from codec.assurances import *


# Intentional nominal-domain misuse must be rejected before runtime.
def main():
    var value = ValidatorIndex(CoreCount(0))
    _ = value
