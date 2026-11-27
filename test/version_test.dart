import 'package:flutter_test/flutter_test.dart';
import 'package:remote_update_gate/remote_update_gate.dart';

void main() {
  group('version comparison (must match app/core/version.py)', () {
    test('component-wise, not numeric: 1.0.9 < 1.0.10', () {
      expect(versionLt('1.0.9', '1.0.10'), isTrue);
      expect(versionLt('1.0.10', '1.0.9'), isFalse);
    });

    test('zero-padded across differing depths', () {
      expect(versionLt('1.0', '1.0.1'), isTrue);
      expect(versionLt('2.0', '2.0.0'), isFalse); // equal after padding
      expect(versionLt('1.2', '1.10'), isTrue);
    });

    test('gates: only a real non-zero version gates', () {
      expect(versionGates('1.0.1'), isTrue);
      expect(versionGates('0'), isFalse);
      expect(versionGates('0.0.0'), isFalse);
      expect(versionGates(''), isFalse);
      expect(versionGates('nope'), isFalse);
    });

    test(
      'validity + fail-open on junk (parses to empty ⇒ never gates/blocks)',
      () {
        expect(isValidVersion('1.0.1'), isTrue);
        expect(isValidVersion('1.0.x'), isFalse);
        expect(isValidVersion(''), isFalse);
        expect(isValidVersion(null), isFalse);
        expect(parseVersion('1.0.x'), isEmpty);
        // A blank/invalid build must never be < a real floor in a blocking way:
        // the gate guards with isValidVersion first, but versionLt is still total.
        expect(versionLt('junk', '1.0.0'), isTrue); // [] < [1,0,0]
        expect(versionLt('1.0.0', 'junk'), isFalse);
      },
    );

    test('versionMax returns the higher', () {
      expect(versionMax('1.0.9', '1.0.10'), '1.0.10');
      expect(versionMax('2.0.0', '1.9.9'), '2.0.0');
    });

    test('an overflow-large component never throws (hot-path safety)', () {
      // Dart int.parse throws >64-bit; Python's server uses arbitrary precision.
      // parseVersion must NOT throw (it runs per-response via reportServerFloor)
      // and must fail open: an unparseable component ⇒ [] ⇒ gates nobody.
      const huge = '99999999999999999999999'; // 23 digits, overflows 64-bit int
      expect(() => parseVersion(huge), returnsNormally);
      expect(parseVersion(huge), isEmpty);
      expect(versionGates(huge), isFalse);
      expect(() => versionLt(huge, '1.0.0'), returnsNormally);
      // A dotted version with one oversized component is likewise invalid.
      expect(parseVersion('1.$huge.0'), isEmpty);
    });
  });
}
