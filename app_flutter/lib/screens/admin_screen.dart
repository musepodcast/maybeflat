import 'package:flutter/material.dart';

import '../models/admin_analytics_overview.dart';
import '../services/client_identity.dart';
import '../services/maybeflat_api.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  final MaybeflatApi _api = MaybeflatApi();
  late final TextEditingController _tokenController;

  bool _isLoading = false;
  String? _error;
  int _windowDays = 7;
  int _suspiciousWindowMinutes = 60;
  AdminAnalyticsOverview? _overview;

  @override
  void initState() {
    super.initState();
    _tokenController = TextEditingController(
      text: ClientIdentity.instance.adminToken ?? '',
    );
    if (_tokenController.text.trim().isNotEmpty) {
      _loadOverview();
    }
  }

  @override
  void dispose() {
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _loadOverview() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _error = 'Enter the admin token to load analytics.';
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final overview = await _api.loadAdminAnalyticsOverview(
        adminToken: token,
        windowDays: _windowDays,
        suspiciousWindowMinutes: _suspiciousWindowMinutes,
      );
      if (!mounted) {
        return;
      }

      ClientIdentity.instance.saveAdminToken(token);
      setState(() {
        _overview = overview;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  void _clearToken() {
    ClientIdentity.instance.clearAdminToken();
    setState(() {
      _tokenController.clear();
      _overview = null;
      _error = null;
    });
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('401')) {
      return 'The admin token was rejected.';
    }
    if (message.contains('503')) {
      return 'Admin analytics are not configured on the backend yet.';
    }
    return 'Could not load analytics overview.';
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${local.hour}:$minute';
  }

  String _formatCount(int value) => value.toString();

  @override
  Widget build(BuildContext context) {
    final overview = _overview;
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Maybeflat admin analytics',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Traffic, feature usage, repeated IP activity, and recent backend requests in one place.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF335C67),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _SectionCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SizedBox(
                          width: 320,
                          child: TextField(
                            controller: _tokenController,
                            obscureText: true,
                            decoration: const InputDecoration(
                              labelText: 'Admin token',
                              hintText: 'Set MAYBEFLAT_ADMIN_TOKEN on the backend',
                              border: OutlineInputBorder(),
                              isDense: true,
                            ),
                          ),
                        ),
                        _DropdownField<int>(
                          label: 'Window',
                          value: _windowDays,
                          options: const <int>[1, 3, 7, 14, 30],
                          labelForValue: (value) => '$value days',
                          onChanged: (value) {
                            setState(() {
                              _windowDays = value;
                            });
                          },
                        ),
                        _DropdownField<int>(
                          label: 'Suspicious IP window',
                          value: _suspiciousWindowMinutes,
                          options: const <int>[15, 30, 60, 180, 720],
                          labelForValue: (value) => '$value min',
                          onChanged: (value) {
                            setState(() {
                              _suspiciousWindowMinutes = value;
                            });
                          },
                        ),
                        FilledButton.icon(
                          onPressed: _isLoading ? null : _loadOverview,
                          icon: const Icon(Icons.refresh),
                          label: Text(_isLoading ? 'Loading...' : 'Refresh'),
                        ),
                        TextButton(
                          onPressed: _isLoading ? null : _clearToken,
                          child: const Text('Clear token'),
                        ),
                      ],
                    ),
                    if (overview != null) ...[
                      const SizedBox(height: 12),
                      Text(
                        'Last refreshed ${_formatTimestamp(overview.generatedAt)}',
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF56707A),
                        ),
                      ),
                    ],
                    if (_error != null) ...[
                      const SizedBox(height: 12),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: const Color(0xFFF5E6C8),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFFE0C38B)),
                        ),
                        child: Text(
                          _error!,
                          style: const TextStyle(
                            color: Color(0xFF7A4A17),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(height: 20),
              if (overview == null && !_isLoading)
                const _SectionCard(
                  child: Text(
                    'Load the dashboard with a valid admin token to review traffic, top features, suspicious IP bursts, recent requests, and live sessions.',
                    style: TextStyle(
                      color: Color(0xFF335C67),
                      height: 1.5,
                    ),
                  ),
                ),
              if (overview != null) ...[
                Wrap(
                  spacing: 14,
                  runSpacing: 14,
                  children: [
                    _MetricCard(
                      title: 'Visitors 24h',
                      value: _formatCount(overview.summary.uniqueVisitors24h),
                    ),
                    _MetricCard(
                      title: 'Sessions 24h',
                      value: _formatCount(overview.summary.sessions24h),
                    ),
                    _MetricCard(
                      title: 'Events 24h',
                      value: _formatCount(overview.summary.events24h),
                    ),
                    _MetricCard(
                      title: 'Requests 24h',
                      value: _formatCount(overview.summary.requests24h),
                    ),
                    _MetricCard(
                      title: 'Errors 24h',
                      value: _formatCount(overview.summary.errorRequests24h),
                    ),
                    _MetricCard(
                      title: 'Suspicious IPs',
                      value: _formatCount(overview.summary.suspiciousIpCount),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: 420,
                      child: _MetricListCard(
                        title: 'Feature usage',
                        items: overview.featureUsage,
                      ),
                    ),
                    SizedBox(
                      width: 420,
                      child: _MetricListCard(
                        title: 'Top referrers',
                        items: overview.topReferrers,
                      ),
                    ),
                    SizedBox(
                      width: 420,
                      child: _MetricListCard(
                        title: 'Top landing paths',
                        items: overview.topLandingPaths,
                      ),
                    ),
                    SizedBox(
                      width: 420,
                      child: _StatusCodeCard(items: overview.statusCodes),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'Traffic by day',
                  child: Column(
                    children: [
                      for (final day in overview.trafficByDay)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 90,
                                child: Text(
                                  day.day,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w700,
                                    color: Color(0xFF112A46),
                                  ),
                                ),
                              ),
                              Expanded(
                                child: Wrap(
                                  spacing: 12,
                                  runSpacing: 8,
                                  children: [
                                    _InlineBadge(
                                      label: 'Sessions ${day.sessions}',
                                      color: const Color(0xFFD8F0DF),
                                    ),
                                    _InlineBadge(
                                      label: 'Events ${day.events}',
                                      color: const Color(0xFFE8EDF3),
                                    ),
                                    _InlineBadge(
                                      label: 'Requests ${day.requests}',
                                      color: const Color(0xFFF5E6C8),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _SuspiciousIpCard(items: overview.suspiciousIps),
                const SizedBox(height: 20),
                _RecentRequestsCard(
                  items: overview.recentRequests,
                  formatTimestamp: _formatTimestamp,
                ),
                const SizedBox(height: 20),
                _RecentSessionsCard(
                  items: overview.recentSessions,
                  formatTimestamp: _formatTimestamp,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({
    required this.child,
    this.title,
  });

  final String? title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3E8),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFD7E0E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (title != null) ...[
            Text(
              title!,
              style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF112A46),
              ),
            ),
            const SizedBox(height: 14),
          ],
          child,
        ],
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
  });

  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 180,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFF8F3E8),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: const Color(0xFFD7E0E5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: Color(0xFF335C67),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            value,
            style: const TextStyle(
              fontSize: 28,
              fontWeight: FontWeight.w900,
              color: Color(0xFF112A46),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetricListCard extends StatelessWidget {
  const _MetricListCard({
    required this.title,
    required this.items,
  });

  final String title;
  final List<AdminCountMetric> items;

  @override
  Widget build(BuildContext context) {
    final topCount = items.isEmpty
        ? 1
        : items.map((item) => item.count).reduce((a, b) => a > b ? a : b);
    return _SectionCard(
      title: title,
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          item.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF112A46),
                          ),
                        ),
                      ),
                      Text(
                        '${item.count}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF335C67),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(999),
                    child: LinearProgressIndicator(
                      value: item.count / topCount,
                      minHeight: 8,
                      backgroundColor: const Color(0xFFE3E9ED),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        Color(0xFF2E557A),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          if (items.isEmpty)
            const Text(
              'No data yet.',
              style: TextStyle(color: Color(0xFF56707A)),
            ),
        ],
      ),
    );
  }
}

class _StatusCodeCard extends StatelessWidget {
  const _StatusCodeCard({
    required this.items,
  });

  final List<AdminStatusCodeMetric> items;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Status codes',
      child: Wrap(
        spacing: 10,
        runSpacing: 10,
        children: [
          for (final item in items)
            _InlineBadge(
              label: '${item.statusCode}: ${item.count}',
              color: item.statusCode >= 500
                  ? const Color(0xFFF4D8D9)
                  : item.statusCode >= 400
                      ? const Color(0xFFF5E6C8)
                      : const Color(0xFFD8F0DF),
            ),
          if (items.isEmpty)
            const Text(
              'No request data yet.',
              style: TextStyle(color: Color(0xFF56707A)),
            ),
        ],
      ),
    );
  }
}

