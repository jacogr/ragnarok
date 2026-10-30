# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Explicit application-owned diagnostic logging: immutable filters and one bounded native writer.
## Producers never wait for the queue or perform output IO. Close joins after all producers retire;
## draining close can wait for a blocked output sink. Handles borrow their fixed-address owner.
import std/[assertions, strutils, locks, rawthreads, atomics, times]

type
  LogLevel* {.pure.} = enum ## Increasing verbosity; Off admits no records.
    Off = "off", Fatal = "fatal", Error = "error", Warn = "warn", Info = "info",
      Debug = "debug", Trace = "trace"
  LogTarget* {.pure.} = enum ## Shared component names are independent of CLI or protocol state.
    Startup = "startup", Pvm = "pvm", Telemetry = "telemetry", Rpc = "rpc",
      Network = "network", Storage = "storage", Application = "app"
  LogPolicy* = object ## Fixed-size immutable filters are copied before any worker starts.
    levels: array[LogTarget, LogLevel]
  LogSink* = proc(context: nil pointer, batch: string) {.nimcall, raises: [].}
    ## Borrow one bounded batch synchronously; never retain bytes, raise, close or restart the logger.

const
  DefaultLogLevel* = LogLevel.Info ## One application-default threshold also displayed by CLI help.
  LogQueueCapacity* = 256          ## Fixed records, independent of guest rate or sink latency.
  LogRecordBytes* = 2048           ## Includes timestamp, level, component, escaped message and newline.
  LogBatchRecords = 16

type
  LogRecord = object ## Plain owned bytes cross threads; no ARC graph or borrowed guest storage.
    used: int
    bytes: array[LogRecordBytes, char]
  Logger* = object ## Noncopyable final-address owner, explicitly joined before destruction.
    lock: Lock
    changed: Cond
    thread: RawThread
    started, stopping, running: bool
    epoch: uint64
    policy: LogPolicy
    sink: nil LogSink
    context: nil pointer
    head, count: int
    queue: array[LogQueueCapacity, LogRecord]
    accepted, dropped, processed, batches: uint64
  LogWriter* = object ## Borrow valid only while its started owner and sink context remain alive.
    owner: nil ptr Logger
    epoch: uint64
  LogStats* = object ## Relaxed diagnostic counters wrap modulo2^64; they grant no protocol authority.
    accepted*, dropped*, processed*, batches*: uint64

proc `=copy`*(destination: var Logger, source: Logger) {.error.}
  ## A running worker borrows one fixed address, never a copied queue or lock.

proc `=dup`*(source: Logger): Logger {.error.}
  ## A container cannot duplicate the native lifetime indirectly.

proc requireClosed(logger: Logger) {.requires: not logger.started.} =
  ## Callers must join while producers, borrowed handles and sink context still exist.
  discard

proc `=destroy`*(logger: Logger) =
  ## Explicit close owns native cleanup; default and already-closed values own no worker.
  requireClosed(logger)

proc `=wasMoved`*(logger: var Logger) {.nodestroy, inline, requires: not logger.started.} =
  ## Moving a live owner would invalidate the worker address; only closed values may move.
  logger.started = false
  logger.running = false

func initLogPolicy*(level = DefaultLogLevel): LogPolicy =
  ## Default application verbosity includes fatal, error, warning and informational records.
  result = default(LogPolicy)
  for index in 0..ord(high(LogTarget)): result.levels[index] = level

func threshold*(policy: LogPolicy, target: LogTarget): LogLevel =
  ## Inspect one immutable component threshold without granting mutation.
  policy.levels[ord(target)]

proc parseLevel(text: string, level: var LogLevel): bool =
  ## Exact spellings avoid silently enabling unexpectedly verbose diagnostics.
  level = LogLevel.Off
  for ordinal in 0..ord(high(LogLevel)):
    let value = LogLevel(ordinal)
    if text == $value:
      level = value
      return true
  false

proc parseLogPolicy*(text: string, policy: var LogPolicy): bool =
  ## Parse global-first or target-only filters atomically, e.g. info,pvm=debug,network=warn.
  policy = default(LogPolicy)
  if text.len == 0 or text.len > 512: return false
  var candidate = initLogPolicy()
  var seen = default(array[LogTarget, bool])
  var globalSeen = false
  var targetSeen = false
  for part in text.split(','):
    let separator = part.find('=')
    var level = LogLevel.Off
    if separator < 0:
      if globalSeen or targetSeen or not parseLevel(part, level): return false
      candidate = initLogPolicy(level)
      globalSeen = true
    else:
      if separator == 0 or separator == part.len-1: return false
      if not parseLevel(part.substr(separator+1), level): return false
      var found = false
      for ordinal in 0..ord(high(LogTarget)):
        let target = LogTarget(ordinal)
        if part.substr(0, separator-1) == $target:
          if seen[ord(target)]: return false
          seen[ord(target)] = true
          candidate.levels[ord(target)] = level
          found = true
      if not found: return false
      targetSeen = true
  policy = candidate
  true

