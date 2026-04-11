class AdminAnalyticsOverview {
  const AdminAnalyticsOverview({
    required this.generatedAt,
    required this.summary,
    required this.featureUsage,
    required this.topReferrers,
    required this.topLandingPaths,
    required this.trafficByDay,
    required this.statusCodes,
    required this.suspiciousIps,
    required this.recentRequests,
    required this.recentSessions,
  });

  final DateTime generatedAt;
  final AdminAnalyticsSummary summary;
  final List<AdminCountMetric> featureUsage;
  final List<AdminCountMetric> topReferrers;
  final List<AdminCountMetric> topLandingPaths;
  final List<AdminTrafficDay> trafficByDay;
  final List<AdminStatusCodeMetric> statusCodes;
  final List<SuspiciousIpActivity> suspiciousIps;
  final List<AdminRequestLogItem> recentRequests;
  final List<AdminSessionItem> recentSessions;

  factory AdminAnalyticsOverview.fromJson(Map<String, dynamic> json) {
    return AdminAnalyticsOverview(
      generatedAt: DateTime.parse(json['generated_at'] as String),
      summary: AdminAnalyticsSummary.fromJson(
        json['summary'] as Map<String, dynamic>,
      ),
      featureUsage: _parseList(
        json['feature_usage'],
        (item) => AdminCountMetric.fromJson(item),
      ),
      topReferrers: _parseList(
        json['top_referrers'],
        (item) => AdminCountMetric.fromJson(item),
      ),
      topLandingPaths: _parseList(
        json['top_landing_paths'],
        (item) => AdminCountMetric.fromJson(item),
      ),
      trafficByDay: _parseList(
        json['traffic_by_day'],
        (item) => AdminTrafficDay.fromJson(item),
      ),
      statusCodes: _parseList(
        json['status_codes'],
        (item) => AdminStatusCodeMetric.fromJson(item),
      ),
      suspiciousIps: _parseList(
        json['suspicious_ips'],
        (item) => SuspiciousIpActivity.fromJson(item),
      ),
      recentRequests: _parseList(
        json['recent_requests'],
        (item) => AdminRequestLogItem.fromJson(item),
      ),
      recentSessions: _parseList(
        json['recent_sessions'],
        (item) => AdminSessionItem.fromJson(item),
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
    required this.uniqueVisitors24h,
    required this.sessions24h,
    required this.events24h,
    required this.requests24h,
    required this.errorRequests24h,
    required this.suspiciousIpCount,
  });

  final int uniqueVisitors24h;
  final int sessions24h;
  final int events24h;
  final int requests24h;
  final int errorRequests24h;
  final int suspiciousIpCount;

  factory AdminAnalyticsSummary.fromJson(Map<String, dynamic> json) {
    return AdminAnalyticsSummary(
      uniqueVisitors24h: (json['unique_visitors_24h'] as num?)?.toInt() ?? 0,
      sessions24h: (json['sessions_24h'] as num?)?.toInt() ?? 0,
      events24h: (json['events_24h'] as num?)?.toInt() ?? 0,
      requests24h: (json['requests_24h'] as num?)?.toInt() ?? 0,
      errorRequests24h: (json['error_requests_24h'] as num?)?.toInt() ?? 0,
      suspiciousIpCount: (json['suspicious_ip_count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminCountMetric {
  const AdminCountMetric({
    required this.label,
    required this.count,
  });

  final String label;
  final int count;

  factory AdminCountMetric.fromJson(Map<String, dynamic> json) {
    return AdminCountMetric(
      label: json['label'] as String? ?? '',
      count: (json['count'] as num?)?.toInt() ?? 0,
    );
  }
}

class AdminTrafficDay {
  const AdminTrafficDay({
    required this.day,
    required this.sessions,
    required this.events,
    required this.requests,
  });

  final String day;
  final int sessions;
  final int events;
  final int requests;

  factory AdminTrafficDay.fromJson(Map<String, dynamic> json) {
    return AdminTrafficDay(
      day: json['day'] as String? ?? '',
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

class SuspiciousIpActivity {
  const SuspiciousIpActivity({
    required this.ip,
    required this.requestCount,
    required this.errorCount,
    required this.uniquePaths,
    required this.uniqueSessions,
    required this.firstSeenAt,
    required this.lastSeenAt,
    required this.severity,
  });

  final String ip;
  final int requestCount;
  final int errorCount;
  final int uniquePaths;
  final int uniqueSessions;
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
    required this.statusCode,
    required this.durationMs,
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
  final int statusCode;
  final int durationMs;
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
      statusCode: (json['status_code'] as num?)?.toInt() ?? 0,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
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
