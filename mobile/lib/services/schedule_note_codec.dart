class ScheduleMissionNote {
  static const String _areaTag = '[AREA]';
  static const String _reasonTag = '[REASON]';

  final String mission;
  final String area;
  final String reason;

  const ScheduleMissionNote({
    this.mission = '',
    this.area = '',
    this.reason = '',
  });

  bool get isEmpty =>
      mission.trim().isEmpty && area.trim().isEmpty && reason.trim().isEmpty;

  String encode() {
    final missionText = mission.trim();
    final areaText = area.trim();
    final reasonText = reason.trim();

    final lines = <String>[];
    if (missionText.isNotEmpty) {
      lines.add(missionText);
    }
    if (areaText.isNotEmpty) {
      lines.add('$_areaTag $areaText');
    }
    if (reasonText.isNotEmpty) {
      lines.add('$_reasonTag $reasonText');
    }

    return lines.join('\n').trim();
  }

  factory ScheduleMissionNote.fromRaw(String rawNote) {
    final raw = rawNote.trim();
    if (raw.isEmpty) {
      return const ScheduleMissionNote();
    }

    final missionLines = <String>[];
    String area = '';
    String reason = '';

    final lines = raw.split('\n');
    for (final line in lines) {
      final trimmedLine = line.trim();
      if (trimmedLine.isEmpty) {
        continue;
      }

      final normalized = trimmedLine.toLowerCase();

      if (normalized.startsWith(_areaTag.toLowerCase())) {
        area = trimmedLine.substring(_areaTag.length).trim();
        continue;
      }
      if (normalized.startsWith('area:')) {
        area = trimmedLine.substring('area:'.length).trim();
        continue;
      }
      if (normalized.startsWith('khu vực:') ||
          normalized.startsWith('khu vuc:')) {
        area = trimmedLine.substring(trimmedLine.indexOf(':') + 1).trim();
        continue;
      }

      if (normalized.startsWith(_reasonTag.toLowerCase())) {
        reason = trimmedLine.substring(_reasonTag.length).trim();
        continue;
      }
      if (normalized.startsWith('reason:')) {
        reason = trimmedLine.substring('reason:'.length).trim();
        continue;
      }
      if (normalized.startsWith('lý do:') || normalized.startsWith('ly do:')) {
        reason = trimmedLine.substring(trimmedLine.indexOf(':') + 1).trim();
        continue;
      }

      missionLines.add(trimmedLine);
    }

    return ScheduleMissionNote(
      mission: missionLines.join('\n').trim(),
      area: area,
      reason: reason,
    );
  }
}
