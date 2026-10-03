import 'dart:io';

/// Whether [path] is absolute on the current platform.
///
/// On Windows a drive path (`C:\` or `C:/`) or a UNC path is absolute;
/// elsewhere a path that starts with `/` is.
bool isAbsoluteFilePath(String path) {
  if (path.isEmpty) return false;
  if (!Platform.isWindows) return path.startsWith('/');
  return RegExp(r'^(?:[A-Za-z]:[\\/]|\\\\)').hasMatch(path);
}
