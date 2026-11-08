# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Closed assurance-namespace I/O jobs borrow one fixed native owner until exact worker collection/join; capture owns independent bounded paths and never retains a cancellation callback.

import ../../jamnp-s/[assurance_store, assurance_record]

type
  AssuranceStorageMode* {.pure.} = enum ## Startup explicitly distinguishes a fresh independent namespace from an existing one.
    Open, Create
  AssuranceStorageJobError* {.pure.} = enum ## Failed/default capture exposes no callable job or borrowed native owner.
    Uninitialized, None, InvalidPath, InvalidPolicy, Busy
  StorageData = ref object ## Acyclic bounded input owns only startup policy/path and a synchronous lease of the caller's final-address namespace owner.
    owner: ptr AssuranceStore
    folder: string
    chain: AssuranceChainId
    limits: AssuranceStoreLimits
    mode: AssuranceStorageMode
  AssuranceStorageJob* = object ## Only capture binds the fixed owner and closed namespace operation; no raw runner callback is accepted.
    data: nil StorageData
  AssuranceStorageAdmission* = object ## Capture failure carries a reason alone, never a partial path or resource job.
    case status: AssuranceStorageJobError
    of None: completed: AssuranceStorageJob
    else: discard # No default successful job is exposed.

func error*(outcome: AssuranceStorageAdmission): AssuranceStorageJobError =
  ## Read the selected capture refusal before accessing a queued operation.
  outcome.status

func value*(outcome: AssuranceStorageAdmission): AssuranceStorageJob {.requires: outcome.status ==
    AssuranceStorageJobError.None.} =
  ## Only a completely captured operation may enter the native worker lease.
  outcome.completed

func valid*(job: AssuranceStorageJob): bool =
  ## Default jobs borrow no store and cannot execute an empty successful setup.
  job.data != nil

proc captureAssuranceStorage*(owner: var AssuranceStore, folder: string, chain: AssuranceChainId,
    limits: AssuranceStoreLimits, mode: AssuranceStorageMode): AssuranceStorageAdmission =
  ## The caller keeps owner at its final address and freezes every alias until collection/join; capture performs no filesystem I/O.
  if owner.opened: return AssuranceStorageAdmission(status: AssuranceStorageJobError.Busy)
  if not limits.valid: return AssuranceStorageAdmission(
      status: AssuranceStorageJobError.InvalidPolicy)
  if folder.len == 0 or folder.len > 4000 or folder[folder.len-1] ==
      '/': return AssuranceStorageAdmission(status: AssuranceStorageJobError.InvalidPath)
  for character in folder:
    # C truncation cannot select a different resource after the host has admitted a job.
    if character == char(0): return AssuranceStorageAdmission(
        status: AssuranceStorageJobError.InvalidPath)
  var path = ""
  for character in folder: path.add(character) # External option/path owners may retire before CPU execution begins.
  AssuranceStorageAdmission(status: AssuranceStorageJobError.None,
    completed: AssuranceStorageJob(data: StorageData(owner: addr owner, folder: path,
      chain: chain, limits: limits, mode: mode)))

proc executeAssuranceStorage*(job: AssuranceStorageJob,
    control: AssuranceScanControl): AssuranceStoreResult[bool] =
  ## Only the reusable worker supplies its live cancellation view; no context outlives this synchronous operation.
  let data = job.data
  if data == nil: return default(AssuranceStoreResult[bool])
  let owner = data.owner
  if data.mode == AssuranceStorageMode.Create:
    return owner[].createAssuranceStore(data.folder, data.chain, data.limits, control)
  owner[].openAssuranceStore(data.folder, data.chain, data.limits, control)