class _SuspiciousIpCard extends StatelessWidget {
  const _SuspiciousIpCard({
    required this.items,
  });

  final List<SuspiciousIpActivity> items;

  Color _severityColor(String severity) {
    return switch (severity) {
      'high' => const Color(0xFFF4D8D9),
      'medium' => const Color(0xFFF5E6C8),
      _ => const Color(0xFFE8EDF3),
    };
  }

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Suspicious repeated IP activity',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('IP')),
            DataColumn(label: Text('Severity')),
            DataColumn(label: Text('Requests')),
            DataColumn(label: Text('Errors')),
            DataColumn(label: Text('Paths')),
            DataColumn(label: Text('Sessions')),
            DataColumn(label: Text('Last seen')),
          ],
          rows: items.isEmpty
              ? [
                  const DataRow(
                    cells: [
                      DataCell(Text('No suspicious IP bursts in this window')),
                      DataCell(Text('-')),
                      DataCell(Text('-')),
                      DataCell(Text('-')),
                      DataCell(Text('-')),
                      DataCell(Text('-')),
                      DataCell(Text('-')),
                    ],
                  ),
                ]
              : items
                  .map(
                    (item) => DataRow(
                      cells: [
                        DataCell(Text(item.ip)),
                        DataCell(
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: _severityColor(item.severity),
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(item.severity),
                          ),
                        ),
                        DataCell(Text('${item.requestCount}')),
                        DataCell(Text('${item.errorCount}')),
                        DataCell(Text('${item.uniquePaths}')),
                        DataCell(Text('${item.uniqueSessions}')),
                        DataCell(Text(
                          '${item.lastSeenAt.toLocal().month}/${item.lastSeenAt.toLocal().day} ${item.lastSeenAt.toLocal().hour}:${item.lastSeenAt.toLocal().minute.toString().padLeft(2, '0')}',
                        )),
                      ],
                    ),
                  )
                  .toList(growable: false),
        ),
      ),
    );
  }
}

