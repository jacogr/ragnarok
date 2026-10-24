# Frozen Pinky interpreter guest

Pinky is the cycle-accurate NES emulator workload from PolkaVM
69e5b87c9888bc4f94cabdadc9661cf68a1bfbfa, using its unchanged bench-pinky main,
pinned NES dependency 5a9d4ff5f22731191cffd7d6202a1d144aacd740 and embedded
nes15-NTSC homebrew ROM. The original PolkaVM/Pinky MIT and Apache licenses and
the ROM copyright/BSD license are retained beside this fixture.

The public initialize export runs nine NES frames, including controller input to
start autosolve, once per reference process before input capture and outside all
execution clocks. The checked entry calls original benchmark_run once (one more
frame plus ABGR framebuffer conversion), then returns one. Both interpreters start
from the exact frozen initialized memory. The reference restores writable pages
into a fresh public instance before every invocation; registers/gas are reset to
the same explicit source. Read-only pages retain their module data and permissions.
Complete memory, including framebuffer/NES state and stack, is compared together
with all registers and gas. Returning one proves checked-call completion, not an
independent proof of NES emulation. These metered checked timings are not upstream
published stock scores. Initialization/module setup is excluded from execution.

Normal CI reads the frozen artifact and never installs the historical guest
compiler. Rebuild explicitly with the recorded nightly, rust-src and legacy
PolkaVM target: copy the upstream main/ROM into guest/bench-pinky/src, append
pinky.checked_entry.rs.inc to main.rs, and copy upstream bench-common.rs into
guest/. Use workspace.Cargo.toml as guest/Cargo.toml, the normalized package
manifest (substitute @POLKAVM_ROOT@), and guest-Cargo.lock. Execute the command,
release profile and path-remapping flags in pinky.provenance.json; link with
pinned public program_from_elf, default Config, JamV1. Paths in provenance are
placeholders for the corresponding pristine source and ignored build roots.
Source, package, ROM, toolchain and linked artifact identities are pinned;
changes require reviewed fixture regeneration. No dependency pin is upgraded.
