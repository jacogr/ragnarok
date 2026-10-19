# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Runtime selected-result probes for immutable accumulation yield/checkpoint state operations.
## Dynamic modes require the intended contract, including successful contexts with absent yield.

import std/cmdline
import ../../src/state/[accumulation_effects, accumulation_context]
import ../../src/codec/[state_outputs, bounded, composite, state_privileges, state_authorization]
import ../../src/chain/parameters
import ../support/accumulation_effect_context

# Only absent-yield extraction needs a genuinely prepared initialized owner as its negative control.
let pair = if paramStr(1) == "absent": prepareAccumulationEffects(preparedEffectContexts()).value
else: default(AccumulationEffects) # Other modes intentionally retain no initialized provenance.

# Dynamic origins keep the default/refused extraction checks in the runtime harness rather than static evaluation.
let outcome = if paramStr(1) == "refused": prepareAccumulationEffects(default(PreparedAccumulationContexts))
else: default(AccumulationEffectResult[AccumulationEffects]) # Neither alternative supplies a usable pair.
let context = default(AccumulationEffectContext)
case paramStr(1)
of "refused": discard outcome.value # Invalid initial contexts expose no pair.
of "dimension": discard pair.effectContext(AccumulationDimension.Regular).value # No default dimension child.
of "source": discard pair.effectsSource.value # No fabricated initial preparation.
of "initial": discard context.effectInitialContext.value # No substituted account backing.
of "accounts": discard context.effectAccounts.value # Default contexts cannot fabricate current accounts.
of "storage": discard recordAccumulationStorage(pair, [], [], default(Parameters), ByteLimit(
    0)).value # Failed changes contain no successor.
of "account-info": discard context.effectAccountInfo(ServiceIndex(42), default(
    Parameters)).value # No fabricated fixed account record.
of "privileges": discard context.effectPrivileges.value # Default contexts expose no current privilege snapshot.
of "queues": discard context.effectQueues.value # Defaults cannot expose a current queue owner.
of "assign": discard recordAccumulationAssign(pair, AuthorizationCoreIndex(0), [], ServiceIndex(0),
  default(AuthorizationConfig), default(PrivilegeConfig)).value # Failed mutation carries no successor.
of "bless": discard recordAccumulationBless(pair, default(PrivilegeState), default(
    PrivilegeConfig)).value # Default pairs cannot publish roles.
of "info": discard context.effectInfo.value # No default metadata/effects.
of "yield": discard context.effectYield.value # No default hash.
of "absent": discard pair.effectContext(AccumulationDimension.Regular).value.effectYield.value # Absence is not zero bytes.
of "record": discard recordAccumulationYield(pair, default(OutputCommitment)).value # Default pairs cannot yield.
of "checkpoint": discard checkpointAccumulationEffects(pair).value # Default pairs cannot checkpoint.
else: discard outcome.value # Default results require selected success too.
