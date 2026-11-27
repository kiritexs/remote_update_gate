import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:remote_update_gate/remote_update_gate.dart';

/// In-memory [UpdateGateStore] for driving the controller in tests.
class _MemStore implements UpdateGateStore {
  String? skipped;
  Map<String, dynamic>? manifest;

  @override
  Future<String?> loadSkippedVersion() async => skipped;
  @override
  Future<void> saveSkippedVersion(String version) async => skipped = version;
  @override
  Future<Map<String, dynamic>?> loadCachedManifest() async => manifest;
  @override
  Future<void> saveCachedManifest(Map<String, dynamic> json) async =>
      manifest = json;
}

/// Scripted [UpdateSource]: returns [next] and counts calls; while [hold]
/// is set, each fetch waits for it.
class _StubSource implements UpdateSource {
  UpdateManifest? next;
  int fetches = 0;
  Completer<void>? hold;
  bool fails = false;

  @override
  Future<UpdateManifest?> fetch() async {
    fetches++;
    await hold?.future;
    if (fails) throw StateError('offline');
    return next;
  }
}

/// A source whose fetch throws before it returns a future.
class _ThrowingSource implements UpdateSource {
  int calls = 0;

  @override
  Future<UpdateManifest?> fetch() {
    calls++;
    throw StateError('no network');
  }
}

/// A clock the tests move by hand.
class _Clock {
  DateTime now = DateTime(2026, 11, 14, 12);
  void advance(Duration by) => now = now.add(by);
  DateTime call() => now;
}

/// The hosts these tests' links use; the allowlist group checks the rule
/// itself.
const _hosts = {
  'example.com',
  'fallback.example',
  'downloads',
  'files.example',
};

Widget _app(UpdateController c) => MaterialApp(
  builder: (context, child) => UpdateGate(controller: c, child: child!),
  home: const Text('APP-CONTENT'),
);

