import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mobile_api_service.dart';
import '../widgets/glass_widgets.dart';

class ForestCompartmentManagementScreen extends StatefulWidget {
  const ForestCompartmentManagementScreen({super.key});

  @override
  State<ForestCompartmentManagementScreen> createState() =>
      _ForestCompartmentManagementScreenState();
}

class _ForestCompartmentManagementScreenState
    extends State<ForestCompartmentManagementScreen> {
  static const Color _green = Color(0xFF2E7D32);
  static const Color _orange = Color(0xFFB54708);
  static const Color _red = Color(0xFFB42318);
  static const Color _darkText = Color(0xFF1B2838);
  static const Color _grayText = Color(0xFF475467);

  List<MobileForestCompartment> _compartments = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadCompartments();
    });
  }

  Future<void> _loadCompartments() async {
    final auth = context.read<AuthProvider>();
    final api = context.read<MobileApiService>();
    final token = auth.mobileAccessToken?.trim() ?? '';

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'empty_token';
      });
      return;
    }

    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final list = await api.fetchForestCompartments(accessToken: token);
      if (!mounted) return;
      setState(() {
        _compartments = list;
        _loading = false;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Color _regionChipColor(String region) {
    final h = region.hashCode.abs();
    const palette = <Color>[
      Color(0xFFE8F5E9),
      Color(0xFFFFF3E0),
      Color(0xFFE3F2FD),
      Color(0xFFF3E5F5),
      Color(0xFFE0F7FA),
    ];
    return palette[h % palette.length];
  }

  Color _regionChipFg(String region) {
    final h = region.hashCode.abs();
    const palette = <Color>[
      Color(0xFF1B5E20),
      Color(0xFFE65100),
      Color(0xFF1565C0),
      Color(0xFF6A1B9A),
      Color(0xFF006064),
    ];
    return palette[h % palette.length];
  }

  Widget _cardDecoration({required Widget child}) {
    return Container(
      decoration: glassContentDecoration(borderRadius: 16),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FB),
      appBar: AppTopToolbar(
        title: l.get('forest_compartment_title'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Divider(
            height: 1,
            color: Colors.black.withValues(alpha: 0.06),
          ),
        ),
      ),
      body: _buildBody(l.get),
    );
  }

  Widget _buildBody(String Function(String key) tr) {
    if (_loading && _compartments.isEmpty && _error == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: _green),
            const SizedBox(height: 16),
            Text(
              tr('forest_compartment_loading'),
              style: const TextStyle(fontSize: 14, color: _grayText),
            ),
          ],
        ),
      );
    }

    if (_error != null && _compartments.isEmpty) {
      return RefreshIndicator(
        color: _green,
        onRefresh: _loadCompartments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.2),
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: _red.withValues(alpha: 0.85),
            ),
            const SizedBox(height: 16),
            Text(
              tr('forest_compartment_error'),
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 15,
                color: _darkText,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_error != null && _error != 'empty_token') ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 12, color: _grayText),
              ),
            ],
          ],
        ),
      );
    }

    if (!_loading && _compartments.isEmpty) {
      return RefreshIndicator(
        color: _green,
        onRefresh: _loadCompartments,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            SizedBox(height: MediaQuery.sizeOf(context).height * 0.22),
            Icon(
              Icons.forest_outlined,
              size: 56,
              color: _grayText.withValues(alpha: 0.5),
            ),
            const SizedBox(height: 16),
            Text(
              tr('forest_compartment_empty'),
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 15, color: _grayText),
            ),
          ],
        ),
      );
    }

    return Stack(
      children: [
        RefreshIndicator(
          color: _green,
          onRefresh: _loadCompartments,
          child: ListView.separated(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
            physics: const AlwaysScrollableScrollPhysics(),
            itemCount: _compartments.length,
            separatorBuilder: (_, __) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final c = _compartments[index];
              final pct = c.resolutionPct.clamp(0, 100) / 100.0;
              final region = c.region.trim();
              final showRegion = region.isNotEmpty;

              return Material(
                color: Colors.transparent,
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () {
                    HapticFeedback.lightImpact();
                  },
                  child: _cardDecoration(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Expanded(
                                child: Text(
                                  c.name,
                                  style: const TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w700,
                                    color: _darkText,
                                  ),
                                ),
                              ),
                              if (showRegion)
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: _regionChipColor(region),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Text(
                                    region,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w600,
                                      color: _regionChipFg(region),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${tr('forest_compartment_area')}: ${c.areaHa.toStringAsFixed(1)} ha',
                            style: const TextStyle(
                              fontSize: 13,
                              color: _grayText,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            '${tr('forest_compartment_incidents')}: ${c.totalIncidents}',
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: _darkText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Wrap(
                            spacing: 12,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${tr('forest_compartment_resolved')}: ',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _grayText,
                                    ),
                                  ),
                                  Text(
                                    '${c.resolvedIncidents}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _green,
                                    ),
                                  ),
                                ],
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    '${tr('forest_compartment_unresolved')}: ',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      color: _grayText,
                                    ),
                                  ),
                                  Text(
                                    '${c.unresolvedIncidents}',
                                    style: const TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: _orange,
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            '${tr('forest_compartment_resolution')}: ${c.resolutionPct.clamp(0, 100)}%',
                            style: const TextStyle(
                              fontSize: 11,
                              color: _grayText,
                            ),
                          ),
                          const SizedBox(height: 6),
                          ClipRRect(
                            borderRadius: BorderRadius.circular(6),
                            child: SizedBox(
                              height: 8,
                              width: double.infinity,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  ColoredBox(
                                    color: Colors.black.withValues(alpha: 0.06),
                                  ),
                                  Align(
                                    alignment: Alignment.centerLeft,
                                    child: FractionallySizedBox(
                                      widthFactor: pct,
                                      heightFactor: 1,
                                      child: const ColoredBox(color: _green),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        if (_loading && _compartments.isNotEmpty)
          const Positioned(
            top: 8,
            left: 0,
            right: 0,
            child: Center(
              child: SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: _green,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
