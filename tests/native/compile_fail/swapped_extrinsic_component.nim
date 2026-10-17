## Intentional rejection protects static component/parent schema identities.
import ../../../src/codec/block_codec

var source: Extrinsic = default(Extrinsic)
var wrong: PreimageComponent = default(PreimageComponent)
source.tickets = wrong
