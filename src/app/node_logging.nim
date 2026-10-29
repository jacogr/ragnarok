# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Human-readable node lifecycle observations use the existing application-owned async writer.
import std/strutils
import ./options
import ../lib/logging
import ../version

const
  NodeSystem = when defined(macosx): "macOS" elif defined(linux): "Linux" else: "unknown"
  NodeArchitecture = when defined(arm64): "arm64" elif defined(amd64): "x86_64" else: "unknown"

const NodeStatusIntervalMs* = 5000 ## Monotonic status cadence; no per-loop or per-packet default noise.

proc logRuntimeIdentity*(writer: LogWriter) =
  ## Build/target labels describe this executable, independently of selected runtime services.
  log(writer, LogTarget.Startup, LogLevel.Info, "Ragnarok " & AppVersion & " (" & AppRevision & ")")
  log(writer, LogTarget.Startup, LogLevel.Info, "Platform: " & NodeSystem & "/" & NodeArchitecture &
    "; Nimony " & CompilerVersion)

proc logNodeStartup*(options: Options) =
  ## Report selected capabilities, not authority or finality inferred from a command name.
  let writer = options.logWriter
  logRuntimeIdentity(writer)
  log(writer, LogTarget.Startup, LogLevel.Info, "Role: " & ($options.nodeMode).toUpperAscii &
    "; block production: " & (if options.argumentCount > 1 and options.argument(1) ==
        "tiny-devnet" and
    options.argument(2) == "node": "development authority" else: "disabled"))
  log(writer, LogTarget.Startup, LogLevel.Info, "Data directory: " & options.dataDirectory)
  log(writer, LogTarget.Storage, LogLevel.Info, "Database: " & (if options.diskStorage:
    (if options.pagedStorage: "paged" elif options.managedStorage: "managed" else: "journal") &
        " at " & options.stateDatabase else: (if options.stateEnabled: "memory" else: "disabled")))
  if options.chainPath.len > 0:
    log(writer, LogTarget.Startup, LogLevel.Info, "Chain specification: " & options.chainPath)
  else:
    log(writer, LogTarget.Startup, LogLevel.Info, "Chain specification: unconfigured")

proc logServiceStartup*(options: Options) =
  ## Emit endpoints only after successful service initialization; disabled services claim no listener.
  let writer = options.logWriter
  if options.rpcPort != 0:
    log(writer, LogTarget.Rpc, LogLevel.Info, "RPC listening on ws://127.0.0.1:" &
        $options.rpcPort & "/")
  if options.uiPort != 0:
    log(writer, LogTarget.Startup, LogLevel.Info, "UI listening on http://127.0.0.1:" &
      $options.uiPort &
      "/; assets: " & (if options.devUiDirectory.len > 0: options.devUiDirectory else: "embedded"))
  if options.mcpPort != 0:
    log(writer, LogTarget.Startup, LogLevel.Info, "MCP listening on http://127.0.0.1:" &
        $options.mcpPort & "/mcp")
  if options.managementSocket.len > 0:
    log(writer, LogTarget.Startup, LogLevel.Info, "Management listening on " &
        options.managementSocket)
  if options.telemetryEnabled:
    log(writer, LogTarget.Telemetry, LogLevel.Info, "Telemetry destination: " &
        options.telemetryEndpoint)
