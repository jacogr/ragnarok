# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Real bundled-TLS generation, stable identity reuse and refusal of incomplete persistent bundles.

import std/[os, dirs, paths, files, assertions, syncio, strutils]
import ../../../src/app/startup

proc main() {.raises.} =
  ## Every test owns a build-directory namespace; no repository or caller fixture is mutated.
  let root = os.getCurrentDir() / "startup-identity-test"
  if dirExists(root): removeDir(paths.path(root))
  createDir(paths.path(root))
  defer: removeDir(paths.path(root))
  let directory = root / "network"
  var diagnostic = ""
  assert ensureIdentity(directory, diagnostic), diagnostic
  let key = readFile(directory / "key.pem")
  let cert = readFile(directory / "cert.pem")
  let publicKey = readFile(directory / "public.key")
  assert publicKey.len == 32 and "BEGIN PRIVATE KEY" in key and "BEGIN CERTIFICATE" in cert
  assert getFilePermissions(paths.path(directory / "key.pem")) == {fpUserRead, fpUserWrite}
  assert ensureIdentity(directory, diagnostic), diagnostic
  assert readFile(directory / "key.pem") == key and readFile(directory / "cert.pem") == cert
  assert readFile(directory / "public.key") == publicKey
  removeFile(paths.path(directory / "cert.pem"))
  assert not ensureIdentity(directory, diagnostic)
  assert readFile(directory / "key.pem") == key # A partial bundle never rotates an existing identity.
  assert not fileExists(directory / "cert.pem")
  let link = root / "linked"
  createSymlink(directory, link)
  assert not ensureIdentity(link, diagnostic) # A symlink cannot select the managed private namespace.
try: main()
except: assert false, "Startup identity test filesystem operation failed"
echo "Startup identity generation and reuse passed"
