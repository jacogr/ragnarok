# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

# @@Verification={"arc": "jamnp_assurance_policy_arc_release"}

## Strict complete startup policies reject ambiguous or deficient files before resources open; genuine foreground create/open lifetimes release archive locks and remain disabled without an explicit policy.

import std/[assertions, syncio, strutils, os, dirs, paths, posix/posix]
import ../../../src/app/[node_assurance_policy, options, node_command]
import ../../../src/app/proof/assurance_storage
import ../../../src/app/work_policy/types
import ../../../src/codec/[bounded, header]
import ../../../src/codec/state/safrole
import ../../../src/chain/genesis
import ../../../src/jamnp-s/[connections, node, assurance_store, assurance_record]
import ../../../src/quic/transport
import ../../support/[jamnp_assurance_fixture, jamnp_assurance_policy, current_application_context,
  assurance_signer_context, arc_evidence]

proc processId(): cint {.importc: "getpid", header: "<unistd.h>".}
  ## Separate test-owned paths from any concurrently running independent suite.

proc hex(bytes: array[32, byte]): string =
  ## Independent lower-case fixed-width command finality representation.
  result = ""
  for octet in bytes: result.add(toHex(int(octet), 2).toLowerAscii())

proc refuse(user: pointer, bytes: ptr ConstByte, length: csize_t): cint {.cdecl, raises: [].} =
  ## An ephemeral port reservation accepts no peer or claimed identity.
  0

proc ignore(user: pointer, stream: NativeStream, event: cint) {.cdecl, raises: [].} =
  ## The reservation never polls or owns an application stream.
  discard

proc appended(base, extra: seq[string]): seq[string] =
  ## Independent argument ownership uses supported explicit sequence traversal.
  result = @[]
  for item in base: result.add(item)
  for item in extra: result.add(item)

proc configuration(text: string) =
  ## Whole schema success and representative resource/role refusals exercise the actual strict loader without native activation.
  let parsed = decodeNodeAssurancePolicy(text)
  assert parsed.error == WorkPolicyError.None, "complete assurance policy: " & $parsed.error
  assert parsed.value.valid and parsed.value.storageMode == AssuranceStorageMode.Create,
    "explicit create mode survives complete parsing"
  assert uint64(parsed.value.storageLimits.entries) == 16 and uint64(
      parsed.value.readLimits.batchSources) == 6144,
    "parsed resource bounds reach namespace and batched serving"
  assert not default(NodeAssurancePolicy).valid, "default policy stays disabled"
  assert decodeNodeAssurancePolicy("ragnarok-assurance-policy-v0\n").error ==
      WorkPolicyError.WrongVersion, "assurance policy boundary 44"
  assert decodeNodeAssurancePolicy(text & "mode=1\n").error == WorkPolicyError.DuplicateField, "assurance policy boundary 46"
  assert decodeNodeAssurancePolicy(text & "unrecognized=1\n").error == WorkPolicyError.UnknownField, "assurance policy boundary 47"
  assert decodeNodeAssurancePolicy(text.replace("mode=1\n", "")).error ==
      WorkPolicyError.MissingField, "assurance policy boundary 48"
  assert decodeNodeAssurancePolicy(text.replace("mode=1\n", "mode=01\n")).error ==
      WorkPolicyError.InvalidNumber, "assurance policy boundary 50"
  assert decodeNodeAssurancePolicy(text.replace("mode=1\n", "mode=2\n")).error ==
      WorkPolicyError.InvalidPolicy, "assurance policy boundary 52"
  assert decodeNodeAssurancePolicy(text.replace("broadcastParallel=8\n",
      "broadcastParallel=0\n")).error == WorkPolicyError.InvalidPolicy, "assurance policy boundary 54"
  assert decodeNodeAssurancePolicy(text.replace("storeScanEntries=400\n",
      "storeScanEntries=16\n")).error == WorkPolicyError.InvalidPolicy, "assurance policy boundary 56"
  assert decodeNodeAssurancePolicy(text.replace("signing.shards=1023\n",
      "signing.shards=0\n")).error == WorkPolicyError.InvalidPolicy, "assurance policy boundary 58"
  assert decodeNodeAssurancePolicy(repeat('x', 32769)).error == WorkPolicyError.LimitExceeded, "assurance policy boundary 60"

proc cycle(text: string) =
  ## All detached parsed configuration and child policies retire before each ARC observation.
  let parsed = decodeNodeAssurancePolicy(text)
  assert parsed.error == WorkPolicyError.None and parsed.value.valid, "repeat complete parse"

