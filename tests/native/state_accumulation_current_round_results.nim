# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Default/refused current round owners expose neither partial success nor inactive nested parent results.
import std/cmdline
import ../../src/chain/parameters as chain_parameters
import ../../src/state/accumulation_current_round as state_accumulation_current_round
import ../../src/state/accumulation_round as state_accumulation_round
let owner = default(CurrentAccumulationRoundResult[PreparedCurrentAccumulationRound])
let refused = runCurrentBlockAccumulationRound(default(BlockAccumulationRound), default(Parameters),
    default(CurrentAccumulationRoundLimits))
let round = default(PreparedCurrentAccumulationRound)
case paramStr(1)
of "refused": discard refused.value # Only the actual matching selected alternative authorizes extraction.
of "guest": discard owner.guestFailure # Only the actual matching selected alternative authorizes extraction.
of "account": discard owner.accountFailure # Only the actual matching selected alternative authorizes extraction.
of "provision": discard owner.provisionFailure # Only the actual matching selected alternative authorizes extraction.
of "global": discard owner.globalFailure # Only the actual matching selected alternative authorizes extraction.
of "output": discard owner.outputFailure # Only the actual matching selected alternative authorizes extraction.
of "transfer": discard owner.transferFailure # Only the actual matching selected alternative authorizes extraction.
of "pending": discard owner.pendingFailure # Only the actual matching selected alternative authorizes extraction.
of "globals": discard round.currentRoundGlobals.value # Only the actual matching selected alternative authorizes extraction.
of "outputs": discard round.currentRoundOutputs.value # Only the actual matching selected alternative authorizes extraction.
of "transfers": discard round.currentRoundTransfers.value # Only the actual matching selected alternative authorizes extraction.
of "pending-owner": discard round.currentRoundPending.value # Only the actual matching selected alternative authorizes extraction.
of "guests": discard round.currentRoundGuests.value # Only the actual matching selected alternative authorizes extraction.
of "snapshot": discard round.currentRoundSnapshot.value # Only the actual matching selected alternative authorizes extraction.
of "parameters": discard round.currentRoundParameters.value # Default owners cannot supply frozen chain configuration.
else: discard owner.value # No synthetic completed current round.
