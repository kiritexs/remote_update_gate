import 'package:flutter_test/flutter_test.dart';
import 'package:remote_update_gate/remote_update_gate.dart';

UpdateManifest m({String skippable = '', String unskippable = ''}) =>
    UpdateManifest(
      skippableVersion: skippable,
      unskippableVersion: unskippable,
    );

void main() {
  group('resolveUpdateStatus', () {
    test('up to date -> none', () {
      expect(
        resolveUpdateStatus(
          currentVersion: '1.0.10',
          manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
        ),
        UpdateStatus.none,
      );
      expect(
        resolveUpdateStatus(
          currentVersion: '9.0.0',
          manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
        ),
        UpdateStatus.none,
      );
    });

    test('below recommended floor -> optional', () {
      expect(
        resolveUpdateStatus(
          currentVersion: '1.0.7',
          manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
        ),
        UpdateStatus.optional,
      );
    });

    test('below required floor -> forced', () {
      expect(
        resolveUpdateStatus(
          currentVersion: '1.0.4',
          manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
        ),
        UpdateStatus.forced,
      );
    });

    test('component-wise: 1.0.9 < 1.0.10 (would be wrong as a number)', () {
      expect(
        resolveUpdateStatus(
          currentVersion: '1.0.9',
          manifest: m(unskippable: '1.0.10'),
        ),
        UpdateStatus.forced,
      );
      expect(
        resolveUpdateStatus(
          currentVersion: '1.0.10',
          manifest: m(unskippable: '1.0.10'),
        ),
        UpdateStatus.none, // equal ⇒ not below the floor
      );
    });

    test('exactly at a floor is NOT gated (strict less-than)', () {
      expect(
        resolveUpdateStatus(
          currentVersion: '1.0.5',
          manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
        ),
        UpdateStatus.optional, // == unskippable ⇒ not forced, but < skippable
      );
      expect(
        resolveUpdateStatus(
          currentVersion: '1.0.10',
          manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
        ),
        UpdateStatus.none, // == skippable ⇒ not optional
      );
    });

    group('fail-open', () {
      test('empty config never gates anyone', () {
        expect(
          resolveUpdateStatus(
            currentVersion: '1.0.0',
            manifest: UpdateManifest.empty,
          ),
          UpdateStatus.none,
        );
      });

      test('a real version against absent thresholds -> none', () {
        expect(
          resolveUpdateStatus(currentVersion: '4.2.0', manifest: m()),
          UpdateStatus.none,
        );
      });

      test('unresolvable current version (blank / invalid) is never gated', () {
        // A failed PackageInfo read yields '' — must not force-lock every user.
        expect(
          resolveUpdateStatus(
            currentVersion: '',
            manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
          ),
          UpdateStatus.none,
        );
        expect(
          resolveUpdateStatus(
            currentVersion: '1.0.x',
            manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
          ),
          UpdateStatus.none,
        );
      });
    });

    group('skip suppression (optional only)', () {
      test('skipping the current recommended floor hides it', () {
        expect(
          resolveUpdateStatus(
            currentVersion: '1.0.7',
            manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
            skippedVersion: '1.0.10',
          ),
          UpdateStatus.none,
        );
      });

      test('a higher skipped value also suppresses', () {
        expect(
          resolveUpdateStatus(
            currentVersion: '1.0.7',
            manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
            skippedVersion: '1.0.12',
          ),
          UpdateStatus.none,
        );
      });

      test(
        'prompt returns when the server raises the floor above the skip',
        () {
          expect(
            resolveUpdateStatus(
              currentVersion: '1.0.7',
              manifest: m(skippable: '1.0.11', unskippable: '1.0.5'),
              skippedVersion: '1.0.10',
            ),
            UpdateStatus.optional,
          );
        },
      );

      test('a stale skip below the current floor does NOT suppress', () {
        expect(
          resolveUpdateStatus(
            currentVersion: '1.0.7',
            manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
            skippedVersion: '1.0.8',
          ),
          UpdateStatus.optional,
        );
      });
    });

    group('forced can never be skipped', () {
      test(
        'a skip that would hide an optional prompt is ignored when forced',
        () {
          expect(
            resolveUpdateStatus(
              currentVersion: '1.0.4',
              manifest: m(skippable: '1.0.10', unskippable: '1.0.5'),
              skippedVersion: '9.9.9',
            ),
            UpdateStatus.forced,
          );
        },
      );
    });
  });

  group('UpdateManifest', () {
    test(
      'mergeFloor raises the required floor and keeps recommended above it',
      () {
        final merged = m(
          skippable: '1.0.8',
          unskippable: '1.0.5',
        ).mergeFloor('1.2.0');
        expect(merged.unskippableVersion, '1.2.0');
        expect(merged.skippableVersion, '1.2.0'); // pulled up from 1.0.8
      },
    );

    test('mergeFloor is a no-op when the floor does not rise', () {
      final base = m(skippable: '1.0.10', unskippable: '1.0.8');
      expect(identical(base.mergeFloor('1.0.8'), base), isTrue);
      expect(identical(base.mergeFloor('1.0.3'), base), isTrue);
      expect(identical(base.mergeFloor(''), base), isTrue); // blank never gates
    });

    test('urlFor prefers the platform, then fallback, then any entry', () {
      const man = UpdateManifest(
        downloadUrls: {'android': 'a', 'ios': 'i'},
        fallbackUrl: 'f',
      );
      expect(man.urlFor('android'), 'a');
      expect(man.urlFor('windows'), 'f'); // falls back
      const noFallback = UpdateManifest(downloadUrls: {'ios': 'i'});
      expect(noFallback.urlFor('android'), 'i'); // any non-empty entry
      expect(const UpdateManifest().urlFor('android'), isNull);
    });

    test('JSON round-trips', () {
      const man = UpdateManifest(
        skippableVersion: '1.0.10',
        unskippableVersion: '1.0.5',
        message: 'hi',
        downloadUrls: {'android': 'a'},
        fallbackUrl: 'f',
        latestVersion: '1.2.0',
      );
      expect(UpdateManifest.fromJson(man.toJson()), man);
    });

    test('fromJson coerces + tolerates junk (fail-open floors)', () {
      final man = UpdateManifest.fromJson({
        'skippableVersion': '1.0.10',
        'unskippableVersion': 5, // a stray number still stringifies
      });
      expect(man.skippableVersion, '1.0.10');
      expect(man.unskippableVersion, '5');
      expect(UpdateManifest.fromJson({}).unskippableVersion, ''); // fail-open
    });
  });
}
