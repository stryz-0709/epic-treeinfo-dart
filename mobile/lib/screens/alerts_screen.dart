import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/auth_provider.dart';
import '../providers/settings_provider.dart';
import '../services/mobile_api_service.dart';
import '../widgets/glass_widgets.dart';

class AlertsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const AlertsScreen({super.key, this.onBack});

  @override
  State<AlertsScreen> createState() => _AlertsScreenState();
}

class _AlertsScreenState extends State<AlertsScreen> {
  static const Color _greenAccent = Color(0xFF2E7D32);

  List<MobileAlert> _alerts = [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAlerts();
    });
  }

  int _alertLevelRank(String level) {
    switch (level.toLowerCase()) {
      case 'urgent':
        return 0;
      case 'warning':
        return 1;
      case 'info':
        return 2;
      default:
        return 3;
    }
  }

  (Color textColor, Color bgColor) _colorsForLevel(String alertLevel) {
    switch (alertLevel.toLowerCase()) {
      case 'urgent':
        return (
          const Color(0xFFB42318),
          const Color(0xFFFFE8E8),
        );
      case 'warning':
        return (
          const Color(0xFFB54708),
          const Color(0xFFFFF4E5),
        );
      case 'info':
      default:
        return (
          const Color(0xFF475467),
          const Color(0xFFF2F4F7),
        );
    }
  }

  String _formatOccurredAt(String? iso) {
    if (iso == null || iso.isEmpty) return '—';
    final dt = DateTime.tryParse(iso);
    if (dt == null) return iso;
    final d = dt.toLocal();
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    final hh = d.hour.toString().padLeft(2, '0');
    final min = d.minute.toString().padLeft(2, '0');
    return '$dd/$mm/${d.year} $hh:$min';
  }

  Future<void> _loadAlerts() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = null;
    });

    final auth = context.read<AuthProvider>();
    final api = context.read<MobileApiService>();
    final token = auth.mobileAccessToken?.trim() ?? '';

    if (token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _alerts = [];
        _error = context.read<SettingsProvider>().l.get('alerts_error');
      });
      return;
    }

    try {
      final raw = await api.fetchAlerts(accessToken: token);
      if (!mounted) return;
      final sorted = List<MobileAlert>.from(raw)
        ..sort((a, b) {
          final ra = _alertLevelRank(a.alertLevel);
          final rb = _alertLevelRank(b.alertLevel);
          if (ra != rb) return ra.compareTo(rb);
          final ta = DateTime.tryParse(a.occurredAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final tb = DateTime.tryParse(b.occurredAt ?? '') ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return tb.compareTo(ta);
        });
      setState(() {
        _alerts = sorted;
        _loading = false;
        _error = null;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = context.read<SettingsProvider>().l.get('alerts_error');
      });
    }
  }

  Widget _buildAlertCard(MobileAlert alert, String Function(String key) tr) {
    final (textColor, bgColor) = _colorsForLevel(alert.alertLevel);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: Colors.black.withValues(alpha: 0.06),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  alert.title.isEmpty ? '—' : alert.title,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Colors.black.withValues(alpha: 0.06),
                  ),
                ),
                child: Text(
                  alert.alertLevel.isEmpty ? '—' : alert.alertLevel,
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: textColor,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            '${tr('alerts_status_prefix')}${alert.status}',
            style: TextStyle(
              fontSize: 13,
              color: textColor.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${tr('alerts_severity_prefix')}${alert.severity.isEmpty ? '—' : alert.severity}',
            style: TextStyle(
              fontSize: 13,
              color: textColor.withValues(alpha: 0.92),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            '${tr('alerts_time_prefix')}${_formatOccurredAt(alert.occurredAt)}',
            style: TextStyle(
              fontSize: 13,
              color: textColor.withValues(alpha: 0.85),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(String Function(String key) tr) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(color: _greenAccent),
            const SizedBox(height: 16),
            Text(
              tr('alerts_loading'),
              style: TextStyle(
                fontSize: 14,
                color: Colors.black.withValues(alpha: 0.55),
              ),
            ),
          ],
        ),
      );
    }

    if (_error != null) {
      return RefreshIndicator(
        color: _greenAccent,
        onRefresh: _loadAlerts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.35,
              child: Center(
                child: Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 15,
                    color: Color(0xFF475467),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    if (_alerts.isEmpty) {
      return RefreshIndicator(
        color: _greenAccent,
        onRefresh: _loadAlerts,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(24),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.notifications_off_outlined,
                      size: 56,
                      color: Colors.black.withValues(alpha: 0.22),
                    ),
                    const SizedBox(height: 16),
                    Text(
                      tr('alerts_empty'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF475467),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _greenAccent,
      onRefresh: _loadAlerts,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 80),
        itemCount: _alerts.length,
        itemBuilder: (context, index) {
          return _buildAlertCard(_alerts[index], tr);
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l = context.watch<SettingsProvider>().l;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppTopToolbar(
        title: l.get('alerts'),
        showBackButton: true,
        onBack: widget.onBack,
      ),
      body: _buildBody(l.get),
    );
  }
}
