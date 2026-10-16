## Intentional rejection keeps retained composition bytes and child descriptors private.
import ../../../src/block_codec

var owner: OwnedExtrinsic
discard owner.data
