import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/tree_model.dart';

/// Supabase PostgREST client – mirrors the Java SupabaseClient.
class SupabaseService {
  final String baseUrl;
  final String apiKey;

  SupabaseService({required this.baseUrl, required this.apiKey}) {
    if (_looksLikeMissingOrPlaceholderUrl(baseUrl)) {
      throw ArgumentError(
        'SUPABASE_URL is not configured for mobile. Set a real value in mobile/.env (for example: https://<project-ref>.supabase.co).',
      );
    }

    if (_looksLikeMissingOrPlaceholderAnonKey(apiKey)) {
      throw ArgumentError(
        'SUPABASE_ANON_KEY is not configured for mobile. Set your project anon key in mobile/.env.',
      );
    }

    if (_looksLikeServiceRoleKey(apiKey)) {
      throw ArgumentError(
        'SUPABASE_ANON_KEY is required on mobile. Service-role keys are forbidden.',
      );
    }
  }

  bool _looksLikeMissingOrPlaceholderUrl(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (normalized.contains('your-project.supabase.co')) return true;
    if (!normalized.startsWith('http://') &&
        !normalized.startsWith('https://')) {
      return true;
    }
    return false;
  }

  bool _looksLikeMissingOrPlaceholderAnonKey(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return true;
    if (normalized.contains('your-supabase-anon-key')) return true;
    return false;
  }

  bool _looksLikeServiceRoleKey(String key) {
    final normalized = key.toLowerCase();
    return normalized.contains('service_role') ||
        normalized.contains('c2vydmljzv9yb2xl');
  }

  Map<String, String> get _headers => {
        'apikey': apiKey,
        'Authorization': 'Bearer $apiKey',
        'Accept': 'application/json',
        'Content-Type': 'application/json',
      };

  /// Find a tree by NFC ID or Tree ID.
  Future<TreeModel?> findTreeByNfcOrTreeId(String queryId) async {
    final encoded = Uri.encodeComponent(queryId);
    final url =
        '$baseUrl/rest/v1/trees?or=(nfc_id.ilike.$encoded,tree_id.ilike.$encoded)&limit=1';

    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw SupabaseException(response.statusCode, response.body);
    }

    final List<dynamic> data = jsonDecode(response.body);
    if (data.isEmpty) return null;
    return TreeModel.fromJson(data[0] as Map<String, dynamic>);
  }

  /// Update editable fields of a tree by its DB row ID.
  Future<void> updateTree(int treeDbId, Map<String, dynamic> updates) async {
    final url = '$baseUrl/rest/v1/trees?id=eq.$treeDbId';

    final response = await http.patch(
      Uri.parse(url),
      headers: {
        ..._headers,
        'Prefer': 'return=minimal',
      },
      body: jsonEncode(updates),
    );

    if (response.statusCode != 200 && response.statusCode != 204) {
      throw SupabaseException(response.statusCode, response.body);
    }
  }

  /// Get all trees (ordered by tree_id).
  Future<List<TreeModel>> getAllTrees() async {
    final url = '$baseUrl/rest/v1/trees?order=tree_id.asc';
    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw SupabaseException(response.statusCode, response.body);
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((e) => TreeModel.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Get all rows from `trees` as raw JSON maps.
  ///
  /// Used by UI flows that need to detect whether optional analytics columns
  /// exist in Supabase and compute dashboard metrics directly from table data.
  Future<List<Map<String, dynamic>>> getAllTreesRaw() async {
    final url = '$baseUrl/rest/v1/trees?select=*&order=tree_id.asc';
    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode != 200) {
      throw SupabaseException(response.statusCode, response.body);
    }

    final List<dynamic> data = jsonDecode(response.body);
    return data
        .map((e) => Map<String, dynamic>.from(e as Map<String, dynamic>))
        .toList();
  }

  /// Check whether a specific column exists in `trees`.
  ///
  /// PostgREST returns HTTP 400 for unknown selected columns.
  Future<bool> hasTreeColumn(String columnName) async {
    final url = '$baseUrl/rest/v1/trees?select=$columnName&limit=1';
    final response = await http.get(Uri.parse(url), headers: _headers);

    if (response.statusCode == 200) {
      return true;
    }

    if (response.statusCode == 400) {
      return false;
    }

    throw SupabaseException(response.statusCode, response.body);
  }
}

class SupabaseException implements Exception {
  final int statusCode;
  final String body;

  SupabaseException(this.statusCode, this.body);

  @override
  String toString() =>
      'SupabaseException($statusCode): ${body.length > 200 ? '${body.substring(0, 200)}…' : body}';
}
