# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Shared CLI catalog: option classification, presentation order and application defaults.
## Parser and help consume the same records; command-specific values are normalized before service parsing.

import std/strutils
import ../../lib/logging

import ./defaults as cli_defaults
export cli_defaults

type
  OptionGroup* {.pure.} = enum ## Ordered help sections keep activation flags beside their dependent settings.
    General, PVM, Network, Ui, Rpc, Mcp, Management, Telemetry, State, Storage, Recovery, Download,
      Trace, Devnet, Fuzz
  OptionDefault* {.pure.} = enum ## A default references its single typed definition instead of duplicating display strings.
    Required, None, Disabled, Embedded, ChainFile, RpcPort, McpPort, UiPort, Timeout, PeerMode,
      Mode, Storage,
    Layout, Writes, WriteBytes, Environment, FuzzWrites, FuzzWriteBytes, CompactBytes, Blocks,
      Logging, PvmBackend, DataDirectory, NetworkPort, Certificate, PrivateKey, PeerKey, Alpn,
        Database, ManagementPath, RetainedBlocks
  OptionSpec* = object ## Immutable catalog row; an empty commands string denotes shared service controls.
    name*, value*, description*, commands*: string
    fallback*: OptionDefault
    group*: OptionGroup
    repeatable*: bool
  CommandSpec* = object ## One discoverable command topic, including explicit development subcommands.
    name*, description*: string

