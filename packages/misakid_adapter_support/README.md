# misakid_adapter_support

Path and file checks shared by the misakid adapter packages.

The adapters accept explicit resource paths and verify that a file did not
change while it was read. Each adapter used to carry its own copy of these
checks. They live here once, so a fix reaches every adapter.

This package is plumbing for the `misakid_*` adapters. It has no G2P behavior
and makes no parity claim.

## Libraries

- `package:misakid_adapter_support/path_text.dart` is pure Dart. It checks
  that a path is well-formed text within the 32,768-byte UTF-8 limit the
  adapters and their native shims share.
- `package:misakid_adapter_support/file_system.dart` uses `dart:io`, so it
  supports the Dart VM only. It checks that a path is absolute on the current
  platform and captures a file's size and timestamps to detect a change.
