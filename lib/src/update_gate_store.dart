/// Per-app persistence for the skipped version and the cached manifest (the offline latch).
abstract class UpdateGateStore {
  Future<String?> loadSkippedVersion();
  Future<void> saveSkippedVersion(String version);

  Future<Map<String, dynamic>?> loadCachedManifest();
  Future<void> saveCachedManifest(Map<String, dynamic> json);
}
