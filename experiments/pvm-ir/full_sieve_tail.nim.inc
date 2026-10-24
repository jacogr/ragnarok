# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared real-guest comparison tail; pricing controls distinguish existing API gains from prepared code.
let engine = getEnv("PVM_SIEVE_ENGINE")
let requestedSamples = getEnv("PVM_SIEVE_SAMPLES")
let samples = if requestedSamples == "3": 3 else: 13
let preparationWall = getMonoTime().ticks
let preparationCpu = cpuNanoseconds()
when defined(FullMasterLazy):
  let capturedPolicy = newGasMemo(owner, GasMemoLimits(bytes: GasMemoByteLimit(16 * 1024 * 1024),
    cycles: GasCycleLimit(1000000)))
  assert capturedPolicy.error == GasMemoError.None
  let policy = capturedPolicy.value
  let payload = gasMemoInfo(policy).value.payloadBytes
elif defined(FullMasterComplete):
  let capturedPolicy = newGasPlan(owner, GasPlanLimits(bytes: GasPlanByteLimit(16 * 1024 * 1024),
    blocks: GasPlanBlockLimit(65535), cycles: GasCycleLimit(1000000)))
  assert capturedPolicy.error == GasPlanError.None
  let policy = capturedPolicy.value
  let payload = gasPlanInfo(policy).value.payloadBytes
else:
  when defined(FullComplete):
    let capture = prepared.prepareExecution(owner, prepared.defaultPreparedLimits(
        prepared.PricingMode.Complete))
  else:
    let capture = prepared.prepareExecution(owner, prepared.defaultPreparedLimits(
        prepared.PricingMode.Lazy))
  assert capture.error == prepared.PreparedError.None
  let code = capture.value
  let binding = prepared.bindPrepared(code, source)
  assert binding.error == prepared.PreparedError.None
  let invocation = binding.value
  let payload = prepared.preparedInfo(code).value.payloadBytes
let preparationCpuElapsed = cpuNanoseconds() - preparationCpu
let preparationWallElapsed = getMonoTime().ticks - preparationWall
echo "PREP,", limit, ",", preparationWallElapsed, ",", preparationCpuElapsed, ",", payload
for sample in 0..<samples:
  # All engines exclude fixture loading and input binding; lazy first-cold learning stays inside execution.
  let wallStart = getMonoTime().ticks
  let cpuStart = cpuNanoseconds()
  when defined(FullMasterLazy) or defined(FullMasterComplete):
    let done = reference.execute(source, reference.ExecutionStepLimit(1000000000), policy)
  else:
    let done = prepared.executePrepared(invocation, prepared.ExecutionStepLimit(1000000000))
  let cpuElapsed = cpuNanoseconds() - cpuStart
  let elapsed = getMonoTime().ticks - wallStart
  when defined(FullMasterLazy) or defined(FullMasterComplete):
    assert done.error == reference.StepError.None and done.value.exit == reference.StepExit.Halt
  else:
    assert done.error == prepared.StepError.None and done.value.exit == prepared.StepExit.Halt
  check(done.value.machine, indices, access, expected, limit)
  checkMemory(memory, indices, access, originalBytes, 0)
  let original = machineInfo(source).value
  assert uint64(original.pc) == entry and uint64(original.gas) == uint64(info.gas)
  assert not original.blockCharged
  for i in 0..<13: assert uint64(original.registers[i]) == uint64(info.registers[i])
  echo "SIEVE,", engine, ",", limit, ",", sample, ",", elapsed, ",", cpuElapsed
when defined(FullMasterLazy):
  let final = gasMemoInfo(policy).value
  echo "FACTS,", final.codeBytes, ",", final.payloadBytes, ",", final.pricedBlocks
elif defined(FullMasterComplete):
  let final = gasPlanInfo(policy).value
  echo "FACTS,", final.codeBytes, ",", final.payloadBytes, ",", final.blockCount
else:
  let final = prepared.preparedInfo(code).value
  echo "FACTS,", final.codeBytes, ",", final.payloadBytes, ",", final.pricedBlocks