void main() {
  testWidgets('forced update replaces the whole app with a block', (t) async {
    final c = UpdateController(
      currentVersion: '1.0.5',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    await c.submitManifest(
      const UpdateManifest(
        unskippableVersion: '1.1.0',
        message: 'Critical fix — please update.',
        downloadUrls: {'android': 'https://example.com/app.apk'},
      ),
    );

    await t.pumpWidget(_app(c));
    await t.pumpAndSettle();

    // The app content is GONE — there is no route underneath the block.
    expect(find.text('APP-CONTENT'), findsNothing);
    expect(find.text('Update required'), findsOneWidget);
    expect(find.text('Critical fix — please update.'), findsOneWidget);
    // No skip affordance on a forced update.
    expect(find.text('Skip this version'), findsNothing);
  });

  testWidgets('forced: continue-offline reveals the app; reopen re-blocks', (
    t,
  ) async {
    final c = UpdateController(
      currentVersion: '1.0.5',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    await c.submitManifest(
      const UpdateManifest(
        unskippableVersion: '1.1.0',
        downloadUrls: {'android': 'https://example.com/app.apk'},
      ),
    );

    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) => UpdateGate(
          controller: c,
          allowOfflineContinue: true,
          child: child!,
        ),
        home: const Text('APP-CONTENT'),
      ),
    );
    await t.pumpAndSettle();

    // Blocked, but an offline escape hatch is offered.
    expect(find.text('APP-CONTENT'), findsNothing);
    expect(find.text('Continue with offline content'), findsOneWidget);

    await t.tap(find.text('Continue with offline content'));
    await t.pumpAndSettle();

    // App is revealed while the status stays forced (host restricts itself).
    expect(c.status, UpdateStatus.forced);
    expect(c.offlineContinued, isTrue);
    expect(find.text('APP-CONTENT'), findsOneWidget);

    // Reopening the gate re-blocks.
    c.reopenForcedGate();
    await t.pumpAndSettle();
    expect(c.offlineContinued, isFalse);
    expect(find.text('APP-CONTENT'), findsNothing);
    expect(find.text('Update required'), findsOneWidget);
  });

  testWidgets('optional update overlays a dismissible card; skip persists', (
    t,
  ) async {
    final store = _MemStore();
    final c = UpdateController(
      currentVersion: '1.0.5',
      platform: 'android',
      store: store,
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    await c.submitManifest(
      const UpdateManifest(
        skippableVersion: '1.1.0',
        downloadUrls: {'android': 'https://example.com/app.apk'},
      ),
    );

    await t.pumpWidget(_app(c));
    await t.pumpAndSettle();

    // The app stays usable underneath the optional card.
    expect(find.text('APP-CONTENT'), findsOneWidget);
    expect(find.text('Update available'), findsOneWidget);

    await t.tap(find.text('Skip this version'));
    await t.pumpAndSettle();

    expect(find.text('Update available'), findsNothing);
    expect(store.skipped, '1.1.0'); // persisted so it stays hidden
    expect(c.status, UpdateStatus.none);
  });

  testWidgets('allowSkipOptional:false → "Later" dismisses the session only, '
      'never persists, so the card returns next launch', (t) async {
    final store = _MemStore();
    final c = UpdateController(
      currentVersion: '1.0.5',
      platform: 'android',
      store: store,
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    await c.submitManifest(
      const UpdateManifest(
        skippableVersion: '1.1.0',
        downloadUrls: {'android': 'https://example.com/app.apk'},
      ),
    );

    await t.pumpWidget(
      MaterialApp(
        builder: (context, child) =>
            UpdateGate(controller: c, allowSkipOptional: false, child: child!),
        home: const Text('APP-CONTENT'),
      ),
    );
    await t.pumpAndSettle();

    expect(find.text('Update available'), findsOneWidget);
    expect(find.text('Skip this version'), findsNothing); // no permanent skip
    expect(find.text('Later'), findsOneWidget);

    await t.tap(find.text('Later'));
    await t.pumpAndSettle();

    // Card gone for THIS session, but nothing persisted and still optional —
    // a fresh launch (new gate state) would show it again.
    expect(find.text('Update available'), findsNothing);
    expect(store.skipped, isNull);
    expect(c.status, UpdateStatus.optional);
  });

  testWidgets('offline latch: a cached forcing manifest arms on cold init', (
    t,
  ) async {
    final store = _MemStore()
      ..manifest = const UpdateManifest(
        unskippableVersion: '1.1.0',
        downloadUrls: {'android': 'https://example.com/app.apk'},
      ).toJson();

    final c = UpdateController(
      currentVersion: '1.0.5',
      platform: 'android',
      store: store,
      allowedDownloadHosts: _hosts,
    );
    await c.init(); // no network, just the cached latch

    expect(c.status, UpdateStatus.forced);

    await t.pumpWidget(_app(c));
    await t.pumpAndSettle();
    expect(find.text('APP-CONTENT'), findsNothing);
    expect(find.text('Update required'), findsOneWidget);
  });

  test(
    'markServerForced forces the gate regardless of version policy',
    () async {
      final c = UpdateController(
        currentVersion: '9.9.9', // policy alone would say "none"
        platform: 'android',
        store: _MemStore(),
        allowedDownloadHosts: _hosts,
      );
      await c.init();
      expect(c.status, UpdateStatus.none);
      c.markServerForced(); // e.g. server 426 from a revoked API key
      expect(c.status, UpdateStatus.forced);
      expect(c.isForced, isTrue);
    },
  );

  testWidgets(
    'forced with NO download URL shows the repairing state (no button)',
    (t) async {
      final c = UpdateController(
        currentVersion: '1.0.5',
        platform: 'android',
        store:
            _MemStore(), // no fallbackDownloadUrl -> hasDownloadTarget == false
      );
      await c.init();
      await c.submitManifest(
        const UpdateManifest(
          unskippableVersion: '1.1.0', // forced, but no downloadUrls at all
        ),
      );

      await t.pumpWidget(
        MaterialApp(
          builder: (context, child) => UpdateGate(
            controller: c,
            allowOfflineContinue: true,
            child: child!,
          ),
          home: const Text('APP-CONTENT'),
        ),
      );
      await t.pumpAndSettle();

      expect(find.text('Update on the way'), findsOneWidget); // repairing title
      expect(find.text('Update now'), findsNothing); // no dead button
      expect(find.text('Update required'), findsNothing);
      expect(find.text('Continue with offline content'), findsOneWidget);
    },
  );

  test('a lower refresh does not drop a floor a header raised', () async {
    final c = UpdateController(
      currentVersion: '1.1.5',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    c.reportServerFloor(
      '1.2.0',
    ); // header raises the floor → 1.1.5 < 1.2.0 forced
    expect(c.status, UpdateStatus.forced);
    // A full refresh with a LOWER floor must not un-force an in-between version.
    await c.submitManifest(const UpdateManifest(unskippableVersion: '1.0.5'));
    expect(c.status, UpdateStatus.forced);
    expect(c.manifest.unskippableVersion, '1.2.0');
  });

  test('an online refresh releases a latched client when the server clears the '
      'floor (turning enforcement off must not lock users forever)', () async {
    // Cold start re-arms a previously cached forcing manifest (offline latch).
    final store = _MemStore()
      ..manifest = const UpdateManifest(
        unskippableVersion: '5.0.0',
        downloadUrls: {'android': 'https://example.com/app.apk'},
      ).toJson();
    final c = UpdateController(
      currentVersion: '3.0.0',
      platform: 'android',
      store: store,
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    expect(c.status, UpdateStatus.forced); // latched from cache

    // Server now reports "not forced" (admin disabled enforcement). No response
    // header raised the floor this session, so the authoritative config wins
    // and the client is released instead of staying stuck until data-clear.
    await c.submitManifest(const UpdateManifest(unskippableVersion: ''));
    expect(c.status, UpdateStatus.none);
    expect(c.manifest.unskippableVersion, '');
  });

  test('reportServerFloor tolerates a garbage/overflow X-Min-Build header '
      '(hot path must never throw, and it must not gate)', () async {
    final c = UpdateController(
      currentVersion: '1.0.0',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    // The transport interceptor calls this for EVERY response header. A hostile
    // or corrupt value must not crash it, and must not force an update.
    c.reportServerFloor('99999999999999999999999'); // overflows 64-bit int
    c.reportServerFloor('not-a-version');
    c.reportServerFloor('');
    expect(c.status, UpdateStatus.none);
    expect(c.isForced, isFalse);
  });

  test(
    'openDownload falls back to the app URL when the manifest has none',
    () async {
      final c = UpdateController(
        currentVersion: '1.0.5',
        platform: 'android',
        store: _MemStore(),
        allowedDownloadHosts: _hosts,
        fallbackDownloadUrl: 'https://fallback.example/app',
      );
      await c.submitManifest(
        const UpdateManifest(
          unskippableVersion: '1.1.0', // no downloadUrls at all
        ),
      );
      expect(c.downloadUri.toString(), 'https://fallback.example/app');
    },
  );

  test('a server 426 kicks an immediate manifest fetch so the card gets its '
      'URL + message instead of a dead "on the way" state', () async {
    final source = _StubSource()
      ..next = const UpdateManifest(
        // kill-switch style: no floors, just URL + message
        message: 'Maintenance — please update',
        downloadUrls: {'android': 'https://downloads/app.apk'},
      );
    final c = UpdateController(
      currentVersion: '9.9.9',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
      source: source,
    );
    await c.init();
    expect(c.hasDownloadTarget, isFalse);

    c.markServerForced();
    expect(c.isForced, isTrue);
    await Future<void>.delayed(Duration.zero); // let the kicked refresh land
    expect(source.fetches, 1);
    expect(c.hasDownloadTarget, isTrue);
    expect(c.manifest.message, 'Maintenance — please update');
  });

  test('while forced without a URL, refresh() bypasses the throttle until a '
      'target appears', () async {
    final source = _StubSource(); // fetch yields null: no manifest yet
    final clock = _Clock();
    final c = UpdateController(
      currentVersion: '9.9.9',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
      source: source,
      clock: clock.call,
    );
    await c.init();
    c.markServerForced();
    await Future<void>.delayed(Duration.zero);
    expect(source.fetches, 1); // kicked fetch found nothing
    expect(c.hasDownloadTarget, isFalse);

    // Within a minute of the last attempt it doesn't poll again, so
    // Windows' focus changes can't flood the API.
    await c.refresh();
    expect(source.fetches, 1);

    // Admin fills in the URL; the next plain refresh (e.g. app resume) a
    // minute on must re-poll despite the 6h throttle, and heal the card.
    source.next = const UpdateManifest(
      downloadUrls: {'android': 'https://downloads/app.apk'},
    );
    clock.advance(const Duration(minutes: 1));
    await c.refresh();
    expect(source.fetches, 2);
    expect(c.hasDownloadTarget, isTrue);

    // With a target known, the throttle applies again.
    clock.advance(const Duration(minutes: 5));
    await c.refresh();
    expect(source.fetches, 2);
  });

  // A reconnect after a check that
  // applied a manifest still waits the minute, so a link that flaps every
  // ~11 s can't poll the API that fast while the card waits for a URL.
  test('while forced without a URL, a reconnect after a success still waits '
      'a minute', () async {
    final source = _StubSource()
      ..next = const UpdateManifest(message: 'Update on the way');
    final clock = _Clock();
    final c = UpdateController(
      currentVersion: '9.9.9',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
      source: source,
      clock: clock.call,
    );
    await c.init();
    c.markServerForced();
    await Future<void>.delayed(Duration.zero);
    expect(source.fetches, 1); // applied, still no URL
    expect(c.isForced, isTrue);
    expect(c.hasDownloadTarget, isFalse);

    clock.advance(const Duration(seconds: 20));
    expect(await c.refresh(reconnect: true), isFalse);
    expect(source.fetches, 1);

    clock.advance(const Duration(seconds: 40));
    expect(await c.refresh(reconnect: true), isTrue);
    expect(source.fetches, 2);
  });

  group('refresh throttles (a failure does not use up the 6 hours)', () {
    late _StubSource source;
    late _Clock clock;
    late UpdateController c;

    setUp(() {
      source = _StubSource()
        ..next = const UpdateManifest(
          downloadUrls: {'android': 'https://example.com/app.apk'},
        );
      clock = _Clock();
      c = UpdateController(
        currentVersion: '1.0.5',
        platform: 'android',
        store: _MemStore(),
        allowedDownloadHosts: _hosts,
        source: source,
        clock: clock.call,
      );
    });

    test(
      'a failed check comes back after a minute, not after 6 hours',
      () async {
        source.fails = true;
        expect(await c.refresh(), isFalse);
        expect(source.fetches, 1);

        clock.advance(const Duration(seconds: 30));
        expect(await c.refresh(), isFalse);
        expect(source.fetches, 1, reason: 'within a minute of the last try');

        source.fails = false;
        clock.advance(const Duration(seconds: 30));
        expect(await c.refresh(), isTrue);
        expect(source.fetches, 2);
      },
    );

    test('a source that answers nothing counts as a failure too', () async {
      source.next = null;
      await c.refresh();
      clock.advance(const Duration(minutes: 1));
      await c.refresh();
      expect(source.fetches, 2);
    });

    test('a success holds unforced refreshes off for 6 hours', () async {
      expect(await c.refresh(), isTrue);
      clock.advance(const Duration(hours: 5, minutes: 59));
      expect(await c.refresh(), isFalse);
      expect(source.fetches, 1);
      clock.advance(const Duration(minutes: 1));
      expect(await c.refresh(), isTrue);
      expect(source.fetches, 2);
    });

    test('forced refreshes are never held off', () async {
      await c.refresh();
      expect(await c.refresh(force: true), isTrue);
      expect(source.fetches, 2);
    });

    test(
      'refreshes that overlap share one fetch, a forced one included',
      () async {
        source.hold = Completer<void>();
        final plain = c.refresh();
        final forced = c.refresh(force: true);
        source.hold!.complete();
        expect(await Future.wait([plain, forced]), [true, true]);
        expect(source.fetches, 1);
      },
    );

    // A check made offline must not hold off the one the network coming
    // back asks for (final check 2026-11-16).
    test(
      'a reconnect is not held off by a failed attempt, only by a success',
      () async {
        source.fails = true;
        expect(await c.refresh(), isFalse);

        source.fails = false;
        clock.advance(const Duration(seconds: 20));
        expect(await c.refresh(reconnect: true), isTrue);
        expect(source.fetches, 2);

        // Applied: the 6 hours hold off a reconnect too.
        clock.advance(const Duration(minutes: 5));
        expect(await c.refresh(reconnect: true), isFalse);
        expect(source.fetches, 2);
      },
    );

    test(
      'a failed reconnect starts the retry window for a plain refresh',
      () async {
        source.fails = true;
        expect(await c.refresh(), isFalse);
        clock.advance(const Duration(seconds: 20));
        expect(await c.refresh(reconnect: true), isFalse);
        expect(source.fetches, 2, reason: 'the reconnect went to the source');

        clock.advance(const Duration(seconds: 20));
        expect(await c.refresh(), isFalse);
        expect(source.fetches, 2, reason: 'within a minute of the reconnect');
      },
    );

    // A server that keeps failing
    // under a flapping link gets one early reconnect per failed check, not
    // one every reconnect.
    test('a failed early reconnect lets no second one through', () async {
      source.fails = true;
      expect(await c.refresh(), isFalse);
      clock.advance(const Duration(seconds: 11));
      expect(await c.refresh(reconnect: true), isFalse);
      expect(source.fetches, 2, reason: 'the first reconnect went through');

      clock.advance(const Duration(seconds: 11));
      expect(await c.refresh(reconnect: true), isFalse);
      expect(source.fetches, 2, reason: 'within a minute of the early one');

      clock.advance(const Duration(seconds: 50));
      expect(await c.refresh(reconnect: true), isFalse);
      expect(source.fetches, 3, reason: 'a minute on, an ordinary attempt');
      clock.advance(const Duration(seconds: 11));
      expect(await c.refresh(reconnect: true), isFalse);
      expect(source.fetches, 4, reason: 'that one failed, so one early again');
    });

    test('a reconnect joins a refresh on its way', () async {
      source.hold = Completer<void>();
      final plain = c.refresh();
      final reconnect = c.refresh(reconnect: true);
      source.hold!.complete();
      expect(await Future.wait([plain, reconnect]), [true, true]);
      expect(source.fetches, 1);
    });

    test('a source that throws at once still ends its refresh', () async {
      final throwing = _ThrowingSource();
      final t = UpdateController(
        currentVersion: '1.0.5',
        platform: 'android',
        store: _MemStore(),
        source: throwing,
        clock: clock.call,
      );
      expect(await t.refresh(force: true), isFalse);
      expect(await t.refresh(force: true), isFalse);
      expect(throwing.calls, 2, reason: 'not stuck on the first');
    });
  });

  group(
    'download URL normalization (so a good link is never a dead button)',
    () {
      Future<UpdateController> forUrl(String url) async {
        final c = UpdateController(
          currentVersion: '1.0.5',
          platform: 'android',
          store: _MemStore(),
          allowedDownloadHosts: _hosts,
        );
        await c.submitManifest(
          UpdateManifest(
            unskippableVersion: '1.1.0',
            downloadUrls: {'android': url},
          ),
        );
        return c;
      }

      test('a scheme-less dashboard URL is treated as https', () async {
        final c = await forUrl('files.example/file/app.apk');
        expect(c.downloadUri.toString(), 'https://files.example/file/app.apk');
        expect(c.hasDownloadTarget, isTrue);
      });

      test(
        'a cleartext http URL is upgraded to https (never launched as-is)',
        () async {
          final c = await forUrl('http://example.com/app.apk');
          expect(c.downloadUri?.scheme, 'https');
          expect(c.downloadUri.toString(), 'https://example.com/app.apk');
        },
      );

      test('a store scheme is refused unless its app is allowed', () async {
        final c = await forUrl('market://details?id=com.example.app');
        expect(c.downloadUri, isNull);
        expect(c.hasDownloadTarget, isFalse);
      });

      test(
        'a hostile scheme is refused → repairing state, openDownload false',
        () async {
          final c = await forUrl('javascript:alert(1)');
          expect(c.downloadUri, isNull);
          expect(c.hasDownloadTarget, isFalse);
          expect(await c.openDownload(), isFalse);
        },
      );
    },
  );

  group('download host allowlist', () {
    Future<UpdateController> forUrl(String url, Set<String> hosts) async {
      final c = UpdateController(
        currentVersion: '1.0.5',
        platform: 'android',
        store: _MemStore(),
        allowedDownloadHosts: hosts,
      );
      await c.submitManifest(
        UpdateManifest(
          unskippableVersion: '1.1.0',
          downloadUrls: {'android': url},
        ),
      );
      return c;
    }

    test('a listed host and its subdomains are allowed', () async {
      final c = await forUrl('https://www.files.example/file/app.apk', {
        'files.example',
      });
      expect(c.downloadUri?.host, 'www.files.example');
    });

    test('any other host is refused → repairing state', () async {
      final c = await forUrl('https://files.example.evil.example/app.apk', {
        'files.example',
      });
      expect(c.downloadUri, isNull);
      expect(c.hasDownloadTarget, isFalse);
      expect(await c.openDownload(), isFalse);
    });

    test('store schemes are not host-checked: their app is', () async {
      final c = await forUrl('market://details?id=com.example.app', {
        'files.example',
      });
      expect(c.downloadUri, isNull);
    });

    // A config that can be tampered with names the link, so no hosts must
    // mean no link, not any.
    test('no hosts opens no https link', () async {
      final c = await forUrl('https://example.com/app.apk', const {});
      expect(c.downloadUri, isNull);
      expect(c.hasDownloadTarget, isFalse);
    });

    test('allowAnyDownloadHost opens any', () async {
      final c = UpdateController(
        currentVersion: '1.0.5',
        platform: 'android',
        store: _MemStore(),
        allowAnyDownloadHost: true,
      );
      await c.submitManifest(
        const UpdateManifest(
          unskippableVersion: '1.1.0',
          downloadUrls: {'android': 'https://example.com/app.apk'},
        ),
      );
      expect(c.downloadUri.toString(), 'https://example.com/app.apk');
    });

    test('setMoreDownloadHosts adds hosts, replaces them, and tells', () async {
      final c = await forUrl('https://dl.example.org/app.apk', {'example.net'});
      expect(c.downloadUri, isNull);
      var told = 0;
      c.addListener(() => told++);

      c.setMoreDownloadHosts({'example.org'});
      expect(c.downloadUri?.host, 'dl.example.org');
      expect(told, 1);

      c.setMoreDownloadHosts({'example.org'});
      expect(told, 1, reason: 'the same hosts again change nothing');

      c.setMoreDownloadHosts(const {});
      expect(c.downloadUri, isNull);
    });
  });

  group('store links (only the apps allowed)', () {
    Future<UpdateController> forUrl(
      String url, {
      Set<String> appIds = const {},
      bool any = false,
    }) async {
      final c = UpdateController(
        currentVersion: '1.0.5',
        platform: 'android',
        store: _MemStore(),
        allowedDownloadHosts: const {'example.com'},
        allowedStoreAppIds: appIds,
        allowAnyStoreLink: any,
      );
      await c.submitManifest(
        UpdateManifest(
          unskippableVersion: '1.1.0',
          downloadUrls: {'android': url},
        ),
      );
      return c;
    }

    test('a market link to an allowed app opens', () async {
      final c = await forUrl(
        'market://details?id=com.example.app',
        appIds: {'com.example.app'},
      );
      expect(c.downloadUri?.scheme, 'market');
    });

    test('a market link to another app is refused', () async {
      final c = await forUrl(
        'market://details?id=com.lookalike.app',
        appIds: {'com.example.app'},
      );
      expect(c.downloadUri, isNull);
    });

    test('with none allowed, no store link opens', () async {
      expect((await forUrl('market://details?id=a.b')).downloadUri, isNull);
      expect(
        (await forUrl('itms-apps://apps.apple.com/app/id123')).downloadUri,
        isNull,
      );
    });

    test(
      'an App Store link is allowed by its number, without the id prefix',
      () async {
        final ok = await forUrl(
          'itms-apps://apps.apple.com/app/id123',
          appIds: {'123'},
        );
        expect(ok.downloadUri?.scheme, 'itms-apps');
        final other = await forUrl(
          'itms-apps://apps.apple.com/app/id456',
          appIds: {'123'},
        );
        expect(other.downloadUri, isNull);
        final named = await forUrl(
          'itms-apps://apps.apple.com/app/my-app/id123',
          appIds: {'123'},
        );
        expect(named.downloadUri?.scheme, 'itms-apps');
        final slashed = await forUrl(
          'itms-apps://apps.apple.com/app/id123/',
          appIds: {'123'},
        );
        expect(slashed.downloadUri?.scheme, 'itms-apps');
        final slashedOther = await forUrl(
          'itms-apps://apps.apple.com/app/id456/',
          appIds: {'123'},
        );
        expect(slashedOther.downloadUri, isNull);
      },
    );

    test('allowAnyStoreLink opens any', () async {
      final c = await forUrl('market://details?id=a.b', any: true);
      expect(c.downloadUri?.scheme, 'market');
    });

    test('https links are host-checked as before', () async {
      final ok = await forUrl(
        'https://example.com/app.apk',
        appIds: {'com.example.app'},
      );
      expect(ok.downloadUri?.host, 'example.com');
      final other = await forUrl(
        'https://elsewhere.example/app.apk',
        any: true,
      );
      expect(other.downloadUri, isNull);
    });
  });

  testWidgets('the card names the host "Update now" will open', (t) async {
    final c = UpdateController(
      currentVersion: '1.0.5',
      platform: 'android',
      store: _MemStore(),
      allowedDownloadHosts: _hosts,
    );
    await c.init();
    await c.submitManifest(
      const UpdateManifest(
        unskippableVersion: '1.1.0',
        downloadUrls: {'android': 'https://example.com/app.apk'},
      ),
    );

    await t.pumpWidget(_app(c));
    await t.pumpAndSettle();

    expect(find.text('Opens example.com'), findsOneWidget);
  });
}
