# Changelog

## Unreleased

- Use `misakid_adapter_support` for the path and file checks this package
  shared with the other adapters, instead of private copies. No behavior
  change.
- Free the first native path buffer when allocating the second one fails
  while creating a context.
- Report malformed initialization data from the native library as
  `BackendUnavailableException`, as the other adapters do, instead of letting
  the internal exception escape.

## 0.1.0-dev.1

- Add the explicit macOS-arm64 eSpeak NG 1.52.0 English fallback backend.
- Add provisioned exact composition coverage with the native English
  transformer tokenizer/tagger; this is a development-only test dependency.
