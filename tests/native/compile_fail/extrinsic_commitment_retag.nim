## Binding and commitment payloads/discriminators remain private across all alternatives.
import ../../../src/crypto/extrinsic_commitment
import ../../../src/codec/header
var hidden = default(ExtrinsicCommitmentResult[ExtrinsicRoot])
hidden.status = ExtrinsicCommitmentError.None