class _RecentRequestsCard extends StatelessWidget {
  const _RecentRequestsCard({
    required this.items,
    required this.formatTimestamp,
  });

  final List<AdminRequestLogItem> items;
  final String Function(DateTime value) formatTimestamp;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Recent backend requests',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('IP')),
            DataColumn(label: Text('Method')),
            DataColumn(label: Text('Path')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('ms')),
            DataColumn(label: Text('Session')),
          ],
          rows: items
              .map(
                (item) => DataRow(
                  cells: [
                    DataCell(Text(formatTimestamp(item.occurredAt))),
                    DataCell(Text(item.ip ?? '-')),
                    DataCell(Text(item.method)),
                    DataCell(
                      SizedBox(
                        width: 280,
                        child: Text(
                          item.path,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text('${item.statusCode}')),
                    DataCell(Text('${item.durationMs}')),
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          item.sessionId ?? '-',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _RecentSessionsCard extends StatelessWidget {
  const _RecentSessionsCard({
    required this.items,
    required this.formatTimestamp,
  });

  final List<AdminSessionItem> items;
  final String Function(DateTime value) formatTimestamp;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Recent sessions',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Started')),
            DataColumn(label: Text('Visitor')),
            DataColumn(label: Text('Session')),
            DataColumn(label: Text('Landing path')),
            DataColumn(label: Text('Referrer')),
            DataColumn(label: Text('IP')),
            DataColumn(label: Text('Requests')),
            DataColumn(label: Text('Events')),
          ],
          rows: items
              .map(
                (item) => DataRow(
                  cells: [
                    DataCell(Text(formatTimestamp(item.startedAt))),
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          item.visitorId,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(
                      SizedBox(
                        width: 180,
                        child: Text(
                          item.sessionId,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(item.landingPath ?? '/')),
                    DataCell(
                      SizedBox(
                        width: 220,
                        child: Text(
                          item.referrer ?? 'Direct / unknown',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text(item.lastIp ?? item.entryIp ?? '-')),
                    DataCell(Text('${item.requestCount}')),
                    DataCell(Text('${item.eventCount}')),
                  ],
                ),
              )
              .toList(growable: false),
        ),
      ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({
    required this.label,
    required this.color,
  });

  final String label;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        label,
        style: const TextStyle(
          fontWeight: FontWeight.w700,
          color: Color(0xFF112A46),
        ),
      ),
    );
  }
}

class _DropdownField<T> extends StatelessWidget {
  const _DropdownField({
    required this.label,
    required this.value,
    required this.options,
    required this.labelForValue,
    required this.onChanged,
  });

  final String label;
  final T value;
  final List<T> options;
  final String Function(T value) labelForValue;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 180,
      child: DropdownButtonFormField<T>(
        value: value,
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
        ),
        items: options
            .map(
              (option) => DropdownMenuItem<T>(
                value: option,
                child: Text(labelForValue(option)),
              ),
            )
            .toList(growable: false),
        onChanged: (nextValue) {
          if (nextValue != null) {
            onChanged(nextValue);
          }
        },
      ),
    );
  }
}
