import 'package:flutter/material.dart';

import '../models/admin_analytics_overview.dart';
import '../services/client_identity.dart';
import '../services/download_text_file.dart';
import '../services/maybeflat_api.dart';

class AdminScreen extends StatefulWidget {
  const AdminScreen({super.key});

  @override
  State<AdminScreen> createState() => _AdminScreenState();
}

class _AdminScreenState extends State<AdminScreen> {
  static const Map<String, String> _windowLabels = <String, String>{
    '1h': '1 hour',
    '24h': '24 hours',
    '7d': '7 days',
    '30d': '30 days',
  };

  static const List<int> _suspiciousWindowOptions = <int>[15, 30, 60, 180, 720];

  final MaybeflatApi _api = MaybeflatApi();
  late final TextEditingController _tokenController;

  bool _isLoading = false;
  bool _isDownloadingCsv = false;
  bool _isLoadingIp = false;
  bool _isLoadingSession = false;
  String? _error;
  String? _ipError;
  String? _sessionError;
  String _window = '24h';
  int _suspiciousWindowMinutes = 60;
  AdminAnalyticsOverview? _overview;
  String? _selectedIp;
  String? _selectedSessionId;
  IpDrilldown? _ipDrilldown;
  SessionDrilldown? _sessionDrilldown;

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
        window: _window,
        suspiciousWindowMinutes: _suspiciousWindowMinutes,
      );
      if (!mounted) {
        return;
      }

      ClientIdentity.instance.saveAdminToken(token);
      setState(() {
        _overview = overview;
        _ipDrilldown = null;
        _sessionDrilldown = null;
        _ipError = null;
        _sessionError = null;
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

  Future<void> _loadIpDrilldown(String ip) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      return;
    }

    setState(() {
      _selectedIp = ip;
      _isLoadingIp = true;
      _ipError = null;
    });

    try {
      final drilldown = await _api.loadAdminIpDrilldown(
        adminToken: token,
        ip: ip,
        window: _window,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _ipDrilldown = drilldown;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _ipError = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingIp = false;
        });
      }
    }
  }

  Future<void> _loadSessionDrilldown(String sessionId) async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      return;
    }

    setState(() {
      _selectedSessionId = sessionId;
      _isLoadingSession = true;
      _sessionError = null;
    });

    try {
      final drilldown = await _api.loadAdminSessionDrilldown(
        adminToken: token,
        sessionId: sessionId,
      );
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionDrilldown = drilldown;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _sessionError = _friendlyError(error);
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingSession = false;
        });
      }
    }
  }

  Future<void> _downloadSuspiciousCsv() async {
    final token = _tokenController.text.trim();
    if (token.isEmpty) {
      setState(() {
        _error = 'Enter the admin token before exporting CSV.';
      });
      return;
    }

    setState(() {
      _isDownloadingCsv = true;
      _error = null;
    });

    try {
      final csv = await _api.downloadSuspiciousCsv(
        adminToken: token,
        window: _window,
        suspiciousWindowMinutes: _suspiciousWindowMinutes,
      );
      await downloadTextFile(
        filename: 'maybeflat-suspicious-$_window.csv',
        content: csv,
        contentType: 'text/csv',
      );
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
          _isDownloadingCsv = false;
        });
      }
    }
  }

  void _clearToken() {
    ClientIdentity.instance.clearAdminToken();
    setState(() {
      _tokenController.clear();
      _overview = null;
      _selectedIp = null;
      _selectedSessionId = null;
      _ipDrilldown = null;
      _sessionDrilldown = null;
      _error = null;
      _ipError = null;
      _sessionError = null;
    });
  }

  String _friendlyError(Object error) {
    final message = error.toString();
    if (message.contains('401')) {
      return 'The admin token was rejected.';
    }
    if (message.contains('403')) {
      return 'Cloudflare Access blocked this admin request.';
    }
    if (message.contains('404')) {
      return 'The selected analytics record was not found in the current window.';
    }
    if (message.contains('503')) {
      return 'Admin analytics are not configured on the backend yet.';
    }
    return 'Could not load admin analytics.';
  }

  String _formatTimestamp(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${local.hour}:$minute';
  }

  String _formatCount(int value) => value.toString();

  String _formatMs(double value) =>
      '${value.toStringAsFixed(value >= 100 ? 0 : 1)} ms';

  String _formatBytes(int value) {
    if (value >= 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    if (value >= 1024) {
      return '${(value / 1024).toStringAsFixed(1)} KB';
    }
    return '$value B';
  }

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
                  fontSize: 30,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF112A46),
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Traffic, feature adoption, latency, suspicious IP activity, drilldowns, and CSV export in one protected dashboard.',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFF335C67),
                  height: 1.45,
                ),
              ),
              const SizedBox(height: 18),
              _buildControlsCard(overview),
              const SizedBox(height: 20),
              if (overview == null && !_isLoading)
                const _SectionCard(
                  child: Text(
                    'Load the dashboard with a valid admin token. For production, keep the token and put /admin behind Cloudflare Access.',
                    style: TextStyle(color: Color(0xFF335C67), height: 1.5),
                  ),
                ),
              if (overview != null) ...[
                _buildSummaryCards(overview),
                const SizedBox(height: 20),
                _buildDistributionCards(overview),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'Traffic buckets',
                  child: _TrafficBucketList(items: overview.trafficBuckets),
                ),
                const SizedBox(height: 20),
                _SectionCard(
                  title: 'Endpoint performance',
                  child: _EndpointBreakdownTable(
                    items: overview.endpointBreakdown,
                    formatMs: _formatMs,
                    formatBytes: _formatBytes,
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  children: [
                    SizedBox(
                      width: 420,
                      child: _StatusCodeCard(items: overview.statusCodes),
                    ),
                    SizedBox(
                      width: 560,
                      child: _ErrorRoutesCard(items: overview.errorRoutes),
                    ),
                  ],
                ),
                const SizedBox(height: 20),
                _SuspiciousIpCard(
                  items: overview.suspiciousIps,
                  selectedIp: _selectedIp,
                  formatTimestamp: _formatTimestamp,
                  onInspect: _loadIpDrilldown,
                ),
                const SizedBox(height: 20),
                _RecentRequestsCard(
                  items: overview.recentRequests,
                  formatTimestamp: _formatTimestamp,
                  formatBytes: _formatBytes,
                  onInspectIp: (ip) {
                    if (ip != null && ip.isNotEmpty) {
                      _loadIpDrilldown(ip);
                    }
                  },
                  onInspectSession: (sessionId) {
                    if (sessionId != null && sessionId.isNotEmpty) {
                      _loadSessionDrilldown(sessionId);
                    }
                  },
                ),
                const SizedBox(height: 20),
                _RecentSessionsCard(
                  items: overview.recentSessions,
                  formatTimestamp: _formatTimestamp,
                  selectedSessionId: _selectedSessionId,
                  onInspectSession: _loadSessionDrilldown,
                ),
                const SizedBox(height: 20),
                _buildDrilldowns(),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControlsCard(AdminAnalyticsOverview? overview) {
    return _SectionCard(
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
              _DropdownField<String>(
                label: 'Window',
                value: _window,
                options: _windowLabels.keys.toList(growable: false),
                labelForValue: (value) => _windowLabels[value] ?? value,
                onChanged: (value) => setState(() => _window = value),
              ),
              _DropdownField<int>(
                label: 'Suspicious IP window',
                value: _suspiciousWindowMinutes,
                options: _suspiciousWindowOptions,
                labelForValue: (value) => '$value min',
                onChanged: (value) {
                  setState(() => _suspiciousWindowMinutes = value);
                },
              ),
              FilledButton.icon(
                onPressed: _isLoading ? null : _loadOverview,
                icon: const Icon(Icons.refresh),
                label: Text(_isLoading ? 'Loading...' : 'Refresh'),
              ),
              OutlinedButton.icon(
                onPressed: _isDownloadingCsv ? null : _downloadSuspiciousCsv,
                icon: const Icon(Icons.download),
                label: Text(_isDownloadingCsv ? 'Exporting...' : 'Export CSV'),
              ),
              TextButton(
                onPressed: _isLoading ? null : _clearToken,
                child: const Text('Clear token'),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            'Window ${_windowLabels[_window] ?? _window} | Suspicious IP window $_suspiciousWindowMinutes min',
            style: const TextStyle(fontSize: 12, color: Color(0xFF56707A)),
          ),
          if (overview != null) ...[
            const SizedBox(height: 6),
            Text(
              'Last refreshed ${_formatTimestamp(overview.generatedAt)}',
              style: const TextStyle(fontSize: 12, color: Color(0xFF56707A)),
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: 12),
            _ErrorBanner(message: _error!),
          ],
        ],
      ),
    );
  }

  Widget _buildSummaryCards(AdminAnalyticsOverview overview) {
    return Wrap(
      spacing: 14,
      runSpacing: 14,
      children: [
        _MetricCard(
          title: 'Visitors',
          value: _formatCount(overview.summary.uniqueVisitors),
          subtitle: _windowLabels[_window] ?? _window,
        ),
        _MetricCard(
          title: 'Sessions',
          value: _formatCount(overview.summary.sessions),
          subtitle: _windowLabels[_window] ?? _window,
        ),
        _MetricCard(
          title: 'Events',
          value: _formatCount(overview.summary.events),
          subtitle: _windowLabels[_window] ?? _window,
        ),
        _MetricCard(
          title: 'Requests',
          value: _formatCount(overview.summary.requests),
          subtitle: _windowLabels[_window] ?? _window,
        ),
        _MetricCard(
          title: 'Errors',
          value: _formatCount(overview.summary.errorRequests),
          subtitle: '4xx / 5xx',
        ),
        _MetricCard(
          title: 'Suspicious IPs',
          value: _formatCount(overview.summary.suspiciousIpCount),
          subtitle: 'active window',
        ),
        _MetricCard(
          title: 'p95 latency',
          value: _formatMs(overview.latency.p95Ms),
          subtitle: 'request latency',
        ),
        _MetricCard(
          title: 'Avg payload',
          value: _formatBytes(overview.latency.averageResponseSizeBytes),
          subtitle: 'response size',
        ),
      ],
    );
  }

  Widget _buildDistributionCards(AdminAnalyticsOverview overview) {
    return Wrap(
      spacing: 16,
      runSpacing: 16,
      children: [
        SizedBox(
          width: 420,
          child: _FeatureUsageCard(items: overview.featureUsage),
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
            title: 'Landing paths',
            items: overview.topLandingPaths,
          ),
        ),
        SizedBox(
          width: 420,
          child: _MetricListCard(
            title: 'Countries',
            items: overview.countryCounts,
          ),
        ),
        SizedBox(
          width: 300,
          child: _MetricListCard(
            title: 'Device mix',
            items: overview.deviceBreakdown,
          ),
        ),
        SizedBox(
          width: 300,
          child: _MetricListCard(
            title: 'Browser mix',
            items: overview.browserBreakdown,
          ),
        ),
      ],
    );
  }

  Widget _buildDrilldowns() {
    return Column(
      children: [
        if (_ipError != null) _ErrorBanner(message: _ipError!),
        if (_ipDrilldown != null || _isLoadingIp) ...[
          if (_ipError != null) const SizedBox(height: 12),
          _IpDrilldownCard(
            drilldown: _ipDrilldown,
            isLoading: _isLoadingIp,
            selectedIp: _selectedIp,
            formatTimestamp: _formatTimestamp,
            formatBytes: _formatBytes,
            onInspectSession: (sessionId) {
              if (sessionId.isNotEmpty) {
                _loadSessionDrilldown(sessionId);
              }
            },
          ),
        ],
        if ((_ipDrilldown != null || _isLoadingIp) &&
            (_sessionDrilldown != null ||
                _isLoadingSession ||
                _sessionError != null))
          const SizedBox(height: 20),
        if (_sessionError != null) _ErrorBanner(message: _sessionError!),
        if (_sessionDrilldown != null || _isLoadingSession)
          _SessionDrilldownCard(
            drilldown: _sessionDrilldown,
            isLoading: _isLoadingSession,
            selectedSessionId: _selectedSessionId,
            formatTimestamp: _formatTimestamp,
            formatBytes: _formatBytes,
            onInspectIp: (ip) {
              if (ip != null && ip.isNotEmpty) {
                _loadIpDrilldown(ip);
              }
            },
          ),
      ],
    );
  }
}

