# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Typed service reads consume authenticated partial evidence without claiming a complete account map.
## Missing witnesses, proven absence and malformed present bytes remain separate outcomes.
import ./[proof_view, trie_proof]
import ../codec/[bounded, state_accounts, state_layout]

type
  ServiceProofError* {.pure.} = enum ## Failed/default reads expose only a reason, never a fabricated value.
    Uninitialized, None, MissingWitness, AbsentValue, InvalidValue, LimitExceeded,
    BackendFailure, InvalidInput
  ServiceProofResult*[T] = object ## Success alone grants access to a complete typed read.
    case status: ServiceProofError
    of None:
      completed: T
    else:
      discard                     # Refused reads retain no successful prefix or default account.

func error*[T](outcome: ServiceProofResult[T]): ServiceProofError =
  ## Inspect a reason without authorizing payload access.
  outcome.status
func value*[T](outcome: ServiceProofResult[T]): T {.inline,
    requires: outcome.status == ServiceProofError.None.} =
  ## Extract only explicitly successful typed reads in checked optimized builds.
  outcome.completed
func viewReason(reason: ProofViewError): ServiceProofError =
  ## Exact lookup has no malformed-value interpretation; preserve absent evidence separately.
  case reason
  of ProofViewError.MissingWitness: ServiceProofError.MissingWitness # Unknown never means absent.
  else: ServiceProofError.Uninitialized # Default views cannot authorize any query.

proc readProofAccount*(view: ProofView, service: ServiceIndex): ServiceProofResult[
    ServiceMetadata] =
  ## Decode exact current C(255, service), without claiming validity of its unqueried nested maps.
  let found = view.lookup(chapterServiceKey(StateChapter(255), service))
  if found.error != ProofViewError.None:
    return ServiceProofResult[ServiceMetadata](status: viewReason(found.error))
  if not found.value.present:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.AbsentValue)
  if found.value.byteLength != ServiceMetadataBytes:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  let decoded = decodeServiceMetadata(found.value.bytes, ByteLimit(ServiceMetadataBytes))
  if decoded.error != ServiceMetadataError.None:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  if decoded.value.consumed != ServiceMetadataBytes:
    return ServiceProofResult[ServiceMetadata](status: ServiceProofError.InvalidValue)
  ServiceProofResult[ServiceMetadata](status: ServiceProofError.None,
      completed: decoded.value.metadata)
