import 'package:flutter_test/flutter_test.dart';
import 'package:treeinfo_dart/services/schedule_note_codec.dart';

void main() {
  group('ScheduleMissionNote', () {
    test('encode writes mission area and reason with tags', () {
      const note = ScheduleMissionNote(
        mission: '  Patrol boundary sector A  ',
        area: '  Zone 3  ',
        reason: '  Weather reroute  ',
      );

      expect(
        note.encode(),
        'Patrol boundary sector A\n[AREA] Zone 3\n[REASON] Weather reroute',
      );
    });

    test('encode omits empty segments', () {
      const note = ScheduleMissionNote(
        mission: 'Night patrol',
        area: '',
        reason: ' ',
      );

      expect(note.encode(), 'Night patrol');
    });

    test('fromRaw parses tagged note payload', () {
      final parsed = ScheduleMissionNote.fromRaw(
        'Night patrol\n[AREA] Buffer zone\n[REASON] Shift swap',
      );

      expect(parsed.mission, 'Night patrol');
      expect(parsed.area, 'Buffer zone');
      expect(parsed.reason, 'Shift swap');
      expect(parsed.isEmpty, isFalse);
    });

    test('fromRaw parses legacy prefixes including Vietnamese labels', () {
      final parsed = ScheduleMissionNote.fromRaw(
        'Bao ve rung\nKhu vuc: Tieu khu 12\nLy do: Dieu chinh nhan su',
      );

      expect(parsed.mission, 'Bao ve rung');
      expect(parsed.area, 'Tieu khu 12');
      expect(parsed.reason, 'Dieu chinh nhan su');
    });

    test('fromRaw preserves multi-line mission body', () {
      final parsed = ScheduleMissionNote.fromRaw(
        'Morning patrol\nUse route B\n[AREA] Sector East',
      );

      expect(parsed.mission, 'Morning patrol\nUse route B');
      expect(parsed.area, 'Sector East');
      expect(parsed.reason, '');
    });

    test('fromRaw returns empty model for blank payload', () {
      final parsed = ScheduleMissionNote.fromRaw('  \n  ');

      expect(parsed.mission, '');
      expect(parsed.area, '');
      expect(parsed.reason, '');
      expect(parsed.isEmpty, isTrue);
    });
  });
}
