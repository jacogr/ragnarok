## Intentional rejection protects static component/parent schema identities.
import ../../../src/codec/block_codec

var owner: OwnedBlock = default(OwnedBlock)
discard extrinsicInfo(owner)
