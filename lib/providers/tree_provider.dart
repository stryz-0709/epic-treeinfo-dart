import 'package:flutter/material.dart';
import '../models/tree_model.dart';
import '../services/supabase_service.dart';
import '../services/earthranger_auth.dart';

class TreeProvider extends ChangeNotifier {
  final SupabaseService _supabase;
  final EarthRangerAuth _erAuth;

  TreeModel? _currentTree;
  bool _isLoading = false;
  String? _error;
  bool _notFound = false;

  TreeProvider({required SupabaseService supabaseService, required EarthRangerAuth earthRangerAuth})
      : _supabase = supabaseService,
        _erAuth = earthRangerAuth;

  TreeModel? get currentTree => _currentTree;
  bool get isLoading => _isLoading;
  String? get error => _error;
  bool get notFound => _notFound;

  /// Search for a tree by NFC ID or Tree ID.
  Future<void> searchTree(String query) async {
    _isLoading = true;
    _error = null;
    _notFound = false;
    _currentTree = null;
    notifyListeners();

    try {
      // Pre-fetch EarthRanger token for image loading
      await _erAuth.getAccessToken();

      final tree = await _supabase.findTreeByNfcOrTreeId(query);

      if (tree == null) {
        _notFound = true;
      } else {
        _currentTree = tree;
      }
    } catch (e) {
      _error = e.toString();
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Update editable tree fields.
  Future<bool> updateTree({
    required String treeId,
    required String species,
    required String age,
    required String height,
    required String diameter,
    required String canopy,
    required String condition,
  }) async {
    if (_currentTree == null || _currentTree!.id == null) {
      _error = 'no_data_to_edit';
      notifyListeners();
      return false;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final updates = <String, dynamic>{};
      if (treeId.isNotEmpty) updates['tree_id'] = treeId;
      if (species.isNotEmpty) updates['tree_type'] = species;
      if (age.isNotEmpty) updates['age_years'] = age;
      if (height.isNotEmpty) updates['height_m'] = height;
      if (diameter.isNotEmpty) updates['diameter_cm'] = diameter;
      if (canopy.isNotEmpty) updates['foliage_m'] = canopy;
      if (condition.isNotEmpty) updates['status'] = condition;

      await _supabase.updateTree(_currentTree!.id!, updates);

      // Update local model
      _currentTree = _currentTree!.copyWith(
        treeId: treeId.isNotEmpty ? treeId : null,
        species: species.isNotEmpty ? species : null,
        age: age.isNotEmpty ? age : null,
        height: height.isNotEmpty ? height : null,
        diameter: diameter.isNotEmpty ? diameter : null,
        canopy: canopy.isNotEmpty ? canopy : null,
        condition: condition.isNotEmpty ? condition : null,
      );

      _isLoading = false;
      notifyListeners();
      return true;
    } catch (e) {
      _error = e.toString();
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Refresh current tree data.
  Future<void> refresh() async {
    final nfcId = _currentTree?.nfcId ?? _currentTree?.treeId;
    if (nfcId == null) return;
    await searchTree(nfcId);
  }

  void clear() {
    _currentTree = null;
    _error = null;
    _notFound = false;
    notifyListeners();
  }
}
