# macOS toolchain baseline

Verified 2026-10-13 on Apple Silicon (arm64), macOS 27.0.1.
This is a local development baseline; Linux reproducibility (M0) remains open.
No JAM protocol implementation or conformance tests are part of this setup.

## Recorded versions

- Nim: 2.2.12, built 2026-09-08.
- Nimble: 0.24.1.
- Odin: dev-2026-10, commit prefix 84bc3fc21 (Homebrew package 2026-10).
- Odin's Homebrew LLVM/LLD dependency: 22.1.8.
- Apple clang: 21.0.0 (clang-2100.3.34.2).

Homebrew was already installed at /opt/homebrew. Xcode was already selected
at /Applications/Xcode.app/Contents/Developer. Neither language was installed.
Homebrew stable bottles were chosen for a straightforward native ARM64 setup.
Future upgrades should be deliberate and revalidated; the installation command
below follows Homebrew's current versions rather than locking these versions.

## Installation and version checks

```sh
HOMEBREW_NO_AUTO_UPDATE=1 brew install nim odin
nim --version
nimble --version
odin version
```

Installation succeeded. Odin's formula also installed glfw 3.5.1, raylib 6.0,
LLVM/LLD 22.1.8, and upgraded xz to 5.8.4 and zstd to 1.5.7_1.
Both compiler commands are available on the existing shell PATH; no shell
configuration changes were needed.

## Smoke checks

Temporary sources and build output were placed in
/private/tmp/ragnarok-toolchain-smoke (not durable project fixtures).

hello.nim:

```nim
import std/strutils
let values = @["Ragnarok", "Nim", "ARC"]
doAssert values.len == 3
echo values.join(" ")
```

hello.odin:

```odin
package main
import "core:fmt"
main :: proc() {
    values := []string{"Ragnarok", "Odin", "native"}
    assert(len(values) == 3)
    fmt.println(values[0], values[1], values[2])
}
```

Executed successfully:

```sh
nim c --mm:arc --nimcache:/private/tmp/ragnarok-toolchain-smoke/nimcache --out:/private/tmp/ragnarok-toolchain-smoke/hello-nim -r /private/tmp/ragnarok-toolchain-smoke/hello.nim
odin check /private/tmp/ragnarok-toolchain-smoke/hello.odin -file
odin build /private/tmp/ragnarok-toolchain-smoke/hello.odin -file -out:/private/tmp/ragnarok-toolchain-smoke/hello-odin -extra-linker-flags:"-isysroot $(xcrun --sdk macosx --show-sdk-path)"
/private/tmp/ragnarok-toolchain-smoke/hello-odin
file /private/tmp/ragnarok-toolchain-smoke/hello-nim /private/tmp/ragnarok-toolchain-smoke/hello-odin
```

Observed output: `Ragnarok Nim ARC` and `Ragnarok Odin native`.
Both binaries were reported as Mach-O 64-bit executable arm64.
Nim's compiler output explicitly confirmed `mm: arc`.
The Nim smoke program has no reference cycles; this does not establish cycle
safety for future code. Odin's slice refers to local storage and requires no
heap allocation or cross-FFI lifetime management.

Odin's default build succeeded but warned about an absent SDK at
/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk. This Mac uses full Xcode;
explicitly selecting its SDK through the linker flag above removed the warning.
Setting SDKROOT alone did not remove it. No global SDK configuration was changed.

Official vectors, protocol checks, and Linux builds were not run: this task
only installed and verified the local compiler toolchains.

## Formatters (added 2026-10-13)

Installed `odinfmt` through Homebrew (`HOMEBREW_NO_AUTO_UPDATE=1 brew install odinfmt`).
Homebrew reported package 2026-08; no dependencies or compiler upgrades were
needed. This release has no `-version` option, so the package version was checked
with `brew list --versions odinfmt`. `nimpretty --version` reports 0.2 and is
already bundled with the installed Nim 2.2.12.

Use `python3 tools/format.py` to format all Nim/Odin sources and
`python3 tools/format.py --check` to verify without modifying files.
The wrapper uses stdin/stdout with `nimpretty --indent:2 --maxLineLen:100` and
`odinfmt -config:<project>/odinfmt.json`. Odin's configuration uses tabs,
a tab display width of four, and a target width of 100 columns.

Formatter references: [OLS/odinfmt configuration](https://github.com/DanielGavin/ols#odinfmt-configurations),
[Nim's bundled tools](https://nim-lang.org/1.0.0/tools.html).
These are development tools, not runtime dependencies.
