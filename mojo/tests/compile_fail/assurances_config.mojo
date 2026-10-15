from std.collections import Array
from codec.assurances import *


# Intentional nominal-domain misuse must be rejected before runtime.
def main():
    var value = AssuranceConfig(ValidatorCount(2), CoreCount(6))
    _ = value
