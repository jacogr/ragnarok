## Intentional rejection protects static component/parent schema identities.
import ../../../src/block_codec

var owner: OwnedBlock
discard extrinsicInfo(owner)