func shortHash*(hash: array[32, byte]): string =
  ## A bounded display abbreviation retains both ends; it is never a protocol identifier.
  const digits = "0123456789abcdef"
  result = "0x"
  for index in 0..<4:
    result.add(digits[int(hash[index] shr 4)]); result.add(digits[int(hash[index] and 15)])
  result.add("...")
  for index in 28..<32:
    result.add(digits[int(hash[index] shr 4)]); result.add(digits[int(hash[index] and 15)])

func active*(logger: Logger): bool =
  ## Lifecycle checks permit safe diagnostics at process failure boundaries before/after startup.
  logger.started

func configured*(writer: LogWriter): bool =
  ## Default handles select no shared application sink.
  writer.owner != nil

func enabled*(writer: LogWriter, target: LogTarget, level: LogLevel): bool =
  ## Filter only immutable policy before formatting, locking or guest reads.
  let owner = writer.owner
  if owner == nil: return false
  owner.started and owner.epoch == writer.epoch and level != LogLevel.Off and ord(level) <= ord(
      owner.policy.levels[ord(target)])

proc append(record: var LogRecord, text: string) =
  ## Internal bounded literal/header construction never writes beyond one complete record.
  for character in text:
    if record.used < LogRecordBytes:
      record.bytes[record.used] = character
      inc record.used

type Calendar {.importc: "struct tm", header: "<time.h>", bycopy.} = object
  ## libc owns the complete platform layout; conversion writes only worker-independent local storage.
  tm_sec, tm_min, tm_hour, tm_mday, tm_mon, tm_year, tm_wday, tm_yday, tm_isdst: cint

proc utcTime(seconds: ptr clong, calendar: ptr Calendar): nil ptr Calendar {.
    importc: "gmtime_r", header: "<time.h>".}
  ## Thread-safe UTC conversion never reads process timezone state.

proc formatTime(output: ptr char, capacity: csize_t, pattern: cstring,
    calendar: ptr Calendar): csize_t {.importc: "strftime", header: "<time.h>".}
  ## Bound native date formatting to caller-owned bytes.

proc timestamp(): string =
  ## Capture event time before queueing; disabled records never query the wall clock.
  var seconds = clong(getTime().toUnix)
  var calendar = default(Calendar)
  var buffer = default(array[32, char])
  if utcTime(addr seconds, addr calendar) == nil: return "[time unavailable] "
  let length = formatTime(addr buffer[0], csize_t(buffer.len), "%Y-%m-%d %H:%M:%SZ", addr calendar)
  if length == 0 or length >= csize_t(buffer.len): return "[time unavailable] "
  result = ""
  for index in 0..<int(length): result.add(buffer[index])
  result.add(' ')

proc encode(target: LogTarget, level: LogLevel, message: string): LogRecord =
  ## Escape guest/remote controls, preserve one physical line and visibly truncate within the cap.
  const hex = "0123456789abcdef"
  const suffix = "...[truncated]"
  result = default(LogRecord)
  append(result, timestamp())
  append(result, "[" & $level & "][" & $target & "] ")
  var index = 0
  while index < message.len:
    let octet = byte(message[index])
    let needed = if octet >= 32 and octet <= 126: 1 else: 4
    if result.used > LogRecordBytes-1-suffix.len-needed:
      append(result, suffix)
      break
    if needed == 1:
      result.bytes[result.used] = char(octet)
      inc result.used
    else:
      append(result, "\\x")
      result.bytes[result.used] = hex[int(octet shr 4)]
      inc result.used
      result.bytes[result.used] = hex[int(octet and 15)]
      inc result.used
    inc index
  append(result, "\n")

