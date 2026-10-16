## White-box project-owned alias regression; public probes separately prove these fields are inaccessible.
include ../../src/codec/block_codec

# Expected-good snapshots alone authorize private test backing-allocation setup.
proc checked[T](parsed: FrameResult[T]): T =
  doAssert parsed.error == FrameError.None
  parsed.value

let config = fullFrameConfig(ByteLimit(1048576), PreimageLimits(items: ElementLimit(16),
  perBlob: ByteLimit(1024), totalBlobBytes: ByteLimit(1024)))
var source: Extrinsic
source.tickets = checked(decodeComponent[ComponentKind.Tickets](@[0'u8], config)).owner
source.preimages = checked(decodeComponent[ComponentKind.Preimages](@[0'u8], config)).owner
source.guarantees = checked(decodeComponent[ComponentKind.Guarantees](@[0'u8], config)).owner
source.assurances = checked(decodeComponent[ComponentKind.Assurances](@[0'u8], config)).owner
source.disputes = checked(decodeComponent[ComponentKind.Disputes](@[0'u8, 0, 0], config)).owner
# Reserve genuine spare backing bytes while restoring every original validated dispute byte and metadata extent.
source.disputes.data.wire.setLen(4096)
source.disputes.data.wire.setLen(3)
let late = cast[ptr UncheckedArray[byte]](addr source.disputes.data.wire[0])
doAssert encodeExtrinsic(source, config, late.toOpenArray(0, 6)).error == FrameError.AliasedBuffers
let owner = checked(ownExtrinsic(source, config))
doAssert encodeOwnedExtrinsic(owner, late.toOpenArray(0, 6)).error == FrameError.AliasedBuffers
# The same late-component buffer must be protected from an earlier whole-block header destination.
var headerBytes: array[1024, byte]
let headerSize = header.encodeHeader(header.Header(), headerConfig(config), headerBytes)
doAssert headerSize.error == HeaderError.None
let h = checked(decodeComponent[ComponentKind.Header](headerBytes.toOpenArray(0,
    headerSize.value-1), config)).owner
let blockSource = Block(header: h, extrinsic: owner)
doAssert encodeBlock(blockSource, config, late.toOpenArray(0, headerSize.value+6)).error ==
    FrameError.AliasedBuffers
# Component-only re-emission must also reject attempts to overwrite immutable private backing bytes.
doAssert encodeComponent(source.disputes, late.toOpenArray(0, 2)).error == FrameError.AliasedBuffers

echo "Nim blocks: whole-destination private-wire alias checks passed"
