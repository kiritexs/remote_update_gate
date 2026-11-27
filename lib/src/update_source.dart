import 'update_manifest.dart';

/// Where the [UpdateManifest] comes from — implemented per app; null on failure/offline.
abstract class UpdateSource {
  Future<UpdateManifest?> fetch();
}
