import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:url_launcher/url_launcher.dart';

import 'update_gate_store.dart';
import 'update_manifest.dart';
import 'update_policy.dart';
import 'update_source.dart';
import 'update_status.dart';
import 'version.dart';

/// Orchestrates the gate: owns the manifest + resolved status and the UI-facing actions.
class UpdateController extends ChangeNotifier {
  UpdateController({
    required this._currentVersion,
    required this._platform,
    required this._store,
    this._source,
    this._fallbackDownloadUrl = '',
    this._minRefreshInterval = const Duration(hours: 6),
    this._minRetryInterval = const Duration(minutes: 1),
    this._allowedDownloadHosts = const {},
    this._allowAnyDownloadHost = false,
    this._allowedStoreAppIds = const {},
    this._allowAnyStoreLink = false,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final String _currentVersion;
  final String _platform;
  final UpdateGateStore _store;
  final UpdateSource? _source;

  final String _fallbackDownloadUrl;

  /// How long a successful refresh holds off the next unforced one.
  final Duration _minRefreshInterval;

  /// How long any attempt, failed or not, holds off the next unforced one:
  /// after a failure the check comes back within this, not after
  /// [_minRefreshInterval]; and a refresh that needs a download target
  /// can't poll faster than this. A `reconnect` skips it once after a
  /// failed attempt ([_reconnectMaySkipRetry]).
  final Duration _minRetryInterval;
  final DateTime Function() _clock;

  /// The hosts an https download link may open, subdomains included. None
  /// opens nothing unless [_allowAnyDownloadHost]: the link comes from a
  /// config that can be tampered with.
  final Set<String> _allowedDownloadHosts;
  final bool _allowAnyDownloadHost;
  Set<String> _moreDownloadHosts = const {};

  /// The apps a store link may open: `market://details?id=<id>` by its
  /// package name, `itms-apps://…/id<digits>` by its digits (the number
  /// without `id`). None opens no store link unless [_allowAnyStoreLink]:
  /// like a host, the link comes from a config that can be tampered with.
  final Set<String> _allowedStoreAppIds;
  final bool _allowAnyStoreLink;

  UpdateManifest _manifest = UpdateManifest.empty;
  String? _skippedVersion;
  UpdateStatus _status = UpdateStatus.none;
  bool _offlineContinued = false;
  bool _serverForced = false;
  String _sessionFloor = '';

  /// The last refresh that applied a manifest.
  DateTime? _lastRefresh;

  /// The last refresh that went to the source, whatever came back.
  DateTime? _lastAttempt;

  /// Whether a `reconnect` may skip [_minRetryInterval]: the last attempt
  /// failed, likely made without the network, and wasn't itself a reconnect
  /// let through early. After a success, or a failed early reconnect, the
  /// minute holds, so a flapping link can't poll faster than that.
  bool _reconnectMaySkipRetry = false;
  Future<bool>? _inFlight;
  bool _initialized = false;
  bool _disposed = false;

  UpdateStatus get status => _status;
  UpdateManifest get manifest => _manifest;
  String get currentVersion => _currentVersion;

  /// True while a forced update is in effect.
  bool get isForced => _status == UpdateStatus.forced;

  /// True once the user chose to keep using offline content instead of updating (forced only).
  bool get offlineContinued => _offlineContinued;

  /// The launchable download URL for the current platform, or null if none.
  Uri? get downloadUri {
    final url =
        _manifest.urlFor(_platform) ??
        (_fallbackDownloadUrl.isNotEmpty ? _fallbackDownloadUrl : null);
    if (url == null) return null;
    return _launchableUri(url);
  }

  /// Whether a valid download target exists (else the host shows a "repairing" state).
  bool get hasDownloadTarget => downloadUri != null;

  /// Load persisted state and resolve with no network (the offline latch).
  Future<void> init() async {
    if (_initialized) return;
    _initialized = true;
    _skippedVersion = await _store.loadSkippedVersion();
    final cached = await _store.loadCachedManifest();
    if (cached != null) {
      try {
        _manifest = UpdateManifest.fromJson(cached);
      } catch (_) {}
    }
    _recompute();
  }

  /// Full manifest refresh via [UpdateSource]; returns true only when one was applied.
  ///
  /// A refresh already on its way is the one returned, forced or not.
  /// Unforced, it is skipped within [_minRefreshInterval] of the last one
  /// that applied a manifest (unless the gate is forced with no download
  /// target), and within [_minRetryInterval] of the last attempt.
  ///
  /// [reconnect]: the network just came back, so a failed last attempt,
  /// likely made without it, doesn't hold this one off, once; one that
  /// applied a manifest still does, as does [_minRefreshInterval]. The
  /// caller limits how often it passes this.
  Future<bool> refresh({bool force = false, bool reconnect = false}) {
    final inFlight = _inFlight;
    if (inFlight != null) return inFlight;
    final source = _source;
    if (source == null) return Future.value(false);
    final now = _clock();
    var early = false;
    if (!force) {
      final needsTarget = isForced && !hasDownloadTarget;
      final lastRefresh = _lastRefresh;
      if (!needsTarget &&
          lastRefresh != null &&
          now.difference(lastRefresh) < _minRefreshInterval) {
        return Future.value(false);
      }
      final lastAttempt = _lastAttempt;
      early =
          lastAttempt != null &&
          now.difference(lastAttempt) < _minRetryInterval;
      if (early && !(reconnect && _reconnectMaySkipRetry)) {
        return Future.value(false);
      }
    }
    _lastAttempt = now;
    // Counted as failed until a manifest applies.
    _reconnectMaySkipRetry = !early;
    final run = _fetchAndApply(source);
    _inFlight = run;
    // Callbacks run later, so this never clears before it was set.
    run.whenComplete(() {
      if (identical(_inFlight, run)) _inFlight = null;
    }).ignore();
    return run;
  }

  Future<bool> _fetchAndApply(UpdateSource source) async {
    UpdateManifest? fetched;
    try {
      fetched = await source.fetch();
    } catch (_) {
      fetched = null;
    }
    if (fetched == null) return false;
    await _applyManifest(fetched);
    _lastRefresh = _clock();
    _reconnectMaySkipRetry = false;
    return true;
  }

  /// Fold in a per-response server floor (`X-Min-Build`), escalating the required version.
  void reportServerFloor(String minUnskippableVersion) {
    if (!versionGates(minUnskippableVersion)) return;
    if (versionLt(_sessionFloor, minUnskippableVersion)) {
      _sessionFloor = minUnskippableVersion;
    }
    final merged = _manifest.mergeFloor(minUnskippableVersion);
    if (merged == _manifest) return;
    _manifest = merged;
    unawaited(_persist(merged));
    _recompute();
  }

  /// Force the gate on a server 426 (revoked API key); also kicks an immediate refresh.
  void markServerForced() {
    if (!_serverForced) {
      _serverForced = true;
      _recompute();
      unawaited(refresh(force: true));
    }
  }

  /// Push a manifest from outside (alternative to [refresh]).
  Future<void> submitManifest(UpdateManifest manifest) =>
      _applyManifest(manifest);

  /// User chose to keep using offline content rather than update now (forced only).
  void continueOffline() {
    if (_status == UpdateStatus.forced && !_offlineContinued) {
      _offlineContinued = true;
      if (!_disposed) notifyListeners();
    }
  }

  /// Re-show the blocking forced screen.
  void reopenForcedGate() {
    if (_offlineContinued) {
      _offlineContinued = false;
      if (!_disposed) notifyListeners();
    }
  }

  /// User deferred the optional update; persists the recommended floor (optional only).
  Future<void> skipOptional() async {
    if (_status != UpdateStatus.optional) return;
    final version = _manifest.skippableVersion;
    _skippedVersion = version;
    await _store.saveSkippedVersion(version);
    _recompute();
  }

  static const _allowedDownloadSchemes = {
    'https',
    'itms-apps',
    'itms-appss',
    'market',
  };

  /// Normalize a configured URL into a launchable [Uri], or null if we won't open it.
  Uri? _launchableUri(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return null;
    var uri = Uri.tryParse(trimmed);
    if (uri == null) return null;
    final scheme = uri.scheme.toLowerCase();
    if (scheme.isEmpty) {
      uri = Uri.tryParse('https://$trimmed');
    } else if (scheme == 'http') {
      uri = uri.replace(scheme: 'https');
    }
    if (uri == null) return null;
    final launchScheme = uri.scheme.toLowerCase();
    if (!_allowedDownloadSchemes.contains(launchScheme)) return null;
    if (launchScheme == 'https') {
      return _isAllowedDownloadHost(uri.host) ? uri : null;
    }
    return _isAllowedStoreLink(uri, launchScheme) ? uri : null;
  }

  static final _appleAppId = RegExp(r'^id(\d+)$');

  bool _isAllowedStoreLink(Uri uri, String scheme) {
    if (_allowAnyStoreLink) return true;
    final String? appId;
    if (scheme == 'market') {
      appId = uri.queryParameters['id'];
    } else {
      // The last segment that isn't empty: `.../id123/` names 123 too.
      final last = uri.pathSegments.lastWhere(
        (segment) => segment.isNotEmpty,
        orElse: () => '',
      );
      appId = _appleAppId.firstMatch(last)?.group(1);
    }
    return appId != null && _allowedStoreAppIds.contains(appId);
  }

  bool _isAllowedDownloadHost(String host) {
    if (_allowAnyDownloadHost) return true;
    final candidate = host.toLowerCase();
    return {..._allowedDownloadHosts, ..._moreDownloadHosts}.any((allowed) {
      final domain = allowed.toLowerCase();
      return candidate == domain || candidate.endsWith('.$domain');
    });
  }

  /// Hosts a download link may open besides the ones given at construction,
  /// replacing any set before. Only for hosts the app has verified itself
  /// (for example a list signed with its release key), never straight from
  /// the config the link comes from.
  void setMoreDownloadHosts(Set<String> hosts) {
    if (setEquals(hosts, _moreDownloadHosts)) return;
    _moreDownloadHosts = Set.unmodifiable(hosts);
    if (!_disposed) notifyListeners();
  }

  /// Open the platform download URL externally; false if none/failed.
  Future<bool> openDownload() async {
    final uri = downloadUri;
    if (uri == null) return false;
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }

  Future<void> _applyManifest(UpdateManifest manifest) async {
    manifest = manifest.mergeFloor(_sessionFloor);
    if (manifest == _manifest) {
      await _persist(manifest);
      return;
    }
    _manifest = manifest;
    await _persist(manifest);
    final before = _status;
    _recompute();
    if (_status == before && !_disposed) notifyListeners();
  }

  Future<void> _persist(UpdateManifest manifest) async {
    try {
      await _store.saveCachedManifest(manifest.toJson());
    } catch (_) {}
  }

  void _recompute() {
    final policyStatus = resolveUpdateStatus(
      currentVersion: _currentVersion,
      manifest: _manifest,
      skippedVersion: _skippedVersion,
    );
    final next = _serverForced ? UpdateStatus.forced : policyStatus;
    if (next != _status) {
      _status = next;
      if (next != UpdateStatus.forced) _offlineContinued = false;
      if (!_disposed) notifyListeners();
    }
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
