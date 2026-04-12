class AdminAnalyticsOverview {
  const AdminAnalyticsOverview({
    required this.generatedAt,
    required this.window,
    required this.summary,
    required this.latency,
    required this.featureUsage,
    required this.topReferrers,
    required this.topLandingPaths,
    required this.trafficBuckets,
    required this.statusCodes,
    required this.countryCounts,
    required this.deviceBreakdown,
    required this.browserBreakdown,
    required this.endpointBreakdown,
    required this.errorRoutes,
    required this.suspiciousIps,
    required this.recentRequests,
    required this.recentSessions,
  });

  final DateTime generatedAt;
  final String window;
  final AdminAnalyticsSummary summary;
  final AdminLatencySummary latency;
  final List<FeatureUsageMetric> featureUsage;
  final List<AdminCountMetric> topReferrers;
  final List<AdminCountMetric> topLandingPaths;
  final List<AdminTrafficBucket> trafficBuckets;
  final List<AdminStatusCodeMetric> statusCodes;
  final List<AdminCountMetric> countryCounts;
  final List<AdminCountMetric> deviceBreakdown;
  final List<AdminCountMetric> browserBreakdown;
  final List<EndpointBreakdownItem> endpointBreakdown;
  final List<ErrorRouteItem> errorRoutes;
  final List<SuspiciousIpActivity> suspiciousIps;
  final List<AdminRequestLogItem> recentRequests;
  final List<AdminSessionItem> recentSessions;

  factory AdminAnalyticsOverview.fromJson(Map<String, dynamic> json) {
    return AdminAnalyticsOverview(
      generatedAt: DateTime.parse(json['generated_at'] as String),
      window: json['window'] as String? ?? '24h',
      summary: AdminAnalyticsSummary.fromJson(
        json['summary'] as Map<String, dynamic>,
      ),
      latency: AdminLatencySummary.fromJson(
        json['latency'] as Map<String, dynamic>? ?? const {},
      ),
      featureUsage: _parseList(
        json['feature_usage'],
        FeatureUsageMetric.fromJson,
      ),
      topReferrers:
          _parseList(json['top_referrers'], AdminCountMetric.fromJson),
      topLandingPaths: _parseList(
        json['top_landing_paths'],
        AdminCountMetric.fromJson,
      ),
      trafficBuckets: _parseList(
        json['traffic_buckets'],
        AdminTrafficBucket.fromJson,
      ),
      statusCodes: _parseList(
        json['status_codes'],
        AdminStatusCodeMetric.fromJson,
      ),
      countryCounts: _parseList(
        json['country_counts'],
        AdminCountMetric.fromJson,
      ),
      deviceBreakdown: _parseList(
        json['device_breakdown'],
        AdminCountMetric.fromJson,
      ),
      browserBreakdown: _parseList(
        json['browser_breakdown'],
        AdminCountMetric.fromJson,
      ),
      endpointBreakdown: _parseList(
        json['endpoint_breakdown'],
        EndpointBreakdownItem.fromJson,
      ),
      errorRoutes: _parseList(json['error_routes'], ErrorRouteItem.fromJson),
      suspiciousIps: _parseList(
        json['suspicious_ips'],
        SuspiciousIpActivity.fromJson,
      ),
      recentRequests: _parseList(
        json['recent_requests'],
        AdminRequestLogItem.fromJson,
      ),
      recentSessions: _parseList(
        json['recent_sessions'],
        AdminSessionItem.fromJson,
      ),
    );
  }

  static List<T> _parseList<T>(
    dynamic raw,
    T Function(Map<String, dynamic> json) fromJson,
  ) {
    return (raw as List<dynamic>? ?? const <dynamic>[])
        .whereType<Map<String, dynamic>>()
        .map(fromJson)
        .toList(growable: false);
  }
}

class AdminAnalyticsSummary {
  const AdminAnalyticsSummary({
    required this.uniqueVisitors,
    required this.sessions,
    required this.events,
    required this.requests,
    required this.errorRequests,
    required this.suspiciousIpCount,
  });

  final int uniqueVisitors;
  final int sessions;
  final int events;
  final int requests;
  final int errorRequests;
  final int suspiciousIpCount;