const
  BoundedTimeoutDescription = "Bounded workloads default to " & $DefaultTimeoutMs & " ms."
  TimeoutOverview = $DefaultServerTimeoutMs & "/" & $DefaultTimeoutMs
  OptionGroups* = [
    "General",
    "PVM",
    "Network and TLS",
    "Browser UI",
    "WebSocket RPC",
    "Agent MCP",
    "Local management",
    "Telemetry",
    "State execution",
    "State storage",
    "Checkpoint import and light trust",
    "Block downloads",
    "Offline trace checking",
    "Local development network",
    "Conformance testing"
  ]
  CommandSpecs* = [
    CommandSpec(name: "server", description: "Run a foreground listener, or select a bounded workload."),
    CommandSpec(name: "client", description: "Run a bounded client workload."),
    CommandSpec(name: "mesh", description: "Run a retained two-way peer workload."),
    CommandSpec(name: "download", description: "Download and adopt sealed children using an explicit policy."),
    CommandSpec(name: "sync-current", description: "Continuously discover and execute canonical children until interrupted."),
    CommandSpec(name: "download-current", description: "Download and execute children using a current download policy."),
    CommandSpec(name: "history", description: "Read an existing full database block/state; optionally export its checkpoint."),
    CommandSpec(name: "check-traces", description: "Validate consecutive trace files against an explicit Genesis."),
    CommandSpec(name: "tiny-devnet init", description: "Write a tiny chain JSON file."),
    CommandSpec(name: "tiny-devnet identity", description: "Print one development validator identity."),
    CommandSpec(name: "tiny-devnet node", description: "Run one bounded local development validator."),
    CommandSpec(name: "fuzz", description: "Run conformance with built-in policy (also activated by JAM_FUZZ)."),
    CommandSpec(name: "serve-fuzz", description: "Run conformance with explicit policy and parameter files."),
    CommandSpec(name: "serve-fuzz-preset", description: "Run conformance with explicit policy and the environment preset.")
  ]
  OptionSpecs* = [
    OptionSpec(name: "--data-dir", value: "DIR", group: OptionGroup.General,
      description: "Persistent identity and default database root.",
      fallback: OptionDefault.DataDirectory),
    # General options. Keep additions in this group.
    OptionSpec(name: "--chain", value: "FILE", group: OptionGroup.General,
      description: "Shared chain JSON for state, RPC and telemetry; used when state/telemetry is enabled.",
      fallback: OptionDefault.ChainFile,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--log-level", value: "FILTER", group: OptionGroup.General,
      description: "off|fatal|error|warn|info|debug|trace; optional target=level filters.",
      fallback: OptionDefault.Logging, commands: "",
      repeatable: false),

    # PVM options. Keep additions in this group.
    OptionSpec(name: "--pvm-backend", value: "MODE", group: OptionGroup.PVM,
      description: "jit|interpreted|polkavm-interpreted|polkavm-compiled; jit uses interpreted fallback.",
      fallback: OptionDefault.PvmBackend, commands: "", repeatable: false),

    OptionSpec(name: "--pvm-code", value: "FILE", group: OptionGroup.PVM,
      description: "Execute a standalone JamV1 .polkavm artifact.",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--pvm-entry", value: "NAME", group: OptionGroup.PVM,
      description: "Artifact export to execute (default: main); requires --pvm-code.",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--pvm-gas", value: "NUMBER", group: OptionGroup.PVM,
      description: "Artifact gas budget, 1..1000000000000 (default: 10000000).",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--pvm-steps", value: "NUMBER", group: OptionGroup.PVM,
      description: "Artifact instruction budget, 1..1000000000 (default: 10000000).",
      fallback: OptionDefault.None, commands: "", repeatable: false),

    # Network and TLS options. Keep additions in this group.
    OptionSpec(name: "--net-port", value: "NUMBER", group: OptionGroup.Network,
      description: "Peer port (1..65535).", fallback: OptionDefault.NetworkPort,
      commands: "server|client|download|download-current|sync-current",
      repeatable: false),
    OptionSpec(name: "--net-local-port", value: "NUMBER", group: OptionGroup.Network,
      description: "Local mesh listener port.", fallback: OptionDefault.NetworkPort,
      commands: "mesh",
      repeatable: false),
    OptionSpec(name: "--net-remote-port", value: "NUMBER", group: OptionGroup.Network,
      description: "Remote mesh peer port.", fallback: OptionDefault.NetworkPort,
      commands: "mesh",
      repeatable: false),
    OptionSpec(name: "--net-cert", value: "FILE", group: OptionGroup.Network,
      description: "TLS certificate PEM; generated and reused with the default private key.",
      fallback: OptionDefault.Certificate,
      commands: "server|client|mesh|download|download-current|sync-current",
      repeatable: false),
    OptionSpec(name: "--net-key", value: "FILE", group: OptionGroup.Network,
      description: "TLS private key PEM; generated privately and reused across starts.",
      fallback: OptionDefault.PrivateKey,
      commands: "server|client|mesh|download|download-current|sync-current",
      repeatable: false),
    OptionSpec(name: "--net-peer-key", value: "FILE", group: OptionGroup.Network,
      description: "Pinned remote identity; required for dialers; server discovers valid identities.",
      fallback: OptionDefault.PeerKey, commands: "server|client|mesh|download|download-current|sync-current",
      repeatable: false),
    OptionSpec(name: "--net-local-key", value: "FILE", group: OptionGroup.Network,
      description: "Local mesh identity file; required.", fallback: OptionDefault.Required,
      commands: "mesh",
      repeatable: false),
    OptionSpec(name: "--net-alpn", value: "NAME", group: OptionGroup.Network,
      description: "JAM network protocol name; override the isolated development domain for a real network.",
      fallback: OptionDefault.Alpn, commands: "server|client|mesh|download|download-current|sync-current",
      repeatable: false),
    OptionSpec(name: "--net-timeout-ms", value: "MILLISECONDS", group: OptionGroup.Network,
      description: "Listen: 0 means unlimited. " & BoundedTimeoutDescription,
      fallback: OptionDefault.Timeout, commands: "server|client|download|download-current|sync-current",
      repeatable: false),
    OptionSpec(name: "--net-mode", value: "NAME", group: OptionGroup.Network,
      description: "Peer workload mode; see command notes.", fallback: OptionDefault.PeerMode,
      commands: "server|client",
      repeatable: false),
    OptionSpec(name: "--net-gate", value: "FILE", group: OptionGroup.Network,
      description: "Mesh readiness gate path; required.", fallback: OptionDefault.Required,
      commands: "mesh",
      repeatable: false),
    OptionSpec(name: "--net-peer", value: "PORT:KEY_FILE", group: OptionGroup.Network,
      description: "Additional pinned peer; repeat in order (at most " & $(MaxDownloadPeers-1) &
          ").", fallback: OptionDefault.None, commands: "download|download-current|sync-current",
      repeatable: true),

    # Browser UI options. Keep additions in this group.
    OptionSpec(name: "--with-ui", value: "", group: OptionGroup.Ui,
      description: "Enable the browser UI and its RPC listener.", fallback: OptionDefault.Disabled,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--ui-port", value: "NUMBER", group: OptionGroup.Ui,
      description: "Loopback HTTP port (1..65535).", fallback: OptionDefault.UiPort, commands: "",
      repeatable: false),
    OptionSpec(name: "--ui-dev-dir", value: "DIRECTORY", group: OptionGroup.Ui,
      description: "Serve development assets from this directory.",
      fallback: OptionDefault.Embedded, commands: "",
      repeatable: false),

    # WebSocket RPC options. Keep additions in this group.
    OptionSpec(name: "--with-rpc", value: "", group: OptionGroup.Rpc,
      description: "Enable the WebSocket RPC listener independently.",
      fallback: OptionDefault.Disabled, commands: "",
      repeatable: false),
    OptionSpec(name: "--rpc-port", value: "NUMBER", group: OptionGroup.Rpc,
      description: "Loopback WebSocket port (1..65535); must differ from UI.",
      fallback: OptionDefault.RpcPort, commands: "",
      repeatable: false),

    # Agent queries are independently optional and share no privileged registry.
    OptionSpec(name: "--with-mcp", value: "", group: OptionGroup.Mcp,
      description: "Enable read-only MCP queries over loopback HTTP.",
      fallback: OptionDefault.Disabled, commands: "", repeatable: false),
    OptionSpec(name: "--mcp-port", value: "NUMBER", group: OptionGroup.Mcp,
      description: "Loopback MCP port (1..65535); must differ from enabled RPC/UI.",
      fallback: OptionDefault.McpPort, commands: "", repeatable: false),

    # Local management options. Keep additions in this group.
    OptionSpec(name: "--with-management", value: "", group: OptionGroup.Management,
      description: "Enable local management; omitted socket resolves under --data-dir.",
      fallback: OptionDefault.Disabled, commands: "",
      repeatable: false),
    OptionSpec(name: "--management-socket", value: "PATH", group: OptionGroup.Management,
      description: "Absolute socket path in an owned private directory.",
      fallback: OptionDefault.ManagementPath, commands: "",
      repeatable: false),

    # Telemetry options. Keep additions in this group.
    OptionSpec(name: "--with-telemetry", value: "", group: OptionGroup.Telemetry,
      description: "Enable telemetry; requires --telemetry-endpoint and --chain.",
      fallback: OptionDefault.Disabled, commands: "",
      repeatable: false),
    OptionSpec(name: "--telemetry-endpoint", value: "HOST:PORT", group: OptionGroup.Telemetry,
      description: "Explicit telemetry collector address.", fallback: OptionDefault.None,
      commands: "",
      repeatable: false),

    # State execution options. Keep additions in this group.
    OptionSpec(name: "--with-state", value: "", group: OptionGroup.State,
      description: "Enable state; requires --chain.", fallback: OptionDefault.Disabled,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--state-mode", value: "full|light", group: OptionGroup.State,
      description: "Light requires --state-trust and --state-header.", fallback: OptionDefault.Mode,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--state-writes", value: "COUNT", group: OptionGroup.State,
      description: "Maximum writes per batch; zero is permitted.", fallback: OptionDefault.Writes,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--state-write-bytes", value: "BYTES", group: OptionGroup.State,
      description: "Maximum value bytes written per batch; zero is permitted.",
      fallback: OptionDefault.WriteBytes, commands: "",
      repeatable: false),

    # State storage options. Keep additions in this group.
    OptionSpec(name: "--retain-blocks", value: "N", group: OptionGroup.Storage,
      description: "Positive accepted block/state count including head; -1 selects archive. Full state only.",
      fallback: OptionDefault.RetainedBlocks, commands: "", repeatable: false),
    OptionSpec(name: "--archive", value: "", group: OptionGroup.Storage,
      description: "Keep every future accepted full block/state; conflicts with --retain-blocks.",
      fallback: OptionDefault.Disabled, commands: "", repeatable: false),
    OptionSpec(name: "--history-block", value: "HASH", group: OptionGroup.Storage,
      description: "history only: exact 64-digit lowercase header hash; select this or --history-ordinal.",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--history-ordinal", value: "NUMBER", group: OptionGroup.Storage,
      description: "history only: positive local acceptance ordinal (not slot or global height).",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--history-checkpoint", value: "FILE", group: OptionGroup.Storage,
      description: "history only: atomically export the selected complete-state checkpoint (16 MiB cap).",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--state-storage", value: "memory|disk", group: OptionGroup.Storage,
      description: "Disk requires --with-state; omitted database paths resolve under --data-dir.",
      fallback: OptionDefault.Storage,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--state-db", value: "PATH", group: OptionGroup.Storage,
      description: "Database path; defaults separate full/light nodes and physical layouts.",
      fallback: OptionDefault.Database,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--state-layout", value: "journal|managed|paged", group: OptionGroup.Storage,
      description: "Disk layout; defaults to journal for full nodes, paged for light nodes.",
      fallback: OptionDefault.Layout, commands: "",
      repeatable: false),
    OptionSpec(name: "--state-paged-resume", value: "", group: OptionGroup.Storage,
      description: "Explicitly resume interrupted paged storage.", fallback: OptionDefault.Disabled,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--state-compact-bytes", value: "BYTES", group: OptionGroup.Storage,
      description: "Managed layout only; 0 disables automatic maintenance (max " &
      $MaximumCompactionBytes & ").", fallback: OptionDefault.CompactBytes, commands: "",
      repeatable: false),
    OptionSpec(name: "--state-migrate-from", value: "PATH", group: OptionGroup.Storage,
      description: "Managed layout only; source must differ from the new --state-db.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),

    # Checkpoint import and light trust options. Keep additions in this group.
    OptionSpec(name: "--state-checkpoint", value: "FILE", group: OptionGroup.Recovery,
      description: "Full-state import; requires trust, header and byte limit.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),
    OptionSpec(name: "--state-trust", value: "FILE", group: OptionGroup.Recovery,
      description: "Independent trusted identity for import or light state.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),
    OptionSpec(name: "--state-header", value: "FILE", group: OptionGroup.Recovery,
      description: "Independent sealed header for import or light state.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),
    OptionSpec(name: "--state-checkpoint-bytes", value: "BYTES", group: OptionGroup.Recovery,
      description: "Explicit full-checkpoint import ceiling; required for import.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),

    # Block downloads options. Keep additions in this group.
    OptionSpec(name: "--sync-source-age-ms", value: "MILLISECONDS", group: OptionGroup.Download,
      description: "Maximum age of actual peer head evidence for sync-current; default 30000.",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--sync-reconnect-ms", value: "MILLISECONDS", group: OptionGroup.Download,
      description: "Delay before replacing an unavailable sync-current source; default 5000.",
      fallback: OptionDefault.None, commands: "", repeatable: false),
    OptionSpec(name: "--download-policy", value: "FILE", group: OptionGroup.Download,
      description: "Explicit versioned download policy; required.",
      fallback: OptionDefault.Required,
      commands: "download|download-current|sync-current"),
    OptionSpec(name: "--download-blocks", value: "COUNT", group: OptionGroup.Download,
      description: "Successive adoptions (1.." & $MaxDownloadBlocks & ").",
      fallback: OptionDefault.Blocks, commands: "",
      repeatable: false),
    OptionSpec(name: "--download-ancestor", value: "FILE", group: OptionGroup.Download,
      description: "Ancestor headers, newest first; repeat (at most " & $MaxDownloadAncestors &
      ").", fallback: OptionDefault.None, commands: "",
      repeatable: true),
    OptionSpec(name: "--download-local-ancestors", value: "", group: OptionGroup.Download,
      description: "Prepend retained local parent headers.", fallback: OptionDefault.Disabled,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--download-remote-ancestors", value: "COUNT", group: OptionGroup.Download,
      description: "Fetch older parents up front (1.." & $MaxDownloadAncestors & ").",
      fallback: OptionDefault.Disabled, commands: "",
      repeatable: false),
    OptionSpec(name: "--download-discover-ancestors", value: "COUNT", group: OptionGroup.Download,
      description: "Discover parents on demand (1.." & $MaxDownloadAncestors &
      "); alternative to remote ancestors.", fallback: OptionDefault.Disabled, commands: "",
      repeatable: false),
    OptionSpec(name: "--download-logical-source", value: "FILE", group: OptionGroup.Download,
      description: "Current full-state downloads; requires --download-logical-policy.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),
    OptionSpec(name: "--download-logical-policy", value: "FILE", group: OptionGroup.Download,
      description: "Separate bounded logical-source resource policy.", fallback: OptionDefault.None,
      commands: "",
      repeatable: false),
    OptionSpec(name: "--download-namespace-policy", value: "FILE", group: OptionGroup.Download,
      description: "Optional namespace policy for a paired logical source.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),
    OptionSpec(name: "--download-update-logical-source", value: "", group: OptionGroup.Download,
      description: "Update the qualified logical source after actual adoption.",
      fallback: OptionDefault.Disabled, commands: "",
      repeatable: false),

    # Offline trace checking options. Keep additions in this group.
    OptionSpec(name: "--trace-policy", value: "FILE", group: OptionGroup.Trace,
      description: "Current execution policy for offline trace checking; required.",
      fallback: OptionDefault.Required,
      commands: "check-traces"),
    OptionSpec(name: "--trace-genesis", value: "FILE", group: OptionGroup.Trace,
      description: "Independently selected Genesis bytes; required.",
      fallback: OptionDefault.Required, commands: "check-traces",
      repeatable: false),
    OptionSpec(name: "--trace-file", value: "FILE", group: OptionGroup.Trace,
      description: "Consecutive trace steps; repeat in execution order (1.." & $MaxTraceSteps &
      ").", fallback: OptionDefault.Required, commands: "check-traces",
      repeatable: true),
    OptionSpec(name: "--trace-observations", value: "DIRECTORY", group: OptionGroup.Trace,
      description: "Compare step-0000.bin and following published RawState files.",
      fallback: OptionDefault.None, commands: "",
      repeatable: false),

    # Local development network options. Keep additions in this group.
    OptionSpec(name: "--devnet-policy", value: "FILE", group: OptionGroup.Devnet,
      description: "Current execution policy for the development validator; required.",
      fallback: OptionDefault.Required,
      commands: "tiny-devnet node"),
    OptionSpec(name: "--devnet-output", value: "FILE", group: OptionGroup.Devnet,
      description: "Destination chain JSON file; required.", fallback: OptionDefault.Required,
      commands: "tiny-devnet init",
      repeatable: false),
    OptionSpec(name: "--devnet-dir", value: "DIRECTORY", group: OptionGroup.Devnet,
      description: "Development network data directory; required.",
      fallback: OptionDefault.Required, commands: "tiny-devnet node",
      repeatable: false),
    OptionSpec(name: "--devnet-index", value: "NUMBER", group: OptionGroup.Devnet,
      description: "Development validator index (0..5); required.",
      fallback: OptionDefault.Required, commands: "tiny-devnet identity|tiny-devnet node",
      repeatable: false),
    OptionSpec(name: "--devnet-base-port", value: "NUMBER", group: OptionGroup.Devnet,
      description: "First development listener port (1024..65530); required.",
      fallback: OptionDefault.Required, commands: "tiny-devnet node",
      repeatable: false),
    OptionSpec(name: "--devnet-start-unix-ms", value: "MILLISECONDS", group: OptionGroup.Devnet,
      description: "Explicit shared network Unix origin; required.",
      fallback: OptionDefault.Required, commands: "tiny-devnet node",
      repeatable: false),
    OptionSpec(name: "--devnet-stop-slot", value: "NUMBER", group: OptionGroup.Devnet,
      description: "Bounded stop slot (2..64); required.", fallback: OptionDefault.Required,
      commands: "tiny-devnet node",
      repeatable: false),

    # Conformance testing options. Keep additions in this group.
    OptionSpec(name: "--fuzz-spec", value: "PRESET", group: OptionGroup.Fuzz,
      description: "tiny|full|fuzz; overrides JAM_FUZZ_SPEC.",
      fallback: OptionDefault.Environment, commands: "fuzz|serve-fuzz|serve-fuzz-preset"),
    OptionSpec(name: "--fuzz-data-path", value: "DIR", group: OptionGroup.Fuzz,
      description: "Private runtime directory; overrides JAM_FUZZ_DATA_PATH.",
      fallback: OptionDefault.Environment, commands: "fuzz|serve-fuzz|serve-fuzz-preset"),
    OptionSpec(name: "--fuzz-sock-path", value: "PATH", group: OptionGroup.Fuzz,
      description: "Unix listener socket path; overrides JAM_FUZZ_SOCK_PATH.",
      fallback: OptionDefault.Environment, commands: "fuzz|serve-fuzz|serve-fuzz-preset"),
    OptionSpec(name: "--fuzz-log-level", value: "LEVEL", group: OptionGroup.Fuzz,
      description: "error|warn|info|debug|trace; overrides JAM_FUZZ_LOG_LEVEL.",
      fallback: OptionDefault.Environment, commands: "fuzz|serve-fuzz|serve-fuzz-preset"),
    OptionSpec(name: "--fuzz-policy", value: "FILE", group: OptionGroup.Fuzz,
      description: "Conformance resource policy; required for explicit fuzz commands.",
      fallback: OptionDefault.Required,
      commands: "serve-fuzz|serve-fuzz-preset"),
    OptionSpec(name: "--fuzz-state-writes", value: "COUNT", group: OptionGroup.Fuzz,
      description: "Maximum conformance state writes.", fallback: OptionDefault.FuzzWrites,
      commands: "fuzz|serve-fuzz|serve-fuzz-preset"),
    OptionSpec(name: "--fuzz-state-write-bytes", value: "BYTES", group: OptionGroup.Fuzz,
      description: "Maximum conformance state value bytes.", fallback: OptionDefault.FuzzWriteBytes,
      commands: "fuzz|serve-fuzz|serve-fuzz-preset"),
    OptionSpec(name: "--fuzz-parameters", value: "FILE", group: OptionGroup.Fuzz,
      description: "Explicit chain parameters; required for serve-fuzz.",
      fallback: OptionDefault.Required, commands: "serve-fuzz",
      repeatable: false)
  ]

func optionIndex*(name: string): int =
  ## Resolve one canonical spelling; unknown names never become positional values.
  for index, spec in OptionSpecs:
    if name == spec.name: return index
  -1

func commandIndex*(name: string): int =
  ## Resolve exact command topics without prefix matching or implicit defaults.
  for index, spec in CommandSpecs:
    if name == spec.name: return index
  -1

proc defaultValue*(spec: OptionSpec, topic = ""): string =
  ## Render the same typed defaults used by startup; enum spelling is normalized only for presentation.
  case spec.fallback
  of OptionDefault.Required: ""
  of OptionDefault.None: "none"
  of OptionDefault.ChainFile: DefaultChainFile
  of OptionDefault.Environment: "environment"
  of OptionDefault.Disabled: "disabled"
  of OptionDefault.Embedded: "embedded assets"
  of OptionDefault.RpcPort: $DefaultRpcPort
  of OptionDefault.McpPort: $DefaultMcpPort
  of OptionDefault.UiPort: $DefaultUiPort
  of OptionDefault.Timeout:
    if topic == "server": $DefaultServerTimeoutMs
    elif topic.len == 0: TimeoutOverview
    else: $DefaultTimeoutMs
  of OptionDefault.PeerMode:
    if topic == "server": DefaultServerMode
    elif topic.len == 0: "server: " & DefaultServerMode & "; client: " & DefaultPeerMode
    else: DefaultPeerMode
  of OptionDefault.Mode: ($DefaultNodeMode).toLowerAscii
  of OptionDefault.Storage: ($DefaultStateStorage).toLowerAscii
  of OptionDefault.Layout: ($DefaultStateLayout).toLowerAscii & " (full); paged (light)"
  of OptionDefault.Writes: $DefaultStateWrites
  of OptionDefault.WriteBytes: $DefaultStateWriteBytes
  of OptionDefault.FuzzWrites: $DefaultFuzzWrites
  of OptionDefault.FuzzWriteBytes: $DefaultFuzzWriteBytes
  of OptionDefault.CompactBytes: $DefaultCompactionBytes
  of OptionDefault.Blocks: $DefaultDownloadBlocks
  of OptionDefault.Logging: $DefaultLogLevel
  of OptionDefault.PvmBackend: $DefaultPvmBackend
  of OptionDefault.DataDirectory: DefaultDataDirectory
  of OptionDefault.NetworkPort:
    if spec.name == "--net-remote-port": $(DefaultNetworkPort+1) else: $DefaultNetworkPort
  of OptionDefault.Certificate: DefaultDataDirectory & "/network/cert.pem"
  of OptionDefault.PrivateKey: DefaultDataDirectory & "/network/key.pem"
  of OptionDefault.PeerKey:
    if topic == "server": "-"
    elif topic.len == 0: "server: -; dialers: required"
    else: ""
  of OptionDefault.Alpn: DefaultDevelopmentAlpn
  of OptionDefault.ManagementPath: DefaultDataDirectory & "/management/admin.sock"
  of OptionDefault.Database: DefaultDataDirectory & "/full/state.db; light: " &
      DefaultDataDirectory & "/light/paged"
  of OptionDefault.RetainedBlocks: $DefaultRetainedBlocks
