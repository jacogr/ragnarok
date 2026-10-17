## Scalar owners cannot select the ring setup allocator/domain.
import ../../../src/bandersnatch/bandersnatch
discard commitRing(default(BsKey), [])