class _SectionCard extends StatelessWidget {
  const _SectionCard({required this.child, this.title});

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

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFF5E6C8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0C38B)),
      ),
      child: Text(
        message,
        style: const TextStyle(
          color: Color(0xFF7A4A17),
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.title,
    required this.value,
    required this.subtitle,
  });

  final String title;
  final String value;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 170,
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
              fontSize: 26,
              fontWeight: FontWeight.w900,
              color: Color(0xFF112A46),
            ),
          ),
          const SizedBox(height: 4),
          Text(
            subtitle,
            style: const TextStyle(fontSize: 12, color: Color(0xFF56707A)),
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

class _FeatureUsageCard extends StatelessWidget {
  const _FeatureUsageCard({required this.items});

  final List<FeatureUsageMetric> items;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Feature usage',
      child: Column(
        children: [
          for (final item in items)
            Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          item.label,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF112A46),
                          ),
                        ),
                        const SizedBox(height: 4),
                        Wrap(
                          spacing: 8,
                          runSpacing: 6,
                          children: [
                            _InlineBadge(
                              label: 'Total ${item.count}',
                              color: const Color(0xFFE8EDF3),
                            ),
                            _InlineBadge(
                              label: 'Success ${item.successCount}',
                              color: const Color(0xFFD8F0DF),
                            ),
                            _InlineBadge(
                              label: 'Failed ${item.failureCount}',
                              color: const Color(0xFFF5E6C8),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          if (items.isEmpty)
            const Text(
              'No event data yet.',
              style: TextStyle(color: Color(0xFF56707A)),
            ),
        ],
      ),
    );
  }
}

