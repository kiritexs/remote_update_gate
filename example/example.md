# remote_update_gate example

Your API serves an update manifest, the app keeps the skipped version and
the last manifest, and `UpdateGate` sits above every screen.

```dart
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:remote_update_gate/remote_update_gate.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Keeps the skipped version and the last manifest, for the offline latch.
class PrefsUpdateStore implements UpdateGateStore {
  PrefsUpdateStore(this._prefs);
  final SharedPreferences _prefs;

  @override
  Future<String?> loadSkippedVersion() async =>
      _prefs.getString('update.skipped');

  @override
  Future<void> saveSkippedVersion(String version) =>
      _prefs.setString('update.skipped', version);

  @override
  Future<Map<String, dynamic>?> loadCachedManifest() async {
    final json = _prefs.getString('update.manifest');
    return json == null ? null : jsonDecode(json) as Map<String, dynamic>;
  }

  @override
  Future<void> saveCachedManifest(Map<String, dynamic> json) =>
      _prefs.setString('update.manifest', jsonEncode(json));
}

/// Reads the manifest from your API, for example:
/// {"skippableVersion": "1.3.0", "unskippableVersion": "1.2.0",
///  "message": "...", "downloadUrls": {"android": "https://..."}}
class ApiUpdateSource implements UpdateSource {
  @override
  Future<UpdateManifest?> fetch() async {
    final json = await myApi.getJson('/configuration');
    return json == null ? null : UpdateManifest.fromJson(json);
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final controller = UpdateController(
    currentVersion: '1.2.5', // from package_info_plus
    platform: 'android',
    store: PrefsUpdateStore(await SharedPreferences.getInstance()),
    source: ApiUpdateSource(),
    allowedDownloadHosts: {'downloads.example.com'},
  );
  await controller.init(); // the offline latch, before the first frame
  runApp(
    MaterialApp(
      builder: (context, child) =>
          UpdateGate(controller: controller, child: child!),
      home: const HomeScreen(),
    ),
  );
  await controller.refresh();
}
```

`versionLt('1.2.5', '1.3.0')` and the other helpers in `version.dart` compare
dotted versions part by part, the same rules your server should use.
