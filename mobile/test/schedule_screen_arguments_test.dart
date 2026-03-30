import 'package:flutter_test/flutter_test.dart';
import 'package:treeinfo_dart/screens/schedule_screen.dart';

void main() {
  group('ScheduleManagementScreen.parseArguments', () {
    test('returns null for null and unsupported values', () {
      expect(ScheduleManagementScreen.parseArguments(null), isNull);
      expect(ScheduleManagementScreen.parseArguments(<int>[1, 2, 3]), isNull);
      expect(ScheduleManagementScreen.parseArguments('not-a-date'), isNull);
    });

    test('returns same object when already typed arguments', () {
      const args = ScheduleScreenArguments(
        focusDay: null,
        openDetails: true,
      );

      final parsed = ScheduleManagementScreen.parseArguments(args);
      expect(parsed, same(args));
    });

    test('parses DateTime input and normalizes to day precision', () {
      final parsed = ScheduleManagementScreen.parseArguments(
        DateTime(2026, 4, 8, 17, 45),
      );

      expect(parsed, isNotNull);
      expect(parsed!.openDetails, isTrue);
      expect(parsed.focusDay, DateTime(2026, 4, 8));
    });

    test('parses ISO date string input and enables openDetails', () {
      final parsed = ScheduleManagementScreen.parseArguments('2026-05-01');

      expect(parsed, isNotNull);
      expect(parsed!.openDetails, isTrue);
      expect(parsed.focusDay, DateTime(2026, 5, 1));
    });

    test('parses map with camelCase keys', () {
      final parsed = ScheduleManagementScreen.parseArguments(
        <String, Object?>{
          'focusDay': '2026-06-10',
          'openDetails': false,
        },
      );

      expect(parsed, isNotNull);
      expect(parsed!.focusDay, DateTime(2026, 6, 10));
      expect(parsed.openDetails, isFalse);
    });

    test('parses map with snake_case and day fallback keys', () {
      final parsedFromSnake = ScheduleManagementScreen.parseArguments(
        <String, Object?>{
          'focus_day': '2026-07-11',
          'open_details': 'yes',
        },
      );
      final parsedFromDay = ScheduleManagementScreen.parseArguments(
        <String, Object?>{'day': '2026-07-12', 'openDetails': '1'},
      );

      expect(parsedFromSnake, isNotNull);
      expect(parsedFromSnake!.focusDay, DateTime(2026, 7, 11));
      expect(parsedFromSnake.openDetails, isTrue);

      expect(parsedFromDay, isNotNull);
      expect(parsedFromDay!.focusDay, DateTime(2026, 7, 12));
      expect(parsedFromDay.openDetails, isTrue);
    });

    test('supports openDetails without focusDay', () {
      final parsed = ScheduleManagementScreen.parseArguments(
        <String, Object?>{'openDetails': 1},
      );

      expect(parsed, isNotNull);
      expect(parsed!.focusDay, isNull);
      expect(parsed.openDetails, isTrue);
    });

    test('returns null for map without parseable content', () {
      final parsed = ScheduleManagementScreen.parseArguments(
        <String, Object?>{'focusDay': 'invalid-date', 'openDetails': 0},
      );

      expect(parsed, isNull);
    });
  });
}
