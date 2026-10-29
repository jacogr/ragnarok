# Copyright (c) 2026 Ragnarök contributors
# SPDX-License-Identifier: MIT OR Apache-2.0

## Provision persistent default transport identity and parent directories only after CLI validation.
## Explicit TLS paths and existing identities are never replaced or repaired implicitly.

import std/[os, dirs, paths, posix/posix]
import ../management/file_status
import ./options
import ../quic/protocol
import ../lib/atomic/file as atomic_file
import ../lib/atomic/file/writer as atomic_file_writer
import ../codec/bounded

proc generateKey(pem: ptr byte, capacity: csize_t, length: ptr csize_t,
    publicKey: ptr byte): cint {.importc: "rq_identity_key", cdecl, header: "cert_fields.h".}
  ## Borrow fixed caller buffers only during bundled Ed25519 generation.
proc generateCertificate(key: ptr byte, length: csize_t, dns: cstring, days: cint,
    pem: ptr byte, capacity: csize_t, written: ptr csize_t): cint {.
    importc: "rq_identity_cert", cdecl, header: "cert_fields.h".}
  ## TLS signs the caller's Nim-derived JAM identity name without owning paths or protocol policy.
proc clear(bytes: ptr byte, length: csize_t) {.importc: "rq_identity_clear", cdecl,
    header: "cert_fields.h".}
  ## Erase private PEM scratch on every completion path.
proc effectiveUid(): uint32 {.importc: "geteuid", cdecl, header: "<unistd.h>".}
  ## Persistent private identity directories must belong to the running account.

proc privateDirectory(path: string, restrictExisting = true): bool =
  ## Create nested directories, refuse a symlink final component, and restrict the identity namespace.
  let existed = dirExists(path) or symlinkExists(path)
  try: createDir(paths.path(path))
  except: return false
  var native = path
  var metadata = default(FileStatus)
  if readStatus(native.toCString(), metadata) != 0 or not S_ISDIR(posix.Mode(
      metadata.st_mode)): return false
  if uint32(metadata.st_uid) != effectiveUid(): return false
  if existed and not restrictExisting:
    return (uint32(metadata.st_mode) and 0o077) ==
        0 # Never chmod an explicit parent such as the working directory or root.
  chmod(native.toCString(), posix.Mode(0o700)) == 0

proc regular(path: string, secret = false): bool =
  ## Default credentials must be ordinary files; private keys cannot be group/world readable.
  var native = path
  var metadata = default(FileStatus)
  if readStatus(native.toCString(), metadata) != 0 or not S_ISREG(posix.Mode(
      metadata.st_mode)): return false
  not secret or (uint32(metadata.st_mode) and 0o077) == 0

proc ensureIdentity*(directory: string, diagnostic: var string): bool =
  ## Serialize first-use publication; any partial bundle refuses instead of rotating an existing identity.
  diagnostic = "Cannot prepare private identity directory: " & directory
  if not privateDirectory(directory): return false
  var writer = default(AtomicFileWriter)
  if openAtomicFileWriter(writer, directory / "identity") != AtomicFileError.None: return false
  defer: discard writer.close()
  let certificate = directory / "cert.pem"
  let keyPath = directory / "key.pem"
  let publicPath = directory / "public.key"
  let existing = fileExists(certificate) or fileExists(keyPath) or fileExists(publicPath) or
    symlinkExists(certificate) or symlinkExists(keyPath) or symlinkExists(publicPath)
  if existing:
    diagnostic = "Incomplete or unsafe TLS identity in " & directory &
      "; supply --net-cert and --net-key or restore the existing bundle"
    if not regular(certificate) or not regular(keyPath, true) or not regular(
        publicPath): return false
    let publicKey = readBoundedFile(publicPath, ByteLimit(32))
    if publicKey.error != AtomicFileError.None or publicKey.value.len != 32: return false
    diagnostic = ""
    return true # Native TLS validates certificate/key consistency before binding; no existing bytes are changed.
  var key = default(array[4096, byte])
  defer: clear(addr key[0], csize_t(key.len))
  var cert = default(array[4096, byte])
  var publicKey = default(array[32, byte])
  var keyLength, certLength = csize_t(0)
  diagnostic = "Unable to generate the default TLS identity"
  if generateKey(addr key[0], csize_t(key.len), addr keyLength, addr publicKey[0]) !=
      1: return false
  if keyLength == 0 or keyLength > csize_t(key.len): return false
  var name = ""
  for character in peerName(publicKey): name.add(char(character))
  if generateCertificate(addr key[0], keyLength, name.toCString(), cint(DefaultCertificateDays),
      addr cert[0], csize_t(cert.len), addr certLength) != 1: return false
  if certLength == 0 or certLength > csize_t(cert.len): return false
  diagnostic = "Unable to publish the default TLS identity in " & directory
  if replaceAtomicFile(keyPath, key.toOpenArray(0, int(keyLength)-1), ByteLimit(key.len)) !=
      AtomicFileError.None: return false
  if replaceAtomicFile(certificate, cert.toOpenArray(0, int(certLength)-1), ByteLimit(cert.len)) !=
      AtomicFileError.None: return false
  if replaceAtomicFile(publicPath, publicKey, ByteLimit(32)) != AtomicFileError.None: return false
  diagnostic = ""
  true

proc prepareStartup*(options: Options, diagnostic: var string): bool =
  ## Resolve filesystem defaults after help and full option validation, before opening listeners.
  diagnostic = ""
  if not options.valid: return false
  if options.argumentCount == 0: return true
  let topic = options.argument(1)
  if topic notin ["server", "client", "mesh", "download", "download-current",
      "sync-current"]: return true
  let certIndex = if topic == "mesh": 4 else: 3
  let directory = options.dataDirectory / "network"
  if options.argument(certIndex) == directory / "cert.pem" and
      options.argument(certIndex+1) == directory / "key.pem":
    if not ensureIdentity(directory, diagnostic): return false
  if options.diskStorage:
    try:
      let parent = parentDir(options.stateDatabase)
      if parent.len > 0: createDir(paths.path(parent)) # A bare filename already belongs to the existing working directory.
    except:
      diagnostic = "Cannot prepare database parent directory: " & parentDir(options.stateDatabase)
      return false
  if options.managementSocket.len > 0:
    if not privateDirectory(parentDir(options.managementSocket), false):
      diagnostic = "Cannot prepare private management directory"
      return false
  true