class _TrafficBucketList extends StatelessWidget {
  const _TrafficBucketList({required this.items});

  final List<AdminTrafficBucket> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        for (final bucket in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Row(
              children: [
                SizedBox(
                  width: 120,
                  child: Text(
                    bucket.bucket,
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
                        label: 'Sessions ${bucket.sessions}',
                        color: const Color(0xFFD8F0DF),
                      ),
                      _InlineBadge(
                        label: 'Events ${bucket.events}',
                        color: const Color(0xFFE8EDF3),
                      ),
                      _InlineBadge(
                        label: 'Requests ${bucket.requests}',
                        color: const Color(0xFFF5E6C8),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        if (items.isEmpty)
          const Text(
            'No traffic data yet.',
            style: TextStyle(color: Color(0xFF56707A)),
          ),
      ],
    );
  }
}

class _StatusCodeCard extends StatelessWidget {
  const _StatusCodeCard({required this.items});

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

class _EndpointBreakdownTable extends StatelessWidget {
  const _EndpointBreakdownTable({
    required this.items,
    required this.formatMs,
    required this.formatBytes,
  });

  final List<EndpointBreakdownItem> items;
  final String Function(double value) formatMs;
  final String Function(int value) formatBytes;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        columns: const [
          DataColumn(label: Text('Endpoint')),
          DataColumn(label: Text('Requests')),
          DataColumn(label: Text('Errors')),
          DataColumn(label: Text('Avg')),
          DataColumn(label: Text('p95')),
          DataColumn(label: Text('Avg payload')),
        ],
        rows: items.isEmpty
            ? [
                const DataRow(
                  cells: [
                    DataCell(Text('No endpoint data yet')),
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
                      DataCell(
                        SizedBox(
                          width: 260,
                          child: Text(
                            item.routeGroup,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ),
                      DataCell(Text('${item.requestCount}')),
                      DataCell(Text('${item.errorCount}')),
                      DataCell(Text(formatMs(item.averageDurationMs))),
                      DataCell(Text(formatMs(item.p95DurationMs))),
                      DataCell(
                          Text(formatBytes(item.averageResponseSizeBytes))),
                    ],
                  ),
                )
                .toList(growable: false),
      ),
    );
  }
}

class _ErrorRoutesCard extends StatelessWidget {
  const _ErrorRoutesCard({required this.items});

  final List<ErrorRouteItem> items;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Top error routes',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Route')),
            DataColumn(label: Text('Total')),
            DataColumn(label: Text('404')),
            DataColumn(label: Text('4xx')),
            DataColumn(label: Text('5xx')),
          ],
          rows: items.isEmpty
              ? [
                  const DataRow(
                    cells: [
                      DataCell(Text('No error routes in this window')),
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
                        DataCell(
                          SizedBox(
                            width: 260,
                            child: Text(
                              item.routeGroup,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        DataCell(Text('${item.totalErrors}')),
                        DataCell(Text('${item.notFoundCount}')),
                        DataCell(Text('${item.clientErrorCount}')),
                        DataCell(Text('${item.serverErrorCount}')),
                      ],
                    ),
                  )
                  .toList(growable: false),
        ),
      ),
    );
  }
}

