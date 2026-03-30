import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:nfc_manager/nfc_manager.dart';
import 'package:nfc_manager/nfc_manager_android.dart';
import 'package:nfc_manager/nfc_manager_ios.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/tree_model.dart';
import '../providers/settings_provider.dart';
import '../services/app_notification.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';
import 'plant_identification_screen.dart';

class ForestResourceManagementScreen extends StatefulWidget {
  final String? initialQuery;

  const ForestResourceManagementScreen({super.key, this.initialQuery});

  @override
  State<ForestResourceManagementScreen> createState() =>
      _ForestResourceManagementScreenState();
}

class _ForestResourceManagementScreenState
    extends State<ForestResourceManagementScreen> {
  static const String _rareColumn = 'is_rare_species';
  static const String _estimatedValueColumn = 'estimated_value_vnd';
  static const String _monitoringColumn = 'is_health_monitored';

  final TextEditingController _scanInputController = TextEditingController();

  List<TreeModel> _allTrees = <TreeModel>[];
  TreeModel? _selectedTree;

  _ResourceOverviewStats _overview = const _ResourceOverviewStats.empty();
  Map<String, bool> _columnExists = <String, bool>{};
  bool _columnCheckFailed = false;

  bool _loading = true;
  String? _error;
  bool _isScanningNfc = false;
  bool _initialQueryApplied = false;

  StateSetter? _scanSheetSetState;

  @override
  void initState() {
    super.initState();
    _loadTrees();
  }

  @override
  void dispose() {
    if (Platform.isAndroid) {
      NfcManager.instance.stopSession();
    }
    AppNotification.dismiss();
    _scanInputController.dispose();
    super.dispose();
  }

  Future<void> _loadTrees() async {
    if (!mounted) return;

    setState(() {
      _loading = true;
      _error = null;
    });

    final supabase = context.read<SupabaseService>();

    try {
      final rawRows = await supabase.getAllTreesRaw();
      final trees = rawRows
          .map((row) => TreeModel.fromJson(row))
          .toList(growable: false);

      var columnExists = _columnExists;
      var columnCheckFailed = _columnCheckFailed;

      if (columnExists.isEmpty && !columnCheckFailed) {
        try {
          final checks = await Future.wait<bool>([
            supabase.hasTreeColumn(_rareColumn),
            supabase.hasTreeColumn(_estimatedValueColumn),
            supabase.hasTreeColumn(_monitoringColumn),
          ]);

          columnExists = <String, bool>{
            _rareColumn: checks[0],
            _estimatedValueColumn: checks[1],
            _monitoringColumn: checks[2],
          };
        } catch (_) {
          columnCheckFailed = true;
        }
      }

      final overview = _buildOverview(rawRows, trees, columnExists);
      final previous = _selectedTree;
      TreeModel? selected = _matchPreviousSelection(trees, previous);

      if (!mounted) return;
      setState(() {
        _allTrees = trees;
        _selectedTree = selected;
        _overview = overview;
        _columnExists = columnExists;
        _columnCheckFailed = columnCheckFailed;
        _loading = false;
        _error = null;
      });

      final initialQuery = widget.initialQuery?.trim();
      if (!_initialQueryApplied &&
          initialQuery != null &&
          initialQuery.isNotEmpty) {
        _initialQueryApplied = true;
        unawaited(_selectTreeFromQuery(initialQuery, showFeedback: false));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  _ResourceOverviewStats _buildOverview(
    List<Map<String, dynamic>> rows,
    List<TreeModel> trees,
    Map<String, bool> columnExists,
  ) {
    int? rareSpecies;
    if (columnExists[_rareColumn] == true) {
      final rareSet = <String>{};
      for (final row in rows) {
        if (_toBool(row[_rareColumn])) {
          final species =
              _asString(row['tree_type']) ?? _asString(row['species']);
          if (species != null && species.isNotEmpty) {
            rareSet.add(species);
          }
        }
      }
      rareSpecies = rareSet.length;
    }

    double? estimatedValue;
    if (columnExists[_estimatedValueColumn] == true) {
      var sum = 0.0;
      for (final row in rows) {
        sum += _toDouble(row[_estimatedValueColumn]);
      }
      estimatedValue = sum;
    }

    int? monitoringCount;
    if (columnExists[_monitoringColumn] == true) {
      monitoringCount = rows
          .where((row) => _toBool(row[_monitoringColumn]))
          .length;
    }

    return _ResourceOverviewStats(
      totalTrees: trees.length,
      rareSpecies: rareSpecies,
      estimatedValueVnd: estimatedValue,
      monitoringCount: monitoringCount,
    );
  }

  TreeModel? _matchPreviousSelection(
    List<TreeModel> trees,
    TreeModel? previous,
  ) {
    if (previous == null) return null;

    for (final tree in trees) {
      if (tree.id != null && previous.id != null && tree.id == previous.id) {
        return tree;
      }
    }

    final prevNfc = (previous.nfcId ?? '').trim().toLowerCase();
    final prevTreeId = (previous.treeId ?? '').trim().toLowerCase();

    for (final tree in trees) {
      final nfc = (tree.nfcId ?? '').trim().toLowerCase();
      final treeId = (tree.treeId ?? '').trim().toLowerCase();
      if ((prevNfc.isNotEmpty && nfc == prevNfc) ||
          (prevTreeId.isNotEmpty && treeId == prevTreeId)) {
        return tree;
      }
    }

    return null;
  }

  Future<bool> _selectTreeFromQuery(
    String query, {
    bool showFeedback = true,
  }) async {
    final l = context.read<SettingsProvider>().l;
    final normalized = query.trim();

    if (normalized.isEmpty) {
      if (showFeedback) {
        AppNotification.showTop(
          context,
          message: l.get('resource_scan_empty'),
          type: AppNotificationType.error,
        );
      }
      return false;
    }

    TreeModel? tree = _findLocalTree(normalized);
    tree ??= await _lookupTreeRemote(normalized);

    if (!mounted) return false;

    if (tree == null) {
      if (showFeedback) {
        AppNotification.showTop(
          context,
          message: l.get('resource_scan_no_match'),
          type: AppNotificationType.error,
        );
      }
      return false;
    }

    if (!mounted) return false;
    final selectedTree = tree;
    setState(() {
      _selectedTree = selectedTree;
      final exists = _allTrees.any((t) {
        if (t.id != null && selectedTree.id != null) {
          return t.id == selectedTree.id;
        }
        return (t.nfcId ?? '').trim().toLowerCase() ==
                (selectedTree.nfcId ?? '').trim().toLowerCase() ||
            (t.treeId ?? '').trim().toLowerCase() ==
                (selectedTree.treeId ?? '').trim().toLowerCase();
      });
      if (!exists) {
        _allTrees = [selectedTree, ..._allTrees];
      }
    });

    if (showFeedback) {
      AppNotification.showTop(
        context,
        message: l.get('resource_scan_loaded'),
        type: AppNotificationType.success,
      );
    }

    return true;
  }

  TreeModel? _findLocalTree(String query) {
    final q = query.trim().toLowerCase();

    for (final tree in _allTrees) {
      final nfc = (tree.nfcId ?? '').trim().toLowerCase();
      final id = (tree.treeId ?? '').trim().toLowerCase();

      if (nfc == q || id == q || nfc.contains(q) || id.contains(q)) {
        return tree;
      }
    }
    return null;
  }

  Future<TreeModel?> _lookupTreeRemote(String query) async {
    try {
      return await context.read<SupabaseService>().findTreeByNfcOrTreeId(query);
    } catch (_) {
      return null;
    }
  }

  void _refreshSheet() {
    final setter = _scanSheetSetState;
    if (setter != null) setter(() {});
  }

  Future<void> _startNfcScan() async {
    if (_isScanningNfc) return;

    final l = context.read<SettingsProvider>().l;

    if (Theme.of(context).platform == TargetPlatform.iOS) {
      AppNotification.showTop(
        context,
        message: l.get('nfc_ios_unavailable_temp'),
      );
      return;
    }

    final availability = await NfcManager.instance.checkAvailability();
    if (!mounted) return;
    if (availability != NfcAvailability.enabled) {
      AppNotification.showTop(
        context,
        message: l.get('nfc_unavailable_error'),
        type: AppNotificationType.error,
      );
      return;
    }

    AppNotification.showTop(
      context,
      message: l.get('nfc_scan_prompt'),
      duration: null,
    );

    setState(() => _isScanningNfc = true);
    _refreshSheet();

    NfcManager.instance.startSession(
      pollingOptions: {
        NfcPollingOption.iso14443,
        NfcPollingOption.iso15693,
        NfcPollingOption.iso18092,
      },
      onDiscovered: (NfcTag tag) async {
        NfcManager.instance.stopSession();
        AppNotification.dismiss();

        if (!mounted) return;
        setState(() => _isScanningNfc = false);
        _refreshSheet();

        final uid = _extractUid(tag);
        if (uid == null || uid.isEmpty) {
          AppNotification.showTop(
            context,
            message: l.get('nfc_uid_read_error'),
            type: AppNotificationType.error,
          );
          return;
        }

        _scanInputController.text = uid;
        _refreshSheet();
        final selected = await _selectTreeFromQuery(uid);

        if (selected && mounted && _scanSheetSetState != null) {
          Navigator.of(context).maybePop();
        }
      },
      onSessionErrorIos: (_) async {
        AppNotification.dismiss();
        if (!mounted) return;
        setState(() => _isScanningNfc = false);
        _refreshSheet();
      },
      alertMessageIos: l.get('nfc_scan_prompt'),
    );
  }

  void _stopNfcScan() {
    if (Theme.of(context).platform != TargetPlatform.iOS) {
      NfcManager.instance.stopSession();
    }
    AppNotification.dismiss();
    if (!mounted) return;
    setState(() => _isScanningNfc = false);
    _refreshSheet();
  }

  String? _extractUid(NfcTag tag) {
    List<int>? uidBytes;

    if (Theme.of(context).platform == TargetPlatform.android) {
      final androidTag = NfcTagAndroid.from(tag);
      if (androidTag != null) {
        uidBytes = androidTag.id.toList();
      }
    } else if (Theme.of(context).platform == TargetPlatform.iOS) {
      final mifare = MiFareIos.from(tag);
      final iso7816 = Iso7816Ios.from(tag);
      final iso15693 = Iso15693Ios.from(tag);
      final felica = FeliCaIos.from(tag);

      if (mifare != null) {
        uidBytes = mifare.identifier.toList();
      } else if (iso7816 != null) {
        uidBytes = iso7816.identifier.toList();
      } else if (iso15693 != null) {
        uidBytes = iso15693.identifier.toList();
      } else if (felica != null) {
        uidBytes = felica.currentIDm.toList();
      }
    }

    if (uidBytes == null || uidBytes.isEmpty) return null;

    return uidBytes
        .map((e) => e.toRadixString(16).padLeft(2, '0'))
        .join('')
        .toUpperCase();
  }

  Future<void> _showScanPopup() async {
    final l = context.read<SettingsProvider>().l;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            _scanSheetSetState = setSheetState;
            final insetBottom = MediaQuery.viewInsetsOf(context).bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(12, 0, 12, insetBottom + 12),
              child: GlassCard(
                borderRadius: 20,
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      l.get('resource_scan_popup_title'),
                      style: const TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF1B2838),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LightTextField(
                      controller: _scanInputController,
                      hintText: l.get('resource_scan_input_hint'),
                      prefixIcon: Icons.nfc_rounded,
                    ),
                    const SizedBox(height: 10),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isScanningNfc
                                ? _stopNfcScan
                                : _startNfcScan,
                            icon: Icon(
                              _isScanningNfc ? Icons.nfc : Icons.nfc_outlined,
                            ),
                            label: Text(
                              _isScanningNfc
                                  ? l.get('resource_scan_stop')
                                  : l.get('resource_scan_start'),
                            ),
                            style: OutlinedButton.styleFrom(
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: () async {
                              final ok = await _selectTreeFromQuery(
                                _scanInputController.text,
                              );
                              if (ok && sheetContext.mounted) {
                                Navigator.of(sheetContext).pop();
                              }
                            },
                            icon: const Icon(Icons.search_rounded),
                            label: Text(l.get('resource_scan_fetch')),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.accentGreen,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 11),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

    _scanSheetSetState = null;
    if (_isScanningNfc) {
      _stopNfcScan();
    }
  }

  bool _toBool(dynamic value) {
    if (value is bool) return value;
    if (value is num) return value != 0;
    final s = value?.toString().trim().toLowerCase();
    return s == 'true' || s == '1' || s == 'yes' || s == 'y' || s == 't';
  }

  String? _asString(dynamic value) {
    if (value == null) return null;
    final s = value.toString().trim();
    return s.isEmpty ? null : s;
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();

    var source = value.toString().trim();
    if (source.isEmpty) return 0;

    source = source.replaceAll(RegExp(r'[^0-9,.-]'), '');
    if (source.isEmpty) return 0;

    if (source.contains(',') && !source.contains('.')) {
      source = source.replaceAll(',', '.');
    } else {
      source = source.replaceAll(',', '');
    }

    return double.tryParse(source) ?? 0;
  }

  String _formatVnd(dynamic l, double? amount) {
    if (amount == null) return l.get('resource_stat_missing');
    if (amount >= 1000000000) {
      return '${(amount / 1000000000).toStringAsFixed(1)} ${l.get('resource_currency_billion')}';
    }
    if (amount >= 1000000) {
      return '${(amount / 1000000).toStringAsFixed(1)} ${l.get('resource_currency_million')}';
    }
    return '${amount.toStringAsFixed(0)} VND';
  }

  String _treeIdLabel(TreeModel tree, dynamic l) {
    final id = (tree.treeId ?? '').trim();
    if (id.isNotEmpty) return id;
    final nfc = (tree.nfcId ?? '').trim();
    if (nfc.isNotEmpty) return nfc;
    return l.get('not_available');
  }

  String _displayValue(String? value, String fallback) {
    final normalized = value?.trim() ?? '';
    return normalized.isEmpty ? fallback : normalized;
  }

  bool _hasCoordinates(TreeModel? tree) =>
      tree?.latitude != null && tree?.longitude != null;

  String _coordinatesLabel(TreeModel? tree, dynamic l) {
    if (!_hasCoordinates(tree)) return l.get('not_available');
    return '${tree!.latitude!.toStringAsFixed(6)}, ${tree.longitude!.toStringAsFixed(6)}';
  }

  Future<void> _openTreeInMaps(TreeModel tree, dynamic l) async {
    if (!_hasCoordinates(tree)) return;

    final latitude = tree.latitude!;
    final longitude = tree.longitude!;
    final label = Uri.encodeComponent(_treeIdLabel(tree, l));

    final uri = Platform.isIOS
        ? Uri.parse('https://maps.apple.com/?ll=$latitude,$longitude&q=$label')
        : Uri.parse('geo:$latitude,$longitude?q=$latitude,$longitude($label)');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      return;
    }

    final webUri = Uri.parse(
      'https://www.google.com/maps/search/?api=1&query=$latitude,$longitude',
    );
    await launchUrl(webUri, mode: LaunchMode.externalApplication);
  }

  Widget _buildTopStatsCard(dynamic l) {
    Widget statItem({
      required IconData icon,
      required String title,
      required String value,
      Color iconColor = const Color(0xFF2E7D32),
    }) {
      return Expanded(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 17, color: iconColor),
            const SizedBox(height: 4),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color(0xFF475467),
                height: 1.12,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: Color(0xFF101828),
              ),
            ),
          ],
        ),
      );
    }

    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
      child: Row(
        children: [
          statItem(
            icon: Icons.forest_rounded,
            title: l.get('resource_total_valuable_trees'),
            value: '${_overview.totalTrees}',
          ),
          _buildStatDivider(),
          statItem(
            icon: Icons.diamond_outlined,
            iconColor: const Color(0xFFB54708),
            title: l.get('resource_rare_species_count'),
            value:
                _overview.rareSpecies?.toString() ??
                l.get('resource_stat_missing'),
          ),
          _buildStatDivider(),
          statItem(
            icon: Icons.monetization_on_outlined,
            title: l.get('resource_total_estimated_value'),
            value: _formatVnd(l, _overview.estimatedValueVnd),
          ),
          _buildStatDivider(),
          statItem(
            icon: Icons.health_and_safety_outlined,
            iconColor: const Color(0xFF2E7D32),
            title: l.get('resource_health_monitoring'),
            value:
                _overview.monitoringCount?.toString() ??
                l.get('resource_stat_missing'),
          ),
        ],
      ),
    );
  }

  Widget _buildStatDivider() {
    return Container(
      width: 1,
      height: 74,
      margin: const EdgeInsets.symmetric(horizontal: 8),
      color: Colors.black.withValues(alpha: 0.08),
    );
  }

  Widget _buildOverviewInfoCard(dynamic l) {
    final tree = _selectedTree;
    return GlassCard(
      borderRadius: 18,
      padding: const EdgeInsets.fromLTRB(12, 14, 12, 12),
      child: _buildOverviewInfoContent(tree, l),
    );
  }

  void _openPlantIdentificationPage() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const PlantIdentificationScreen(),
      ),
    );
  }

  Widget _buildActionButtons(dynamic l) {
    return Row(
      children: [
        Expanded(
          child: ElevatedButton.icon(
            onPressed: _showScanPopup,
            icon: const Icon(Icons.nfc_rounded, size: 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                l.get('resource_scan_nfc'),
                maxLines: 1,
                softWrap: false,
              ),
            ),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF2E7D32),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _openPlantIdentificationPage,
            icon: const Icon(Icons.local_florist_rounded, size: 18),
            label: FittedBox(
              fit: BoxFit.scaleDown,
              child: Text(
                l.get('resource_identify_plant'),
                maxLines: 1,
                softWrap: false,
              ),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF2E7D32),
              side: const BorderSide(color: Color(0x552E7D32)),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildScanPromptCard(dynamic l, {double minHeight = 0}) {
    return Container(
      constraints: BoxConstraints(minHeight: minHeight),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 18),
      decoration: BoxDecoration(
        color: const Color(0x0F2E7D32),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x332E7D32)),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.nfc_rounded, size: 28, color: Color(0xFF2E7D32)),
          const SizedBox(height: 8),
          Text(
            l.get('resource_scan_detail_prompt'),
            textAlign: TextAlign.center,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF1B2838),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverviewInfoContent(TreeModel? tree, dynamic l) {
    if (tree == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.get('resource_overview_title'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2838),
            ),
          ),
          const SizedBox(height: 10),
          _buildScanPromptCard(l, minHeight: 112),
        ],
      );
    }

    final species = (tree.species ?? '').trim();
    final id = _treeIdLabel(tree, l);
    final condition = (tree.condition ?? '').trim();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          l.get('resource_overview_title'),
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w800,
            color: Color(0xFF1B2838),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: _buildTreeImage(tree),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '${species.isEmpty ? l.get('resource_species_unknown') : species} • $id',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFF101828),
                      height: 1.1,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0x1A2E7D32),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: const Color(0x552E7D32)),
                    ),
                    child: Text(
                      condition.isEmpty
                          ? l.get('resource_condition_unknown')
                          : condition,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                        color: Color(0xFF2E7D32),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _metricChip(
                        icon: Icons.schedule,
                        label: l.get('resource_age'),
                        value: _displayValue(tree.age, l.get('not_available')),
                      ),
                      _metricChip(
                        icon: Icons.height,
                        label: l.get('resource_height'),
                        value: _displayValue(
                          tree.height,
                          l.get('not_available'),
                        ),
                      ),
                      _metricChip(
                        icon: Icons.straighten,
                        label: l.get('resource_trunk_diameter'),
                        value: _displayValue(
                          tree.diameter,
                          l.get('not_available'),
                        ),
                      ),
                      _metricChip(
                        icon: Icons.park,
                        label: l.get('resource_canopy'),
                        value: _displayValue(
                          tree.canopy,
                          l.get('not_available'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildTreeImage(TreeModel? tree) {
    if (tree != null && tree.imageUrls.isNotEmpty) {
      return Image.network(
        tree.imageUrls.first,
        width: 140,
        height: 112,
        fit: BoxFit.cover,
        errorBuilder: (_, error, stackTrace) => _fallbackTreeImage(),
      );
    }
    return _fallbackTreeImage();
  }

  Widget _fallbackTreeImage() {
    return Container(
      width: 140,
      height: 112,
      color: const Color(0x11000000),
      alignment: Alignment.center,
      child: const Icon(Icons.image_outlined, color: Color(0xFF98A2B3)),
    );
  }

  Widget _infoRow({required String label, required String value}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 11,
              color: Color(0xFF667085),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF1B2838),
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _metricChip({
    required IconData icon,
    required String label,
    required String value,
  }) {
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 220),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFFF4F7F2),
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.max,
          children: [
            Icon(icon, size: 14, color: const Color(0xFF2E7D32)),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                '$label: $value',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF1B2838),
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalMap(dynamic l, TreeModel? tree) {
    if (!_hasCoordinates(tree)) {
      return Container(
        height: 132,
        width: double.infinity,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: const Color(0x11000000),
          border: Border.all(color: const Color(0x22000000)),
        ),
        alignment: Alignment.center,
        child: Text(
          '${l.get('resource_map_position')}\n${l.get('not_available')}',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 13,
            color: Color(0xFF344054),
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final point = LatLng(tree!.latitude!, tree.longitude!);

    return ClipRRect(
      borderRadius: BorderRadius.circular(12),
      child: SizedBox(
        height: 132,
        width: double.infinity,
        child: FlutterMap(
          options: MapOptions(
            initialCenter: point,
            initialZoom: 15,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.none,
            ),
          ),
          children: [
            TileLayer(
                urlTemplate: 'https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png',
                subdomains: const ['a', 'b', 'c'],
                userAgentPackageName: 'com.epictech.vranger',
              maxZoom: 19,
            ),
            MarkerLayer(
              markers: [
                Marker(
                  point: point,
                  width: 40,
                  height: 40,
                  child: const Icon(
                    Icons.location_on_rounded,
                    size: 34,
                    color: Color(0xFFB42318),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTechnicalCard(dynamic l, TreeModel? tree) {
    final hasCoordinates = _hasCoordinates(tree);
    final location = _coordinatesLabel(tree, l);

    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.get('resource_technical_title'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2838),
            ),
          ),
          const SizedBox(height: 8),
          _buildTechnicalMap(l, tree),
          const SizedBox(height: 6),
          const Text(
            '© OpenStreetMap contributors',
            style: TextStyle(
              fontSize: 10,
              color: Color(0xFF667085),
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          _infoRow(label: l.get('resource_map_position'), value: location),
          if (hasCoordinates) ...[
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: () => _openTreeInMaps(tree!, l),
                icon: const Icon(Icons.open_in_new, size: 16),
                label: Text(l.get('maps')),
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF2E7D32),
                  side: const BorderSide(color: Color(0x552E7D32)),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
          const SizedBox(height: 2),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _metricChip(
                icon: Icons.schedule,
                label: l.get('resource_age'),
                value: _displayValue(tree?.age, l.get('not_available')),
              ),
              _metricChip(
                icon: Icons.height,
                label: l.get('resource_height'),
                value: _displayValue(tree?.height, l.get('not_available')),
              ),
              _metricChip(
                icon: Icons.straighten,
                label: l.get('resource_trunk_diameter'),
                value: _displayValue(tree?.diameter, l.get('not_available')),
              ),
              _metricChip(
                icon: Icons.forest,
                label: l.get('resource_canopy'),
                value: _displayValue(tree?.canopy, l.get('not_available')),
              ),
              _metricChip(
                icon: Icons.grid_view_rounded,
                label: l.get('resource_compartment'),
                value: _displayValue(tree?.compartment, l.get('not_available')),
              ),
              _metricChip(
                icon: Icons.monetization_on_outlined,
                label: l.get('resource_estimated_value'),
                value: _displayValue(
                  tree?.estimatedValue,
                  l.get('resource_estimated_value_unknown'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          _infoRow(
            label: l.get('event_status'),
            value: _displayValue(tree?.eventStatus, l.get('not_available')),
          ),
          _infoRow(
            label: l.get('sn'),
            value: _displayValue(tree?.sn, l.get('not_available')),
          ),
          _infoRow(
            label: l.get('synced_at'),
            value: _displayValue(tree?.syncedAt, l.get('not_available')),
          ),
          _infoRow(
            label: l.get('nfc_id'),
            value: _displayValue(tree?.nfcId, l.get('not_available')),
          ),
        ],
      ),
    );
  }

  Widget _buildCareCard(dynamic l, TreeModel? tree) {
    final notes = _displayValue(
      tree?.eventStatus,
      l.get('resource_special_notes_empty'),
    );

    return GlassCard(
      borderRadius: 16,
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l.get('resource_care_title'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w800,
              color: Color(0xFF1B2838),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            l.get('resource_care_history'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 6),
          _infoRow(
            label: l.get('created_at'),
            value: _displayValue(tree?.createdAt, l.get('not_available')),
          ),
          _infoRow(
            label: l.get('creator'),
            value: _displayValue(tree?.creator, l.get('not_available')),
          ),
          _infoRow(
            label: l.get('last_reported'),
            value: _displayValue(tree?.lastReported, l.get('not_available')),
          ),
          _infoRow(
            label: l.get('updater'),
            value: _displayValue(tree?.updater, l.get('not_available')),
          ),
          const SizedBox(height: 10),
          Text(
            l.get('resource_current_status'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _displayValue(tree?.condition, l.get('resource_condition_unknown')),
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF344054),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Text(
            l.get('resource_special_notes'),
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Color(0xFF101828),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            notes,
            style: const TextStyle(
              fontSize: 12,
              color: Color(0xFF344054),
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _attachmentTile(Icons.image, const Color(0xFFE8F5E9)),
              _attachmentTile(Icons.picture_as_pdf, const Color(0xFFFFEBEE)),
              _attachmentTile(Icons.table_chart, const Color(0xFFE8F5E9)),
              _attachmentTile(Icons.map_outlined, const Color(0xFFE3F2FD)),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: tree == null
                  ? null
                  : () {
                      AppNotification.showTop(
                        context,
                        message: l.get('resource_update_status_done'),
                        type: AppNotificationType.success,
                      );
                    },
              icon: const Icon(Icons.refresh_rounded),
              label: Text(l.get('resource_update_status')),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF2E7D32),
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _attachmentTile(IconData icon, Color bg) {
    return Container(
      width: 46,
      height: 40,
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0x22000000)),
      ),
      child: Icon(icon, size: 20, color: const Color(0xFF2E7D32)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;
    final selected = _selectedTree;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7F6),
      appBar: AppTopToolbar(
        title: l.get('landing_function_resource'),
        trailing: IconButton(
          onPressed: _loading ? null : _loadTrees,
          icon: const Icon(Icons.refresh_rounded),
          color: const Color(0xFF1B2838),
          tooltip: l.get('retry'),
        ),
      ),
      body: SafeArea(
        top: false,
        child: Stack(
          children: [
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Container(
                  height: 220,
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Color(0xCC2E7D32),
                        Color(0x662E7D32),
                        Color(0x002E7D32),
                      ],
                      stops: [0.0, 0.58, 1.0],
                    ),
                  ),
                ),
              ),
            ),
            RefreshIndicator(
              onRefresh: _loadTrees,
              child: ListView(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 20),
                children: [
                  _buildTopStatsCard(l),
                  const SizedBox(height: 10),
                  _buildActionButtons(l),
                  const SizedBox(height: 10),
                  _buildOverviewInfoCard(l),
                  if (selected != null) ...[
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _buildTechnicalCard(l, selected)),
                        const SizedBox(width: 10),
                        Expanded(child: _buildCareCard(l, selected)),
                      ],
                    ),
                  ],
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.only(top: 10),
                      child: Center(
                        child: CircularProgressIndicator(
                          color: AppColors.accentGreen,
                        ),
                      ),
                    ),
                  if (_error != null) ...[
                    const SizedBox(height: 10),
                    GlassCard(
                      borderRadius: 14,
                      padding: const EdgeInsets.all(12),
                      tintColor: const Color(0xFFFFEBEE),
                      child: Text(
                        _error!,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFFB42318),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResourceOverviewStats {
  final int totalTrees;
  final int? rareSpecies;
  final double? estimatedValueVnd;
  final int? monitoringCount;

  const _ResourceOverviewStats({
    required this.totalTrees,
    required this.rareSpecies,
    required this.estimatedValueVnd,
    required this.monitoringCount,
  });

  const _ResourceOverviewStats.empty()
    : totalTrees = 0,
      rareSpecies = null,
      estimatedValueVnd = null,
      monitoringCount = null;
}
