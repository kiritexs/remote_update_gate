import 'update_manifest.dart';
import 'update_status.dart';
import 'version.dart';

/// The pure heart of the gate — resolves the [UpdateStatus] (no I/O, fail-open).
UpdateStatus resolveUpdateStatus({
  required String currentVersion,
  required UpdateManifest manifest,
  String? skippedVersion,
}) {
  if (!isValidVersion(currentVersion)) return UpdateStatus.none;
  if (versionLt(currentVersion, manifest.unskippableVersion)) {
    return UpdateStatus.forced;
  }
  if (versionLt(currentVersion, manifest.skippableVersion)) {
    if (skippedVersion != null &&
        !versionLt(skippedVersion, manifest.skippableVersion)) {
      return UpdateStatus.none;
    }
    return UpdateStatus.optional;
  }
  return UpdateStatus.none;
}