  factory AdminAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AdminAnalyticsSummary(
      uniqueVisitors: (json['unique_visitors'] as num?)?.toInt() ?? 0,
      sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      events: (json['events'] as num?)?.toInt() ?? 0,
      requests: (json['requests'] as num?)?.toInt() ?? 0,
      errorRequests: (json['error_requests'] as num?)?.toInt() ?? 0,
      suspiciousIpCount: (json['suspicious_ip_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminCountMetric {
  const AdminCountMetric({required this.label, required this.count});

  final String label;
  final int count;

  factory AdminCountMetric.fromJson(Map<String, dynamic> json) {
    return AdminCountMetric(
      label: json['label'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class FeatureUsageMetric {
  const FeatureUsageMetric({
    required this.label,
    required this.count,
    required this.successCount,
    required this.failureCount,
  });

  final String label;
  final int count;
  final int successCount;
  final int failureCount;

  factory FeatureUsageMetric.fromJson(Map<String, dynamic> json) {
    return FeatureUsageMetric(
      label: json['label'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
      successCount: (json['success_count'] as num?)?.toInt() ?? 0,
      failureCount: (json['failure_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminTrafficBucket {
  const AdminTrafficBucket({
    required this.bucket,
    required this.sessions,
    required this.events,
    required this.requests,
  });

  final String bucket;
  final int sessions;
  final int events;
  final int requests;

  factory AdminTrafficBucket.fromJson(Map<String, dynamic> json) {
    return AdminTrafficBucket(
      bucket: json['bucket'] as String? ?? '',
      sessions: (json['sessions'] as num?)?.toInt() ?? 0,
      events: (json['events'] as num?)?.toInt() ?? 0,
      requests: (json['requests'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminStatusCodeMetric {
  const AdminStatusCodeMetric({
    required this.statusCode,
    required this.count,
  });

  final int statusCode;
  final int count;

  factory AdminStatusCodeMetric.fromJson(Map<String, dynamic> json) {
    return AdminStatusCodeMetric(
      statusCode: (json['status_code'] as num?)?.toInt() ?? 0,
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminLatencySummary {
  const AdminLatencySummary({
    required this.averageMs,
    required this.p50Ms,
    required this.p95Ms,
    required this.p99Ms,
    required this.averageResponseSizeBytes,
  });

  final double averageMs;
  final double p50Ms;
  final double p95Ms;
  final double p99Ms;
  final int averageResponseSizeBytes;

  factory AdminLatencySummary.fromJson(Map<String, dynamic> json) {
    return AdminLatencySummary(
      averageMs: (json['average_ms'] as num?)?.toDouble() ?? 0,
      p50Ms: (json['p50_ms'] as num?)?.toDouble() ?? 0,
      p95Ms: (json['p95_ms'] as num?)?.toDouble() ?? 0,
      p99Ms: (json['p99_ms'] as num?)?.toDouble() ?? 0,
      averageResponseSizeBytes:
          (json['average_response_size_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class EndpointBreakdownItem {
  const EndpointBreakdownItem({
    required this.routeGroup,
    required this.requestCount,
    required this.errorCount,
    required this.averageDurationMs,
    required this.p95DurationMs,
    required this.averageResponseSizeBytes,
  });

  final String routeGroup;
  final int requestCount;
  final int errorCount;
  final double averageDurationMs;
  final double p95DurationMs;
  final int averageResponseSizeBytes;

  factory EndpointBreakdownItem.fromJson(Map<String, dynamic> json) {
    return EndpointBreakdownItem(
      routeGroup: json['route_group'] as String? ?? '/',
      requestCount: (json['request_count'] as num?)?.toInt() ?? 0,
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
      averageDurationMs: (json['average_duration_ms'] as num?)?.toDouble() ?? 0,
      p95DurationMs: (json['p95_duration_ms'] as num?)?.toDouble() ?? 0,
      averageResponseSizeBytes:
          (json['average_response_size_bytes'] as num?)?.toInt() ?? 0,
    );
  }
}

class ErrorRouteItem {
  const ErrorRouteItem({
    required this.routeGroup,
    required this.totalErrors,
    required this.notFoundCount,
    required this.clientErrorCount,
    required this.serverErrorCount,
  });

  final String routeGroup;
  final int totalErrors;
  final int notFoundCount;
  final int clientErrorCount;
  final int serverErrorCount;

  factory ErrorRouteItem.fromJson(Map<String, dynamic> json) {
    return ErrorRouteItem(
      routeGroup: json['route_group'] as String? ?? '/',
      totalErrors: (json['total_errors'] as num?)?.toInt() ?? 0,
      notFoundCount: (json['not_found_count'] as num?)?.toInt() ?? 0,
      clientErrorCount: (json['client_error_count'] as num?)?.toInt() ?? 0,
      serverErrorCount: (json['server_error_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class SuspiciousIpActivity {
  const SuspiciousIpActivity({
    required this.ip,
    required this.requestCount,
    required this.errorCount,
    required this.uniquePaths,
    required this.uniqueSessions,
    required this.uniqueVisitors,
    required this.notFoundCount,
    required this.adminHitCount,
    required this.burstScore,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.severity,
  });

  final String ip;
  final int requestCount;
  final int errorCount;
  final int uniquePaths;
  final int uniqueSessions;
  final int uniqueVisitors;
  final int notFoundCount;
  final int adminHitCount;
  final double burstScore;
  final DateTime firstSeenAt;
  final DateTime lastSeenAt;
  final String severity;

  factory SuspiciousIpActivity.fromJson(Map<String, dynamic> json) {
    return SuspiciousIpActivity(
      ip: json['ip'] as String? ?? 'unknown',
      requestCount: (json['request_count'] as num?)?.toInt() ?? 0,
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
      uniquePaths: (json['unique_paths'] as num?)?.toInt() ?? 0,
      uniqueSessions: (json['unique_sessions'] as num?)?.toInt() ?? 0,
      uniqueVisitors: (json['unique_visitors'] as num?)?.toInt() ?? 0,
      notFoundCount: (json['not_found_count'] as num?)?.toInt() ?? 0,
      adminHitCount: (json['admin_hit_count'] as num?)?.toInt() ?? 0,
      burstScore: (json['burst_score'] as num?)?.toDouble() ?? 0,
      firstSeenAt: DateTime.parse(json['first_seen_at'] as String),
      lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
      severity: json['severity'] as String? ?? 'low',
    );
  }
}

class AdminRequestLogItem {
  const AdminRequestLogItem({
    required this.occurredAt,
    required this.method,
    required this.path,
    required this.routeGroup,
    required this.statusCode,
    required this.durationMs,
    required this.responseSizeBytes,
    required this.requestId,
    this.ip,
    this.country,
    this.visitorId,
    this.sessionId,
    this.userAgent,
    this.referrer,
  });

  final DateTime occurredAt;
  final String method;
  final String path;
  final String routeGroup;
  final int statusCode;
  final int durationMs;
  final int responseSizeBytes;
  final String requestId;
  final String? ip;
  final String? country;
  final String? visitorId;
  final String? sessionId;
  final String? userAgent;
  final String? referrer;

  factory AdminRequestLogItem.fromJson(Map<String, dynamic> json) {
    return AdminRequestLogItem(
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      method: json['method'] as String? ?? 'GET',
      path: json['path'] as String? ?? '/',
      routeGroup: json['route_group'] as String? ?? '/',
      statusCode: (json['status_code'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      responseSizeBytes: (json['response_size_bytes'] as num?)?.toInt() ?? 0,
      requestId: json['request_id'] as String? ?? '',
      ip: json['ip'] as String?,
      country: json['country'] as String?,
      visitorId: json['visitor_id'] as String?,
      sessionId: json['session_id'] as String?,
      userAgent: json['user_agent'] as String?,
      referrer: json['referrer'] as String?,
    );
  }
}

class AdminSessionItem {
  const AdminSessionItem({
    required this.sessionId,
    required this.visitorId,
    required this.startedAt,
    required this.lastSeenAt,
    required this.requestCount,
    required this.eventCount,
    this.landingPath,
    this.referrer,
    this.country,
    this.entryIp,
    this.lastIp,
  });

  final String sessionId;
  final String visitorId;
  final DateTime startedAt;
  final DateTime lastSeenAt;
  final int requestCount;
  final int eventCount;
  final String? landingPath;
  final String? referrer;
  final String? country;
  final String? entryIp;
  final String? lastIp;

  factory AdminSessionItem.fromJson(Map<String, dynamic> json) {
    return AdminSessionItem(
      sessionId: json['session_id'] as String? ?? '',
      visitorId: json['visitor_id'] as String? ?? '',
      startedAt: DateTime.parse(json['started_at'] as String),
      lastSeenAt: DateTime.parse(json['last_seen_at'] as String),
      requestCount: (json['request_count'] as num?)?.toInt() ?? 0,
      eventCount: (json['event_count'] as num?)?.toInt() ?? 0,
      landingPath: json['landing_path'] as String?,
      referrer: json['referrer'] as String?,
      country: json['country'] as String?,
      entryIp: json['entry_ip'] as String?,
      lastIp: json['last_ip'] as String?,
    );
  }
}

class AdminSessionEventItem {
  const AdminSessionEventItem({
    required this.occurredAt,
    required this.name,
    required this.properties,
    this.path,
    this.ip,
  });

  final DateTime occurredAt;
  final String name;
  final String? path;
  final String? ip;
  final Map<String, dynamic> properties;

  factory AdminSessionEventItem.fromJson(Map<String, dynamic> json) {
    return AdminSessionEventItem(
      occurredAt: DateTime.parse(json['occurred_at'] as String),
      name: json['name'] as String? ?? '',
      path: json['path'] as String?,
      ip: json['ip'] as String?,
      properties: (json['properties'] as Map<String, dynamic>?) ??
          const <String, dynamic>{},
    );
  }
}

class IpDrilldown {
  const IpDrilldown({
    required this.ip,
    required this.requestCount,
    required this.errorCount,
    required this.sessionCount,
    required this.visitorCount,
    required this.notFoundCount,
    required this.adminHitCount,
    required this.burstScore,
    required this.countries,
    required this.userAgents,
    required this.routes,
    required this.recentRequests,
    required this.recentSessions,
  });

  final String ip;
  final int requestCount;
  final int errorCount;
  final int sessionCount;
  final int visitorCount;
  final int notFoundCount;
  final int adminHitCount;
  final double burstScore;
  final List<AdminCountMetric> countries;
  final List<AdminCountMetric> userAgents;
  final List<AdminCountMetric> routes;
  final List<AdminRequestLogItem> recentRequests;
  final List<AdminSessionItem> recentSessions;

  factory IpDrilldown.fromJson(Map<String, dynamic> json) {
    return IpDrilldown(
      ip: json['ip'] as String? ?? '',
      requestCount: (json['request_count'] as num?)?.toInt() ?? 0,
      errorCount: (json['error_count'] as num?)?.toInt() ?? 0,
      sessionCount: (json['session_count'] as num?)?.toInt() ?? 0,
      visitorCount: (json['visitor_count'] as num?)?.toInt() ?? 0,
      notFoundCount: (json['not_found_count'] as num?)?.toInt() ?? 0,
      adminHitCount: (json['admin_hit_count'] as num?)?.toInt() ?? 0,
      burstScore: (json['burst_score'] as num?)?.toDouble() ?? 0,
      countries: AdminAnalyticsOverview._parseList(
        json['countries'],
        AdminCountMetric.fromJson,
      ),
      userAgents: AdminAnalyticsOverview._parseList(
        json['user_agents'],
        AdminCountMetric.fromJson,
      ),
      routes: AdminAnalyticsOverview._parseList(
        json['routes'],
        AdminCountMetric.fromJson,
      ),
      recentRequests: AdminAnalyticsOverview._parseList(
        json['recent_requests'],
        AdminRequestLogItem.fromJson,
      ),
      recentSessions: AdminAnalyticsOverview._parseList(
        json['recent_sessions'],
        AdminSessionItem.fromJson,
      ),
    );
  }
}

class SessionDrilldown {
  const SessionDrilldown({
    required this.session,
    required this.countries,
    required this.routes,
    required this.userAgents,
    required this.events,
    required this.requests,
  });

  final AdminSessionItem session;
  final List<AdminCountMetric> countries;
  final List<AdminCountMetric> routes;
  final List<AdminCountMetric> userAgents;
  final List<AdminSessionEventItem> events;
  final List<AdminRequestLogItem> requests;

  factory SessionDrilldown.fromJson(Map<String, dynamic> json) {
    return SessionDrilldown(
      session: AdminSessionItem.fromJson(
        json['session'] as Map<String, dynamic>,
      ),
      countries: AdminAnalyticsOverview._parseList(
        json['countries'],
        AdminCountMetric.fromJson,
      ),
      routes: AdminAnalyticsOverview._parseList(
        json['routes'],
        AdminCountMetric.fromJson,
      ),
      userAgents: AdminAnalyticsOverview._parseList(
        json['user_agents'],
        AdminCountMetric.fromJson,
      ),
      events: AdminAnalyticsOverview._parseList(
        json['events'],
        AdminSessionEventItem.fromJson,
      ),
      requests: AdminAnalyticsOverview._parseList(
        json['requests'],
        AdminRequestLogItem.fromJson,
      ),
    );
  }
}
