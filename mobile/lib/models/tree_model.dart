/// Tree model matching the Supabase `trees` table.
class TreeModel {
  final int? id;
  final String? treeId;
  final String? species;
  final String? age;
  final String? height;
  final String? diameter;
  final String? canopy;
  final String? condition;
  final String? compartment;
  final String? estimatedValue;
  final double? latitude;
  final double? longitude;
  final String? images; // newline-separated URLs
  final String? createdAt;
  final String? creator;
  final String? lastReported;
  final String? updater;
  final String? eventStatus;
  final String? sn;
  final String? syncedAt;
  final String? nfcId;

  TreeModel({
    this.id,
    this.treeId,
    this.species,
    this.age,
    this.height,
    this.diameter,
    this.canopy,
    this.condition,
    this.compartment,
    this.estimatedValue,
    this.latitude,
    this.longitude,
    this.images,
    this.createdAt,
    this.creator,
    this.lastReported,
    this.updater,
    this.eventStatus,
    this.sn,
    this.syncedAt,
    this.nfcId,
  });

  /// Safely convert a value (possibly numeric) to String.
  static String? _toStr(dynamic v) {
    if (v == null) return null;
    final s = v.toString().trim();
    return s.isEmpty ? null : s;
  }

  factory TreeModel.fromJson(Map<String, dynamic> json) {
    return TreeModel(
      id: json['id'] as int?,
      treeId: _toStr(json['tree_id']),
      species: _toStr(json['tree_type']),
      age: _toStr(json['age_years']),
      height: _toStr(json['height_m']),
      diameter: _toStr(json['diameter_cm']),
      canopy: _toStr(json['foliage_m']),
      condition: _toStr(json['status']),
      compartment:
          _toStr(json['sub_compartment']) ??
          _toStr(json['compartment']) ??
          _toStr(json['forest_compartment']),
      estimatedValue:
          _toStr(json['estimated_value']) ??
          _toStr(json['estimated_value_vnd']) ??
          _toStr(json['value_estimate']),
      latitude: (json['latitude'] as num?)?.toDouble(),
      longitude: (json['longitude'] as num?)?.toDouble(),
      images: _toStr(json['image_urls']),
      createdAt: _toStr(json['created_at']),
      creator: _toStr(json['creator']),
      lastReported: _toStr(json['last_reported']),
      updater: _toStr(json['updater']),
      eventStatus: _toStr(json['event_state']),
      sn: _toStr(json['sn']),
      syncedAt: _toStr(json['synced_at']),
      nfcId: _toStr(json['nfc_id']),
    );
  }

  /// Helper to safely display a field with fallback.
  String display(String? value, [String fallback = 'N/A']) =>
      (value != null && value.isNotEmpty) ? value : fallback;

  /// Parse newline-separated image URLs.
  List<String> get imageUrls {
    if (images == null || images!.isEmpty) return [];
    return images!
        .split('\n')
        .map((url) {
          var clean = url.trim().replaceAll('"', '');
          if (clean.toUpperCase().startsWith('GET ')) {
            clean = clean.substring(4).trim();
          }
          if (clean.startsWith('/api/')) {
            clean = 'https://epictech.pamdas.org$clean';
          }
          return clean;
        })
        .where((url) => url.isNotEmpty)
        .toList();
  }

  TreeModel copyWith({
    int? id,
    String? treeId,
    String? species,
    String? age,
    String? height,
    String? diameter,
    String? canopy,
    String? condition,
    String? compartment,
    String? estimatedValue,
    double? latitude,
    double? longitude,
    String? images,
    String? createdAt,
    String? creator,
    String? lastReported,
    String? updater,
    String? eventStatus,
    String? sn,
    String? syncedAt,
    String? nfcId,
  }) {
    return TreeModel(
      id: id ?? this.id,
      treeId: treeId ?? this.treeId,
      species: species ?? this.species,
      age: age ?? this.age,
      height: height ?? this.height,
      diameter: diameter ?? this.diameter,
      canopy: canopy ?? this.canopy,
      condition: condition ?? this.condition,
      compartment: compartment ?? this.compartment,
      estimatedValue: estimatedValue ?? this.estimatedValue,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      images: images ?? this.images,
      createdAt: createdAt ?? this.createdAt,
      creator: creator ?? this.creator,
      lastReported: lastReported ?? this.lastReported,
      updater: updater ?? this.updater,
      eventStatus: eventStatus ?? this.eventStatus,
      sn: sn ?? this.sn,
      syncedAt: syncedAt ?? this.syncedAt,
      nfcId: nfcId ?? this.nfcId,
    );
  }
}