proc submitLog*(writer: LogWriter, target: LogTarget, level: LogLevel,
    message: string): bool {.raises: [].} =
  ## Acceptance copies one bounded record; busy/full queues drop rather than wait for a sink.
  if not enabled(writer, target, level): return false
  let owner = writer.owner
  assert owner != nil
  let record = encode(target, level, message)
  if not tryAcquire(owner.lock):
    discard atomicFetchAdd(owner.dropped, 1'u64, moRelaxed)
    return false
  if owner.stopping or owner.count == LogQueueCapacity:
    release(owner.lock)
    discard atomicFetchAdd(owner.dropped, 1'u64, moRelaxed)
    return false
  let slot = (owner.head+owner.count) mod LogQueueCapacity
  owner.queue[slot] = record
  inc owner.count
  discard atomicFetchAdd(owner.accepted, 1'u64, moRelaxed)
  signal(owner.changed)
  release(owner.lock)
  true

template log*(writer, target, level, message: untyped) =
  ## Disabled records never evaluate message expressions or allocate formatted strings.
  block:
    let current = writer
    let selectedTarget = target
    let selectedLevel = level
    if enabled(current, selectedTarget, selectedLevel):
      discard submitLog(current, selectedTarget, selectedLevel, message)

proc diagnosticWrite(fd: cint, data: pointer, size: csize_t): int
    {.importc: "write", header: "<unistd.h>", raises: [].}
  ## POSIX byte output avoids sharing the native runtime stderr object's mutable ARC state.

proc stderrSink(context: nil pointer, batch: string) {.raises: [].} =
  ## Only the worker performs output; partial writes retry, OS failures discard the remaining bytes.
  var offset = 0
  while offset < batch.len:
    # This immutable batch stays alive and unmoved throughout the synchronous borrowed byte read.
    let count = diagnosticWrite(2, readRawData(batch, offset), csize_t(batch.len-offset))
    if count <= 0 or count > batch.len-offset: return # Diagnostics never become protocol errors.
    offset += count

proc run(raw: pointer) =
  ## Condition-driven consumer copies a bounded batch under lock, then releases it before IO.
  let owner = cast[ptr Logger](raw)
  while true:
    var records = default(array[LogBatchRecords, LogRecord])
    acquire(owner.lock)
    while owner.count == 0 and not owner.stopping: wait(owner.changed, owner.lock)
    if owner.count == 0 and owner.stopping:
      release(owner.lock)
      let lost = atomicLoad(owner.dropped, moRelaxed)
      if lost > 0 and ord(owner.policy.levels[ord(LogTarget.Startup)]) >= ord(LogLevel.Warn):
        let sink = owner.sink
        assert sink != nil
        let warning = encode(LogTarget.Startup, LogLevel.Warn, "logging dropped=" & $lost)
        var text = ""
        for index in 0..<warning.used: text.add(warning.bytes[index])
        sink(owner.context, text)
      return
    let taken = min(owner.count, LogBatchRecords)
    for index in 0..<taken:
      records[index] = owner.queue[owner.head]
      owner.head = (owner.head+1) mod LogQueueCapacity
    owner.count -= taken
    release(owner.lock)
    var batch = newStringOfCap(taken*LogRecordBytes)
    for index in 0..<taken:
      let record = records[index]
      for at in 0..<record.used: batch.add(record.bytes[at])
    let sink = owner.sink
    assert sink != nil
    sink(owner.context, batch)
    discard atomicFetchAdd(owner.processed, uint64(taken), moRelaxed)
    discard atomicFetchAdd(owner.batches, 1'u64, moRelaxed)

proc start*(logger: var Logger, policy: LogPolicy, sink: LogSink = stderrSink,
    context: nil pointer = nil): bool {.raises: [].} =
  ## Initialize at its final address; failure creates no live borrower and releases synchronization.
  if logger.started or logger.epoch == high(uint64): return false
  inc logger.epoch # Never recycle a retired producer generation.
  logger.running = false
  logger.policy = policy
  logger.sink = sink
  logger.context = context
  logger.stopping = false
  logger.head = 0
  logger.count = 0
  atomicStore(logger.accepted, 0'u64, moRelaxed)
  atomicStore(logger.dropped, 0'u64, moRelaxed)
  atomicStore(logger.processed, 0'u64, moRelaxed)
  atomicStore(logger.batches, 0'u64, moRelaxed)
  initLock(logger.lock)
  initCond(logger.changed)
  var active = false
  for level in logger.policy.levels:
    if level != LogLevel.Off: active = true
  if not active:
    logger.started = true # Fully disabled logging creates no writer thread.
    return true
  try:
    logger.thread.create(run, addr logger)
  except:
    deinitCond(logger.changed)
    deinitLock(logger.lock)
    return false # Logging setup failure starts no borrower and exposes no half-initialized owner.
  logger.running = true
  logger.started = true
  true

proc writer*(logger: var Logger): LogWriter {.requires: logger.started.} =
  ## Borrow one immutable-policy producer handle; retire every handle before close returns.
  LogWriter(owner: addr logger, epoch: logger.epoch)

proc stats*(logger: var Logger): LogStats =
  ## Read lifetime totals without locking; processed means sink invocation, not durable output.
  LogStats(accepted: atomicLoad(logger.accepted, moRelaxed),
    dropped: atomicLoad(logger.dropped, moRelaxed),
    processed: atomicLoad(logger.processed, moRelaxed),
    batches: atomicLoad(logger.batches, moRelaxed))

proc close*(logger: var Logger) =
  ## After producers retire, drain accepted records and join before the sink context can disappear.
  ## The queue is bounded; sink IO itself may block and therefore delay this explicit drain.
  if not logger.started: return
  acquire(logger.lock)
  logger.stopping = true
  signal(logger.changed)
  release(logger.lock)
  if logger.running: logger.thread.join()
  deinitCond(logger.changed)
  deinitLock(logger.lock)
  logger.started = false
  logger.running = false
