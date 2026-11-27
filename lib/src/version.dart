/// Dotted app-version parsing + comparison for the update gate.
library;

final RegExp _versionRe = RegExp(r'^\d+(\.\d+)*$');

/// Whether [raw] is a well-formed dotted version. Empty/blank is false.
bool isValidVersion(String? raw) {
  if (raw == null) return false;
  return _versionRe.hasMatch(raw.trim());
}

/// Parse a dotted version into a list of ints, or `[]` when empty/invalid. Never throws.
List<int> parseVersion(String? raw) {
  if (raw == null) return const [];
  final s = raw.trim();
  if (!_versionRe.hasMatch(s)) return const [];
  final parts = <int>[];
  for (final component in s.split('.')) {
    final n = int.tryParse(component);
    if (n == null) return const [];
    parts.add(n);
  }
  return parts;
}

/// True if version [a] < version [b], component-wise and zero-padded.
bool versionLt(String? a, String? b) {
  final ta = parseVersion(a);
  final tb = parseVersion(b);
  final n = ta.length > tb.length ? ta.length : tb.length;
  for (var i = 0; i < n; i++) {
    final x = i < ta.length ? ta[i] : 0;
    final y = i < tb.length ? tb[i] : 0;
    if (x != y) return x < y;
  }
  return false;
}

/// True if [raw] is a real, non-zero floor that would gate someone.
bool versionGates(String? raw) => parseVersion(raw).any((n) => n > 0);

/// The higher of two versions (the one that is not less than the other).
String versionMax(String a, String b) => versionLt(a, b) ? b : a;
