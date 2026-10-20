# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Optimized result/owner guards retain genuine successful source and proof controls.

import std/[assertions, cmdline]
import ../../src/state/[import_inputs, import_justification, extrinsic_inputs]
import ../../src/codec/[work_package, work_report]
import ../../src/pvm/host_fetch
import ../support/[pvm_import_inputs, pvm_import_justification, pvm_import_vectors]

proc check(outcome: ImportInputsResult[VerifiedImportInputs], reason: ImportInputsError) =
  ## Inspect reasons without specializing deliberately invalid runtime value extraction.
  assert outcome.error == reason
let source = inputSource([@[rootImport(SegmentRoot(bytes: ThreeRoot), ImportIndex(0))]])
let rows = [@[inputProof(0)]]
let done = bindImportInputs(source, rows, [], inputLimits())
check(done, ImportInputsError.None)
assert done.value.importInput(FetchItemIndex(0), ImportInputIndex(
    0)).value.verifiedImportInfo.value.root.bytes == ThreeRoot
let missing = default(ImportInputsResult[VerifiedImportInputs])
let invalidSource = bindImportInputs(default(VerifiedExtrinsics), rows, [], inputLimits())
check(invalidSource, ImportInputsError.InvalidSource)
let invalidImport = bindImportInputs(source, [@[default(VerifiedImport)]], [], inputLimits())
check(invalidImport, ImportInputsError.InvalidImport)
let limited = bindImportInputs(source, rows, [], default(ImportInputsLimits))
check(limited, ImportInputsError.LimitExceeded)
let singleton = verifyImportSegment(SegmentRoot(bytes: SingletonRoot), ImportIndex(0),
    importSegment(), [], importLimits()).value
let wrongRoot = bindImportInputs(source, [@[singleton]], [], inputLimits())
check(wrongRoot, ImportInputsError.RootMismatch)
case paramStr(1)
of "default": discard missing.value # Defaults have no successful manifest binding.
of "source": discard invalidSource.value # Unverified extrinsics cannot select a package.
of "import": discard invalidImport.value # Missing proof authority exposes no partial binding.
of "root": discard wrongRoot.value # A valid leaf for another root cannot certify this manifest.
of "limit": discard limited.value # A local policy refusal has no retained prefix.
of "owner": discard default(VerifiedImportInputs).importInputsExtrinsics.value # Defaults cannot supply original extrinsics.
of "lookup": discard default(VerifiedImportInputs).importInputsLookup.value # Defaults cannot manufacture an empty dictionary.
else: discard done.value.importInput(FetchItemIndex(high(uint64)), ImportInputIndex(
    0)).value # Invalid ordinals expose no leaf.