class _SuspiciousIpCard extends StatelessWidget {
  const _SuspiciousIpCard({
    required this.items,
    required this.selectedIp,
    required this.formatTimestamp,
    required this.onInspect,
  });

  final List<SuspiciousIpActivity> items;
  final String? selectedIp;
  final String Function(DateTime value) formatTimestamp;
  final ValueChanged<String> onInspect;

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
            DataColumn(label: Text('404s')),
            DataColumn(label: Text('Admin hits')),
            DataColumn(label: Text('Visitors')),
            DataColumn(label: Text('Burst')),
            DataColumn(label: Text('Last seen')),
            DataColumn(label: Text('Inspect')),
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
                      DataCell(Text('-')),
                      DataCell(Text('-')),
                      DataCell(Text('-')),
                    ],
                  ),
                ]
              : items
                  .map(
                    (item) => DataRow(
                      selected: item.ip == selectedIp,
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
                        DataCell(Text('${item.notFoundCount}')),
                        DataCell(Text('${item.adminHitCount}')),
                        DataCell(Text('${item.uniqueVisitors}')),
                        DataCell(Text(item.burstScore.toStringAsFixed(1))),
                        DataCell(Text(formatTimestamp(item.lastSeenAt))),
                        DataCell(
                          TextButton(
                            onPressed: () => onInspect(item.ip),
                            child: const Text('Inspect'),
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

class _RecentRequestsCard extends StatelessWidget {
  const _RecentRequestsCard({
    required this.items,
    required this.formatTimestamp,
    required this.formatBytes,
    required this.onInspectIp,
    required this.onInspectSession,
  });

  final List<AdminRequestLogItem> items;
  final String Function(DateTime value) formatTimestamp;
  final String Function(int value) formatBytes;
  final ValueChanged<String?> onInspectIp;
  final ValueChanged<String?> onInspectSession;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Recent backend requests',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: const [
            DataColumn(label: Text('Time')),
            DataColumn(label: Text('Route')),
            DataColumn(label: Text('Status')),
            DataColumn(label: Text('ms')),
            DataColumn(label: Text('Payload')),
            DataColumn(label: Text('IP')),
            DataColumn(label: Text('Session')),
          ],
          rows: items
              .map(
                (item) => DataRow(
                  cells: [
                    DataCell(Text(formatTimestamp(item.occurredAt))),
                    DataCell(
                      SizedBox(
                        width: 280,
                        child: Text(
                          '${item.method} ${item.routeGroup}',
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                    DataCell(Text('${item.statusCode}')),
                    DataCell(Text('${item.durationMs}')),
                    DataCell(Text(formatBytes(item.responseSizeBytes))),
                    DataCell(
                      item.ip == null
                          ? const Text('-')
                          : TextButton(
                              onPressed: () => onInspectIp(item.ip),
                              child: Text(item.ip!),
                            ),
                    ),
                    DataCell(
                      item.sessionId == null
                          ? const Text('-')
                          : TextButton(
                              onPressed: () => onInspectSession(item.sessionId),
                              child: SizedBox(
                                width: 180,
                                child: Text(
                                  item.sessionId!,
                                  overflow: TextOverflow.ellipsis,
                                ),
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
    required this.selectedSessionId,
    required this.onInspectSession,
  });

  final List<AdminSessionItem> items;
  final String Function(DateTime value) formatTimestamp;
  final String? selectedSessionId;
  final ValueChanged<String> onInspectSession;

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
            DataColumn(label: Text('Country')),
            DataColumn(label: Text('Requests')),
            DataColumn(label: Text('Events')),
            DataColumn(label: Text('Inspect')),
          ],
          rows: items
              .map(
                (item) => DataRow(
                  selected: item.sessionId == selectedSessionId,
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
                    DataCell(Text(item.country ?? 'Unknown')),
                    DataCell(Text('${item.requestCount}')),
                    DataCell(Text('${item.eventCount}')),
                    DataCell(
                      TextButton(
                        onPressed: () => onInspectSession(item.sessionId),
                        child: const Text('Inspect'),
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

class _IpDrilldownCard extends StatelessWidget {
  const _IpDrilldownCard({
    required this.drilldown,
    required this.isLoading,
    required this.selectedIp,
    required this.formatTimestamp,
    required this.formatBytes,
    required this.onInspectSession,
  });

  final IpDrilldown? drilldown;
  final bool isLoading;
  final String? selectedIp;
  final String Function(DateTime value) formatTimestamp;
  final String Function(int value) formatBytes;
  final ValueChanged<String> onInspectSession;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'IP drilldown',
      child: isLoading && drilldown == null
          ? Text(
              'Loading $selectedIp...',
              style: const TextStyle(color: Color(0xFF56707A)),
            )
          : drilldown == null
              ? const Text(
                  'Select an IP from the suspicious activity or request tables.',
                  style: TextStyle(color: Color(0xFF56707A)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InlineBadge(
                          label: 'IP ${drilldown!.ip}',
                          color: const Color(0xFFE8EDF3),
                        ),
                        _InlineBadge(
                          label: 'Requests ${drilldown!.requestCount}',
                          color: const Color(0xFFD8F0DF),
                        ),
                        _InlineBadge(
                          label: 'Errors ${drilldown!.errorCount}',
                          color: const Color(0xFFF5E6C8),
                        ),
                        _InlineBadge(
                          label: '404s ${drilldown!.notFoundCount}',
                          color: const Color(0xFFF5E6C8),
                        ),
                        _InlineBadge(
                          label: 'Admin hits ${drilldown!.adminHitCount}',
                          color: const Color(0xFFF4D8D9),
                        ),
                        _InlineBadge(
                          label:
                              'Burst ${drilldown!.burstScore.toStringAsFixed(1)}',
                          color: const Color(0xFFE8EDF3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: 320,
                          child: _MetricListCard(
                            title: 'Countries',
                            items: drilldown!.countries,
                          ),
                        ),
                        SizedBox(
                          width: 320,
                          child: _MetricListCard(
                            title: 'User agents',
                            items: drilldown!.userAgents,
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: _MetricListCard(
                            title: 'Routes',
                            items: drilldown!.routes,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _RecentSessionsCard(
                      items: drilldown!.recentSessions,
                      formatTimestamp: formatTimestamp,
                      selectedSessionId: null,
                      onInspectSession: onInspectSession,
                    ),
                    const SizedBox(height: 16),
                    _RecentRequestsCard(
                      items: drilldown!.recentRequests,
                      formatTimestamp: formatTimestamp,
                      formatBytes: formatBytes,
                      onInspectIp: (_) {},
                      onInspectSession: (sessionId) {
                        if (sessionId != null && sessionId.isNotEmpty) {
                          onInspectSession(sessionId);
                        }
                      },
                    ),
                  ],
                ),
    );
  }
}

class _SessionDrilldownCard extends StatelessWidget {
  const _SessionDrilldownCard({
    required this.drilldown,
    required this.isLoading,
    required this.selectedSessionId,
    required this.formatTimestamp,
    required this.formatBytes,
    required this.onInspectIp,
  });

  final SessionDrilldown? drilldown;
  final bool isLoading;
  final String? selectedSessionId;
  final String Function(DateTime value) formatTimestamp;
  final String Function(int value) formatBytes;
  final ValueChanged<String?> onInspectIp;

  @override
  Widget build(BuildContext context) {
    return _SectionCard(
      title: 'Session drilldown',
      child: isLoading && drilldown == null
          ? Text(
              'Loading $selectedSessionId...',
              style: const TextStyle(color: Color(0xFF56707A)),
            )
          : drilldown == null
              ? const Text(
                  'Select a session from the recent session or request tables.',
                  style: TextStyle(color: Color(0xFF56707A)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        _InlineBadge(
                          label: 'Session ${drilldown!.session.sessionId}',
                          color: const Color(0xFFE8EDF3),
                        ),
                        _InlineBadge(
                          label: 'Visitor ${drilldown!.session.visitorId}',
                          color: const Color(0xFFE8EDF3),
                        ),
                        _InlineBadge(
                          label: 'Requests ${drilldown!.session.requestCount}',
                          color: const Color(0xFFD8F0DF),
                        ),
                        _InlineBadge(
                          label: 'Events ${drilldown!.session.eventCount}',
                          color: const Color(0xFFF5E6C8),
                        ),
                        _InlineBadge(
                          label:
                              'IP ${drilldown!.session.lastIp ?? drilldown!.session.entryIp ?? '-'}',
                          color: const Color(0xFFE8EDF3),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Wrap(
                      spacing: 16,
                      runSpacing: 16,
                      children: [
                        SizedBox(
                          width: 300,
                          child: _MetricListCard(
                            title: 'Countries',
                            items: drilldown!.countries,
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: _MetricListCard(
                            title: 'Routes',
                            items: drilldown!.routes,
                          ),
                        ),
                        SizedBox(
                          width: 360,
                          child: _MetricListCard(
                            title: 'User agents',
                            items: drilldown!.userAgents,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    _SectionCard(
                      title: 'Event timeline',
                      child: Column(
                        children: [
                          for (final event in drilldown!.events)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 110,
                                    child: Text(
                                      formatTimestamp(event.occurredAt),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFF112A46),
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          event.name,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF112A46),
                                          ),
                                        ),
                                        if (event.path != null)
                                          Text(
                                            event.path!,
                                            style: const TextStyle(
                                              color: Color(0xFF56707A),
                                            ),
                                          ),
                                        if (event.properties.isNotEmpty)
                                          Text(
                                            event.properties.toString(),
                                            style: const TextStyle(
                                              color: Color(0xFF56707A),
                                              fontSize: 12,
                                            ),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          if (drilldown!.events.isEmpty)
                            const Text(
                              'No tracked events for this session yet.',
                              style: TextStyle(color: Color(0xFF56707A)),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                    _RecentRequestsCard(
                      items: drilldown!.requests,
                      formatTimestamp: formatTimestamp,
                      formatBytes: formatBytes,
                      onInspectIp: onInspectIp,
                      onInspectSession: (_) {},
                    ),
                  ],
                ),
    );
  }
}

class _InlineBadge extends StatelessWidget {
  const _InlineBadge({required this.label, required this.color});

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
        initialValue: value,
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
