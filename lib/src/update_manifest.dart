import 'package:flutter/foundation.dart';

import 'version.dart';

/// The server-driven update descriptor the gate resolves against.
@immutable
class UpdateManifest {
  /// Recommend an update to versions `< skippableVersion` (`""` ⇒ never).
  final String skippableVersion;

  /// Force an update on versions `< unskippableVersion` (`""` ⇒ never).
  final String unskippableVersion;

  /// Human-readable message shown on the card (from your API); may be empty.
  final String message;

  /// Download URLs keyed by a platform token; looked up by [urlFor].
  final Map<String, String> downloadUrls;

  /// Used when [downloadUrls] has no entry for the current platform.
  final String fallbackUrl;

  /// Optional, informational: the latest available version.
  final String? latestVersion;

  const UpdateManifest({
    this.skippableVersion = '',
    this.unskippableVersion = '',
    this.message = '',
    this.downloadUrls = const {},
    this.fallbackUrl = '',
    this.latestVersion,
  });

  /// A manifest that gates nobody — the safe default before anything loads.
  static const UpdateManifest empty = UpdateManifest();

  /// The best download URL for [platform], or null if none is known.
  String? urlFor(String platform) {
    final direct = downloadUrls[platform];
    if (direct != null && direct.isNotEmpty) return direct;
    if (fallbackUrl.isNotEmpty) return fallbackUrl;
    for (final v in downloadUrls.values) {
      if (v.isNotEmpty) return v;
    }
    return null;
  }

  /// Return a manifest whose required floor is at least [minUnskippable] (else `this`).
  UpdateManifest mergeFloor(String minUnskippable) {
    if (!versionGates(minUnskippable) ||
        !versionLt(unskippableVersion, minUnskippable)) {
      return this;
    }
    return UpdateManifest(
      skippableVersion: versionLt(skippableVersion, minUnskippable)
          ? minUnskippable
          : skippableVersion,
      unskippableVersion: minUnskippable,
      message: message,
      downloadUrls: downloadUrls,
      fallbackUrl: fallbackUrl,
      latestVersion: latestVersion,
    );
  }

  Map<String, dynamic> toJson() => {
    'skippableVersion': skippableVersion,
    'unskippableVersion': unskippableVersion,
    'message': message,
    'downloadUrls': downloadUrls,
    'fallbackUrl': fallbackUrl,
    if (latestVersion != null) 'latestVersion': latestVersion,
  };

  factory UpdateManifest.fromJson(Map<String, dynamic> json) {
    String asVersion(Object? v) => v == null ? '' : '$v'.trim();
    final urls = <String, String>{};
    final rawUrls = json['downloadUrls'];
    if (rawUrls is Map) {
      rawUrls.forEach((k, v) => urls['$k'] = '${v ?? ''}');
    }
    final latest = json['latestVersion'];
    return UpdateManifest(
      skippableVersion: asVersion(json['skippableVersion']),
      unskippableVersion: asVersion(json['unskippableVersion']),
      message: '${json['message'] ?? ''}',
      downloadUrls: urls,
      fallbackUrl: '${json['fallbackUrl'] ?? ''}',
      latestVersion: latest == null ? null : '$latest'.trim(),
    );
  }

  @override
  bool operator ==(Object other) =>
      other is UpdateManifest &&
      other.skippableVersion == skippableVersion &&
      other.unskippableVersion == unskippableVersion &&
      other.message == message &&
      other.fallbackUrl == fallbackUrl &&
      other.latestVersion == latestVersion &&
      mapEquals(other.downloadUrls, downloadUrls);

  @override
  int get hashCode => Object.hash(
    skippableVersion,
    unskippableVersion,
    message,
    fallbackUrl,
    latestVersion,
    Object.hashAllUnordered(
      downloadUrls.entries.map((e) => Object.hash(e.key, e.value)),
    ),
  );
}
