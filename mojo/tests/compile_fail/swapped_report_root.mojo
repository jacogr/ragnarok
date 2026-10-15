from std.collections import Array
from codec.report import PackageHash, SegmentRoot


# A package identity cannot be initialized with an exported-segment commitment.
def main():
    var wrong: PackageHash = SegmentRoot(Array[UInt8, 32](fill=0))
    _ = wrong
