# Security

## Overview

7ZIP4MAC is a native macOS graphical interface for the 7-Zip command-line engine. It is not a network application and does not perform authentication, encryption key management, or remote communication. This document describes the security model and practices.

## Threat Model

7ZIP4MAC operates in a local-user context on a single Mac. Assumptions:

- **No network exposure**: The app does not listen on ports, make outbound connections, or exchange data over the network.
- **Single-user trust boundary**: Files opened are assumed to be from trusted or tolerated sources.
- **Local privilege boundary**: The app runs with the user's own privileges; no elevation required.

## Security Practices

### Subprocess Invocation

Archive operations invoke the bundled `7zz` binary via `Foundation.Process`. Arguments are always passed as an array of strings, never as a shell command string:

```swift
process.arguments = ["-slt", archivePath]  // Array: prevents shell injection
```

This prevents command injection even if archive paths contain shell metacharacters.

### Archive Parsing

Archives are parsed by reading 7-Zip's `-slt` output via state machine, splitting on known delimiters. User-controlled strings (paths, entry names) flow only through the display layer, not into filesystem operations or subprocess arguments.

GNU tar archives: the parser strips literal `./` prefixes before display. No path traversal is possible because:
- Only removes `./`; does not resolve `..` or symlinks
- Extraction uses original archive paths (7-Zip engine logic)
- Extraction destinations chosen by user via file dialog

### User Interface

Toolbar items, menu titles, and alert text are static or derived from app state only, never from archive content.

### Data Persistence

The app persists only:
- User settings in `~/Library/Preferences/com.jensyleo.sevenzip4mac.plist`
- Toolbar item order (fixed IDs like `"extract"`, `"test"`) in UserDefaults
- Recently opened file URLs (macOS standard)

Passwords for encrypted archives are kept in memory only, never written to disk.

### Code Signing and Sandboxing

The app is ad-hoc signed for development builds. Production releases require a Developer ID certificate (not using App Sandbox):

- **No sandbox**: The app needs unrestricted filesystem access (read arbitrary archives, write to user-chosen destinations).
- **Process spawning**: Must execute the bundled 7-Zip engine without sandbox restrictions.
- **Trust model**: Sandbox would not add security in this threat model (assumes local-user trust).

## Security Review (v1.7.0–v1.7.2)

Formal security review covered:

- **Path normalization**: GNU tar prefix stripping does not introduce path traversal
- **Toolbar bridge**: Cross-window closures do not leak session state or create retain cycles
- **UserDefaults**: Only non-sensitive IDs persisted
- **Archive parsing**: Archive data does not reach subprocess arguments, filesystem paths, or native dialogs

**Result**: No high-confidence, exploitable vulnerabilities identified.

## Reporting Security Issues

If you discover a security vulnerability, please report it responsibly:

1. **Do not open a public GitHub issue** — this notifies potential attackers before a fix is available.
2. **Email the developer** at jmcruz@erco.energy with:
   - Description of the vulnerability
   - Steps to reproduce (if applicable)
   - Affected version(s)
   - Your contact information (optional)

3. **Timeline**:
   - Acknowledgment within 48 hours
   - Investigation and fix development
   - Coordinated disclosure when a fix is ready

## Scope and Limitations

### What is Protected

- Command injection via archive paths or filenames
- Shell metacharacter injection in subprocess arguments
- Data leakage to UserDefaults or system logs
- Session passwords persisting to disk

### What is NOT Protected

- **Malicious 7-Zip engine**: The bundled `7zz` binary runs with full user privileges; a compromised version could extract files anywhere or execute code. Users must trust the binary source (official Igor Pavlov releases).
- **Malicious archives**: An archive designed to exploit 7-Zip bugs (e.g., symlink bombs, deeply nested paths) could cause problems. The app does not defend against 7-Zip engine vulnerabilities.
- **Concurrent file access**: If multiple processes write to the same extraction destination simultaneously, file corruption could occur.
- **Privilege escalation**: The app does not run privileged code; no elevation is requested or used.

### Out of Scope

- Network security (the app has no network component)
- Cryptographic security of 7-Zip (delegated to the engine)
- DoS resistance (the app does not handle untrusted network input)

## Dependencies

- **7-Zip engine**: Official, unmodified `7zz` binary (GNU LGPL, Igor Pavlov). Security updates are manual; the bundled version does not auto-update.
- **Foundation, AppKit, SwiftUI**: Apple frameworks (macOS updates apply security patches)
- **SevenZipKit**: Internal Swift package for parsing 7-Zip output

## Best Practices for Users

- Keep macOS updated for security patches
- Verify archive sources before extraction
- Use password protection for sensitive archive contents
