## Intentional rejection protects static component/parent schema identities.
import ../../../src/codec/block_codec

var source: Block = default(Block)
var wrong: GuaranteeComponent = default(GuaranteeComponent)
source.header = wrong
