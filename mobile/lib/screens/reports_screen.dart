import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/app_localizations.dart';
import '../services/mobile_api_service.dart';
import '../widgets/glass_widgets.dart';

const Color _kAccentGreen = Color(0xFF2E7D32);

class ReportsScreen extends StatefulWidget {
  const ReportsScreen({super.key});

  @override
  State<ReportsScreen> createState() => _ReportsScreenState();
}

class _ReportsScreenState extends State<ReportsScreen>
    with SingleTickerProviderStateMixin {
  static const List<String> _reportTypes = <String>[
    'forest-protection',
    'incidents',
    'work-performance',
  ];

  late TabController _tabController;
  late DateTime _fromDay;
  late DateTime _toDay;

  final Map<String, _TabReportState> _stateByType = <String, _TabReportState>{
    for (final t in _reportTypes) t: _TabReportState(),
  };

  @override
  void initState() {
    super.initState();
    final now = DateTime.now();
    _fromDay = DateTime(now.year, now.month, 1);
    _toDay = DateTime(now.year, now.month, now.day);
    _tabController = TabController(length: _reportTypes.length, vsync: this);
    _tabController.addListener(_onTabChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _loadReport(_currentReportType());
    });
  }

  void _onTabChanged() {
    if (_tabController.indexIsChanging) return;
    if (!mounted) return;
    _loadReport(_currentReportType());
  }

  String _currentReportType() => _reportTypes[_tabController.index];

  String _rangeKey() =>
      '${_fromDay.year}-${_fromDay.month}-${_fromDay.day}|${_toDay.year}-${_toDay.month}-${_toDay.day}';

  void _invalidateAllReports() {
    for (final s in _stateByType.values) {
      s.invalidate();
    }
  }

  void _applyDateRange(DateTime from, DateTime to) {
    var a = DateTime(from.year, from.month, from.day);
    var b = DateTime(to.year, to.month, to.day);
    if (b.isBefore(a)) {
      final t = a;
      a = b;
      b = t;
    }
    setState(() {
      _fromDay = a;
      _toDay = b;
      _invalidateAllReports();
    });
    _loadReport(_currentReportType());
  }

  void _setThisMonth() {
    final now = DateTime.now();
    _applyDateRange(
      DateTime(now.year, now.month, 1),
      DateTime(now.year, now.month + 1, 0),
    );
  }

  void _setThisQuarter() {
    final now = DateTime.now();
    final qStartMonth = ((now.month - 1) ~/ 3) * 3 + 1;
    final start = DateTime(now.year, qStartMonth, 1);
    final end = DateTime(now.year, qStartMonth + 3, 0);
    _applyDateRange(start, end);
  }

  void _setThisYear() {
    final now = DateTime.now();
    _applyDateRange(DateTime(now.year, 1, 1), DateTime(now.year, 12, 31));
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initialStart = _fromDay;
    final initialEnd = _toDay;
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 1, 12, 31),
      initialDateRange: DateTimeRange(start: initialStart, end: initialEnd),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: ColorScheme.light(
              primary: _kAccentGreen,
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
    );
    if (picked == null || !mounted) return;
    HapticFeedback.selectionClick();
    _applyDateRange(picked.start, picked.end);
  }

  Future<void> _loadReport(String reportType) async {
    final state = _stateByType[reportType]!;
    final key = _rangeKey();
    if (state.loading) return;
    if (state.data != null && state.fetchedRangeKey == key) return;

    final auth = context.read<AuthProvider>();
    final token = auth.mobileAccessToken?.trim() ?? '';
    if (token.isEmpty) {
      setState(() {
        state.loading = false;
        state.error = context.read<SettingsProvider>().l.get('report_error');
        state.data = null;
        state.fetchedRangeKey = null;
      });
      return;
    }

    setState(() {
      state.loading = true;
      state.error = null;
    });

    try {
      final api = context.read<MobileApiService>();
      final result = await api.fetchReport(
        accessToken: token,
        reportType: reportType,
        fromDay: _fromDay,
        toDay: _toDay,
      );
      if (!mounted) return;
      setState(() {
        state.loading = false;
        state.data = result;
        state.error = null;
        state.fetchedRangeKey = key;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        state.loading = false;
        state.data = null;
        state.error = context.read<SettingsProvider>().l.get('report_error');
        state.fetchedRangeKey = null;
      });
    }
  }

  void _retry(String reportType) {
    _stateByType[reportType]!.invalidate();
    _loadReport(reportType);
  }

  @override
  void dispose() {
    _tabController.removeListener(_onTabChanged);
    _tabController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTopToolbar(
        title: l.get('landing_function_reports'),
        bottom: TabBar(
          controller: _tabController,
          labelColor: _kAccentGreen,
          unselectedLabelColor: Colors.black54,
          indicatorColor: _kAccentGreen,
          isScrollable: true,
          tabs: <Tab>[
            Tab(text: l.get('report_forest_protection')),
            Tab(text: l.get('report_incidents')),
            Tab(text: l.get('report_work_performance')),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _DateRangeToolbar(
            l: l,
            fromDay: _fromDay,
            toDay: _toDay,
            onThisMonth: () {
              HapticFeedback.selectionClick();
              _setThisMonth();
            },
            onThisQuarter: () {
              HapticFeedback.selectionClick();
              _setThisQuarter();
            },
            onThisYear: () {
              HapticFeedback.selectionClick();
              _setThisYear();
            },
            onCustom: _pickCustomRange,
          ),
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: <Widget>[
                _ReportTabBody(
                  state: _stateByType['forest-protection']!,
                  l: l,
                  onRetry: () => _retry('forest-protection'),
                  builder: (data) => _ForestProtectionContent(data: data, l: l),
                ),
                _ReportTabBody(
                  state: _stateByType['incidents']!,
                  l: l,
                  onRetry: () => _retry('incidents'),
                  builder: (data) => _IncidentsReportContent(data: data, l: l),
                ),
                _ReportTabBody(
                  state: _stateByType['work-performance']!,
                  l: l,
                  onRetry: () => _retry('work-performance'),
                  builder: (data) =>
                      _WorkPerformanceContent(data: data, l: l),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _TabReportState {
  bool loading = false;
  String? error;
  MobileReportData? data;
  String? fetchedRangeKey;

  void invalidate() {
    loading = false;
    error = null;
    data = null;
    fetchedRangeKey = null;
  }
}

class _DateRangeToolbar extends StatelessWidget {
  const _DateRangeToolbar({
    required this.l,
    required this.fromDay,
    required this.toDay,
    required this.onThisMonth,
    required this.onThisQuarter,
    required this.onThisYear,
    required this.onCustom,
  });

  final AppLocalizations l;
  final DateTime fromDay;
  final DateTime toDay;
  final VoidCallback onThisMonth;
  final VoidCallback onThisQuarter;
  final VoidCallback onThisYear;
  final Future<void> Function() onCustom;

  String _fmt(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            '${_fmt(fromDay)} — ${_fmt(toDay)}',
            style: TextStyle(
              fontSize: 13,
              color: Colors.grey.shade700,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 8),
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: <Widget>[
                _QuickChip(label: l.get('report_this_month'), onTap: onThisMonth),
                _QuickChip(label: l.get('report_this_quarter'), onTap: onThisQuarter),
                _QuickChip(label: l.get('report_this_year'), onTap: onThisYear),
                _QuickChip(
                  label: l.get('report_custom'),
                  onTap: () => onCustom(),
                  outlined: true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickChip extends StatelessWidget {
  const _QuickChip({
    required this.label,
    required this.onTap,
    this.outlined = false,
  });

  final String label;
  final VoidCallback onTap;
  final bool outlined;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: Material(
        color: outlined ? Colors.white : _kAccentGreen.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(20),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(20),
              border: Border.all(
                color: outlined ? _kAccentGreen : Colors.grey.shade300,
              ),
            ),
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: outlined ? _kAccentGreen : Colors.black87,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ReportTabBody extends StatelessWidget {
  const _ReportTabBody({
    required this.state,
    required this.l,
    required this.onRetry,
    required this.builder,
  });

  final _TabReportState state;
  final AppLocalizations l;
  final VoidCallback onRetry;
  final Widget Function(MobileReportData data) builder;

  @override
  Widget build(BuildContext context) {
    if (state.loading && state.data == null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const CircularProgressIndicator(color: _kAccentGreen),
            const SizedBox(height: 16),
            Text(
              l.get('report_loading'),
              style: TextStyle(color: Colors.grey.shade700),
            ),
          ],
        ),
      );
    }

    if (state.error != null && state.data == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: <Widget>[
              Icon(Icons.error_outline, size: 48, color: Colors.grey.shade500),
              const SizedBox(height: 12),
              Text(
                state.error!,
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.black87),
              ),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: onRetry,
                style: FilledButton.styleFrom(
                  backgroundColor: _kAccentGreen,
                  foregroundColor: Colors.white,
                ),
                child: Text(l.get('retry')),
              ),
            ],
          ),
        ),
      );
    }

    final data = state.data;
    if (data == null) {
      return const SizedBox.shrink();
    }

    return Stack(
      children: <Widget>[
        builder(data),
        if (state.loading)
          const Positioned(
            left: 0,
            right: 0,
            top: 0,
            child: LinearProgressIndicator(
              minHeight: 2,
              color: _kAccentGreen,
              backgroundColor: Colors.transparent,
            ),
          ),
      ],
    );
  }
}

int _parseInt(dynamic v, [int fallback = 0]) {
  if (v is int) return v;
  if (v is num) return v.toInt();
  if (v is String) return int.tryParse(v) ?? fallback;
  return fallback;
}

Map<String, int> _asStringIntMap(dynamic raw) {
  if (raw is! Map) return <String, int>{};
  return raw.map(
    (dynamic k, dynamic v) => MapEntry(k.toString(), _parseInt(v)),
  );
}

List<Map<String, dynamic>> _asMapList(dynamic raw) {
  if (raw is! List) return <Map<String, dynamic>>[];
  return raw
      .whereType<Map>()
      .map(
        (Map<dynamic, dynamic> e) => e.map(
          (dynamic k, dynamic v) => MapEntry(k.toString(), v),
        ),
      )
      .toList();
}

class _ForestProtectionContent extends StatelessWidget {
  const _ForestProtectionContent({
    required this.data,
    required this.l,
  });

  final MobileReportData data;
  final AppLocalizations l;

  static const List<Color> _chipColors = <Color>[
    Color(0xFF2E7D32),
    Color(0xFF1565C0),
    Color(0xFFEF6C00),
    Color(0xFF6A1B9A),
    Color(0xFFC62828),
    Color(0xFF00838F),
  ];

  Color _chipColor(int i) => _chipColors[i % _chipColors.length];

  @override
  Widget build(BuildContext context) {
    final d = data.data;
    final total = _parseInt(d['total_incidents']);
    final resolved = _parseInt(d['resolved_incidents']);
    final unresolved = _parseInt(d['unresolved_incidents']);
    final rate = _parseInt(d['resolution_rate_pct']);
    final bySeverity = _asStringIntMap(d['by_severity']);
    final byStatus = _asStringIntMap(d['by_status']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _MetricGrid(
          children: <Widget>[
            _StatCard(
              label: l.get('report_total_incidents'),
              value: '$total',
            ),
            _StatCard(
              label: l.get('report_resolved'),
              value: '$resolved',
            ),
            _StatCard(
              label: l.get('report_unresolved'),
              value: '$unresolved',
            ),
            _StatCard(
              label: l.get('report_resolution_rate'),
              value: '$rate%',
            ),
          ],
        ),
        const SizedBox(height: 20),
        _SectionCard(
          title: l.get('report_by_severity'),
          child: _ChipMapRow(
            l: l,
            entries: bySeverity,
            colorForIndex: _chipColor,
          ),
        ),
        const SizedBox(height: 12),
        _SectionCard(
          title: l.get('report_by_status'),
          child: _ChipMapRow(
            l: l,
            entries: byStatus,
            colorForIndex: (i) => _chipColor(i + 2),
          ),
        ),
      ],
    );
  }
}

class _IncidentsReportContent extends StatelessWidget {
  const _IncidentsReportContent({
    required this.data,
    required this.l,
  });

  final MobileReportData data;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final d = data.data;
    final total = _parseInt(d['total_incidents']);
    final rows = _asMapList(d['by_ranger']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _MetricGrid(
          children: <Widget>[
            _StatCard(
              label: l.get('report_total_incidents'),
              value: '$total',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: l.get('report_by_ranger'),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l.get('not_available'),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : Column(
                  children: rows.map((Map<String, dynamic> r) {
                    final name =
                        (r['display_name'] ?? r['ranger_id'] ?? '').toString();
                    final count = _parseInt(r['incident_count']);
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade300),
                      ),
                      child: Row(
                        children: <Widget>[
                          Expanded(
                            child: Text(
                              name.isEmpty ? l.get('not_available') : name,
                              style: const TextStyle(
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                          Text(
                            '$count',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: _kAccentGreen,
                            ),
                          ),
                        ],
                      ),
                    );
                  }).toList(),
                ),
        ),
      ],
    );
  }
}

class _WorkPerformanceContent extends StatelessWidget {
  const _WorkPerformanceContent({
    required this.data,
    required this.l,
  });

  final MobileReportData data;
  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    final d = data.data;
    final totalRangers = _parseInt(d['total_rangers']);
    final totalWorkDays = _parseInt(d['total_work_days']);
    final totalCheckinDays = _parseInt(d['total_checkin_days']);
    final overallRate = _parseInt(d['overall_checkin_rate_pct']);
    final totalIncidents = _parseInt(d['total_incidents']);
    final rows = _asMapList(d['by_ranger']);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: <Widget>[
        _MetricGrid(
          children: <Widget>[
            _StatCard(
              label: l.get('report_total_rangers'),
              value: '$totalRangers',
            ),
            _StatCard(
              label: l.get('report_total_work_days'),
              value: '$totalWorkDays',
            ),
            _StatCard(
              label: l.get('report_total_checkin_days'),
              value: '$totalCheckinDays',
            ),
            _StatCard(
              label: l.get('report_overall_checkin_rate'),
              value: '$overallRate%',
            ),
            _StatCard(
              label: l.get('report_total_incidents'),
              value: '$totalIncidents',
            ),
          ],
        ),
        const SizedBox(height: 16),
        _SectionCard(
          title: l.get('report_by_ranger'),
          child: rows.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    l.get('not_available'),
                    style: TextStyle(color: Colors.grey.shade600),
                  ),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: <Widget>[
                    _WorkRangerHeader(l: l),
                    ...rows.map((Map<String, dynamic> r) {
                      final name = (r['display_name'] ?? r['ranger_id'] ?? '')
                          .toString();
                      final totalDays = _parseInt(r['total_days']);
                      final checkinDays = _parseInt(r['checkin_days']);
                      final rate = _parseInt(r['checkin_rate_pct']);
                      final incidents = _parseInt(r['incidents_found']);
                      return _WorkRangerRow(
                        name: name.isEmpty ? l.get('not_available') : name,
                        totalDays: totalDays,
                        checkinDays: checkinDays,
                        ratePct: rate,
                        incidents: incidents,
                      );
                    }),
                  ],
                ),
        ),
      ],
    );
  }
}