proc foreground(fixture: AssuranceAcquisitionFixture, text, suffix: string) {.raises.} =
  ## Real complete-state startup owns the actual TLS identity, independent durable directory and explicit chain parameters through joined shutdown.
  var chainFile = "assurance-policy-chain-" & suffix & ".json"
  var policyFile = "assurance-policy-" & suffix & ".txt"
  var key = "assurance-policy-key-" & suffix & ".pem"
  var certificate = "assurance-policy-cert-" & suffix & ".pem"
  let folder = "assurance-policy-store-" & suffix
  let missing = folder & "-missing"
  writeFile(chainFile, currentApplicationText(fixture.source.value))
  writeFile(policyFile, text)
  assuranceSignerFiles(key, certificate, 12)
  removeDir(path(folder))
  removeDir(path(missing))
  defer:
    discard posix.unlink(chainFile.toCString())
    discard posix.unlink(policyFile.toCString())
    discard posix.unlink(key.toCString())
    discard posix.unlink(certificate.toCString())
    removeDir(path(folder))
    removeDir(path(missing))
  var reserve = default(Transport)
  var context = 0
  defer: reserve.closeTransport()
  assert openTransport(reserve, true, false, 0, certificate, key, "jamnp-s/1/00000000",
    addr context, refuse, ignore), "actual ephemeral UDP reservation"
  let port = reserve.localPort
  reserve.closeTransport()
  let base = @["node", "--net-port", $port, "--net-cert", certificate, "--net-key", key,
    "--node-finalized", hex(array[32, byte](fixture.source.value.blockHash)), "--net-timeout-ms", "20",
    "--with-state", "--chain", chainFile]
  var options = default(Options)
  var diagnostic = ""
  assert parseOptions(base, options, diagnostic), diagnostic
  assert runNodeCommand(options) == NodeCommandError.Stopped, "ordinary foreground remains unsigned and archive-free"
  assert not dirExists(folder), "omitted policy creates no namespace"
  assert not parseOptions(appended(base, @["--node-assurance-policy", policyFile]), options), "missing independent directory refused before startup"
  assert not parseOptions(appended(base, @["--node-assurance-store", folder]), options), "directory alone never activates assurance defaults"
  let arguments = appended(base, @["--node-assurance-policy", policyFile, "--node-assurance-store", folder])
  assert parseOptions(arguments, options, diagnostic), diagnostic
  assert options.argumentCount == 10 and options.argument(7).len == 0 and options.argument(8).len == 0,
    "new optional arguments preserve empty ticket/work-policy positions"
  var wrongProfile = assuranceSettings(fixture.source.value)
  wrongProfile.period += 1
  writeFile(policyFile, encodeNodeAssurancePolicy(wrongProfile))
  assert runNodeCommand(options) == NodeCommandError.InvalidAssurancePolicy and not dirExists(folder),
    "actual profile mismatch refuses startup before namespace creation"
  writeFile(policyFile, text)
  let created = runNodeCommand(options)
  assert created == NodeCommandError.Stopped, "real foreground assurance startup: " & $created
  assert dirExists(folder), "explicit create published an independent namespace"
  assert runNodeCommand(options) == NodeCommandError.InvalidAssurancePolicy,
    "explicit create refuses existing namespace rather than reopening it implicitly"
  writeFile(policyFile, encodeNodeAssurancePolicy(assuranceSettings(fixture.source.value, 0)))
  assert runNodeCommand(options) == NodeCommandError.Stopped, "explicit reopen succeeds after exact startup/worker/native retirement"
  assert parseOptions(appended(base, @["--node-assurance-policy", policyFile,
      "--node-assurance-store", missing]), options), "assurance policy boundary 113"
  assert runNodeCommand(options) == NodeCommandError.InvalidAssurancePolicy and not dirExists(missing),
    "open mode never creates a missing namespace"
  writeFile(policyFile, text)
  assuranceSignerFiles(key, certificate, 99)
  assert runNodeCommand(options) == NodeCommandError.InvalidAssurancePolicy and not dirExists(missing),
    "a non-validator TLS identity cannot create an assurance namespace or enable private duties"
  writeFile(policyFile, "ragnarok-assurance-policy-v0\n")
  assert runNodeCommand(options) == NodeCommandError.InvalidAssurancePolicy,
    "invalid file rejected before resource activation"

proc main() {.raises.} =
  ## One genuinely admitted source supplies all structural and executable policy evidence.
  let fixture = assuranceAcquisitionFixture()
  let settings = assuranceSettings(fixture.source.value)
  let text = encodeNodeAssurancePolicy(settings)
  configuration(text)
  assert decodeNodeAssurancePolicy(text).value.matches(settings.topology, settings.period), "actual chain profile accepted"
  assert not decodeNodeAssurancePolicy(text).value.matches(settings.topology, settings.period+1), "different chain clock refused"
  foreground(fixture, text, $processId())
  cycle(text)
  let before = getOccupiedMem()
  for iteration in 0..<1000:
    cycle(text) # Complete positive parsing releases every temporary lexical/candidate allocation.
  let after = getOccupiedMem()
  assert before == after, "assurance policy ARC release"
  recordArcRelease("jamnp_assurance_policy", 1000, before, after)
  echo "JAMNP-S assurance policy passed"
try:
  main()
except:
  quit(2)
