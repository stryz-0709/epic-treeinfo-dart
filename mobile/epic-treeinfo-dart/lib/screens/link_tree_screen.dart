import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../models/tree_model.dart';
import '../providers/settings_provider.dart';
import '../services/app_notification.dart';
import '../services/supabase_service.dart';
import '../theme/app_theme.dart';
import '../widgets/glass_widgets.dart';

/// Screen to pick an existing tree and link an NFC tag to it.
/// Modelled after LinkCowActivity but using the app's glass UI.
class LinkTreeScreen extends StatefulWidget {
  final String nfcId;
  const LinkTreeScreen({super.key, required this.nfcId});

  @override
  State<LinkTreeScreen> createState() => _LinkTreeScreenState();
}

class _LinkTreeScreenState extends State<LinkTreeScreen> {
  final _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();

  List<TreeModel> _allTrees = [];
  List<_TreeItem> _filteredItems = [];
  bool _isLoading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
    _fetchTrees();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    _applyFilter(_searchController.text);
  }

  Future<void> _fetchTrees() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final supabase = Provider.of<SupabaseService>(context, listen: false);
      final trees = await supabase.getAllTrees();
      if (!mounted) return;
      setState(() {
        _allTrees = trees;
        _isLoading = false;
      });
      _applyFilter(_searchController.text);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _error = e.toString();
      });
    }
  }

  void _applyFilter(String query) {
    final lowerQuery = query.toLowerCase().trim();

    final unlinked = <_TreeItem>[];
    final linked = <_TreeItem>[];

    for (final tree in _allTrees) {
      final treeId = (tree.treeId ?? '').toLowerCase();
      final species = (tree.species ?? '').toLowerCase();
      final nfcId = (tree.nfcId ?? '').toLowerCase();

      if (lowerQuery.isNotEmpty &&
          !treeId.contains(lowerQuery) &&
          !species.contains(lowerQuery) &&
          !nfcId.contains(lowerQuery)) {
        continue;
      }

      final item = _TreeItem(tree: tree);

      if (tree.nfcId == null || tree.nfcId!.isEmpty) {
        unlinked.add(item);
      } else {
        linked.add(item);
      }
    }

    final items = <_TreeItem>[];

    if (unlinked.isNotEmpty) {
      items.add(
        _TreeItem.header(
          context.read<SettingsProvider>().l.get('unlinked_trees'),
        ),
      );
      items.addAll(unlinked);
    }

    if (linked.isNotEmpty) {
      items.add(
        _TreeItem.header(
          context.read<SettingsProvider>().l.get('linked_trees'),
        ),
      );
      items.addAll(linked);
    }

    setState(() => _filteredItems = items);
  }

  Future<void> _linkTree(TreeModel tree) async {
    final l = context.read<SettingsProvider>().l;
    final supabase = Provider.of<SupabaseService>(context, listen: false);
    final existingNfc = tree.nfcId ?? '';

    // Confirm if tree already has an NFC
    if (existingNfc.isNotEmpty) {
      final proceed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
          title: Text(
            l.get('replace_nfc_title'),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
          content: Text(
            l
                .get('replace_nfc_message')
                .replaceAll('{id}', tree.treeId ?? l.get('not_available'))
                .replaceAll('{nfc}', existingNfc),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(l.get('cancel')),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.accentGreen,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(l.get('confirm')),
            ),
          ],
        ),
      );
      if (proceed != true) return;
    }

    // Perform the link
    try {
      await supabase.updateTree(tree.id!, {'nfc_id': widget.nfcId});

      if (!mounted) return;

      HapticFeedback.mediumImpact();
      AppNotification.showTop(
        context,
        message: l.get('link_success'),
        type: AppNotificationType.success,
      );

      // Navigate to the detail screen for this tree
      Navigator.of(
        context,
      ).pushReplacementNamed('/detail', arguments: widget.nfcId);
    } catch (e) {
      if (!mounted) return;
      AppNotification.showTop(
        context,
        message: '${l.get('link_failed')}: $e',
        type: AppNotificationType.error,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;
    final screenH = MediaQuery.sizeOf(context).height;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        body: Stack(
          children: [
            // ── Background image ──
            Positioned(
              top: screenH * 0.15,
              left: 0,
              right: 0,
              bottom: 0,
              child: Image.asset(
                'assets/icons/background.jpeg',
                fit: BoxFit.cover,
                alignment: Alignment.topCenter,
                errorBuilder: (_, e, s) =>
                    Container(color: const Color(0xFF1B2838)),
              ),
            ),

            // ── Gradient overlay ──
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              height: screenH * 0.55,
              child: Container(
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0.0, 0.4, 0.7, 1.0],
                    colors: [
                      Colors.white,
                      Colors.white,
                      Color(0xBBFFFFFF),
                      Color(0x00FFFFFF),
                    ],
                  ),
                ),
              ),
            ),

            // ── Content ──
            SafeArea(
              child: Column(
                children: [
                  // ── Top bar ──
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                    child: Row(
                      children: [
                        GlassCircleButton(
                          icon: Icons.arrow_back,
                          onTap: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                l.get('link_nfc_title'),
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w800,
                                  color: Color(0xFF1B2838),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                '${l.get('nfc_id')}: ${widget.nfcId}',
                                style: const TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w500,
                                  color: Color(0xFF666666),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Search bar ──
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.85),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.black.withValues(alpha: 0.08),
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: LightTextField(
                        controller: _searchController,
                        focusNode: _searchFocusNode,
                        hintText: l.get('search_tree_hint'),
                        prefixIcon: Icons.search,
                        suffixIcon: _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(
                                  Icons.close,
                                  color: Color(0xFF999999),
                                  size: 20,
                                ),
                                onPressed: () {
                                  _searchController.clear();
                                  setState(() {});
                                },
                              )
                            : null,
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),

                  // ── Tree list ──
                  Expanded(child: _buildContent(l, isDark)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent(dynamic l, bool isDark) {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.error_outline, size: 48, color: AppColors.error),
              const SizedBox(height: 12),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: TextStyle(color: AppColors.textSecondary, fontSize: 13),
              ),
              const SizedBox(height: 16),
              GreenButton(
                text: l.get('retry'),
                icon: Icons.refresh,
                onPressed: _fetchTrees,
              ),
            ],
          ),
        ),
      );
    }

    if (_filteredItems.isEmpty) {
      return Center(
        child: Text(
          l.get('no_trees_found'),
          style: TextStyle(color: AppColors.textHint, fontSize: 16),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _fetchTrees,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        itemCount: _filteredItems.length,
        itemBuilder: (context, index) {
          final item = _filteredItems[index];

          if (item.isHeader) {
            return Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 8, left: 4),
              child: Text(
                item.headerTitle!,
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF1B2838),
                ),
              ),
            );
          }

          final tree = item.tree!;
          final hasNfc = tree.nfcId != null && tree.nfcId!.isNotEmpty;

          return Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: GlassCard(
              padding: const EdgeInsets.all(16),
              child: InkWell(
                borderRadius: BorderRadius.circular(24),
                onTap: () => _linkTree(tree),
                child: Row(
                  children: [
                    // Tree icon
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.accentGreen.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Icon(
                        Icons.park_outlined,
                        color: AppColors.accentGreen,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 14),

                    // Info
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Text(
                                '${l.get('id_label')}: ',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w700,
                                  color: AppColors.textSecondary,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.accentGreen,
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  tree.treeId ?? l.get('not_available'),
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _infoChip(
                                Icons.eco_outlined,
                                tree.species ?? l.get('not_available'),
                              ),
                              const SizedBox(width: 10),
                              _infoChip(
                                Icons.straighten,
                                tree.height ?? l.get('not_available'),
                              ),
                              const Spacer(),
                              // NFC status badge
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 3,
                                ),
                                decoration: BoxDecoration(
                                  color: hasNfc
                                      ? Colors.orange.withValues(alpha: 0.12)
                                      : AppColors.accentGreen.withValues(
                                          alpha: 0.12,
                                        ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  hasNfc
                                      ? l.get('has_nfc')
                                      : l.get('no_nfc_tag'),
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                    fontStyle: FontStyle.italic,
                                    color: hasNfc
                                        ? Colors.orange
                                        : AppColors.accentGreen,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(width: 8),
                    Icon(
                      Icons.chevron_right,
                      color: AppColors.textHint,
                      size: 22,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _infoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppColors.textSecondary),
        const SizedBox(width: 3),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
        ),
      ],
    );
  }
}

/// Helper class to represent either a header or a tree item in the list.
class _TreeItem {
  final TreeModel? tree;
  final String? headerTitle;
  final bool isHeader;

  _TreeItem({required this.tree}) : headerTitle = null, isHeader = false;

  _TreeItem.header(this.headerTitle) : tree = null, isHeader = true;
}