class _WorkRangerHeader extends StatelessWidget {
  const _WorkRangerHeader({required this.l});

  final AppLocalizations l;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              l.get('report_by_ranger'),
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              l.get('report_total_days'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              l.get('report_checkin_days'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              l.get('report_checkin_rate'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              l.get('report_incidents_found'),
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                color: Colors.grey.shade700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WorkRangerRow extends StatelessWidget {
  const _WorkRangerRow({
    required this.name,
    required this.totalDays,
    required this.checkinDays,
    required this.ratePct,
    required this.incidents,
  });

  final String name;
  final int totalDays;
  final int checkinDays;
  final int ratePct;
  final int incidents;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Expanded(
            flex: 2,
            child: Text(
              name,
              style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              '$totalDays',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              '$checkinDays',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
          Expanded(
            child: Text(
              '$ratePct%',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: _kAccentGreen,
              ),
            ),
          ),
          Expanded(
            child: Text(
              '$incidents',
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  const _MetricGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints c) {
        final w = c.maxWidth;
        final cross = w >= 520 ? 3 : 2;
        return GridView.count(
          crossAxisCount: cross,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 1.35,
          children: children,
        );
      },
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: glassContentDecoration(borderRadius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey.shade700,
              height: 1.2,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 22,
              fontWeight: FontWeight.w800,
              color: _kAccentGreen,
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.title,
    required this.child,
  });

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: glassContentDecoration(borderRadius: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            title,
            style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
              color: Colors.black87,
            ),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

class _ChipMapRow extends StatelessWidget {
  const _ChipMapRow({
    required this.l,
    required this.entries,
    required this.colorForIndex,
  });

  final AppLocalizations l;
  final Map<String, int> entries;
  final Color Function(int index) colorForIndex;

  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) {
      return Text(
        l.get('not_available'),
        style: TextStyle(color: Colors.grey.shade600),
      );
    }
    final keys = entries.keys.toList()..sort();
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: List<Widget>.generate(keys.length, (int i) {
        final k = keys[i];
        final v = entries[k]!;
        final bg = colorForIndex(i);
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          decoration: BoxDecoration(
            color: bg.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: bg.withValues(alpha: 0.45)),
          ),
          child: Text(
            '$k: $v',
            style: TextStyle(
              fontWeight: FontWeight.w600,
              color: bg.darken(),
              fontSize: 13,
            ),
          ),
        );
      }),
    );
  }
}

extension on Color {
  Color darken([double amount = .15]) {
    final hsl = HSLColor.fromColor(this);
    final l = (hsl.lightness - amount).clamp(0.0, 1.0);
    return hsl.withLightness(l).toColor();
  }
}
