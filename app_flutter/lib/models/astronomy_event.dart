class AstronomyEvent {
  const AstronomyEvent({
    required this.id,
    required this.eventType,
    required this.subtype,
    required this.title,
    required this.timestampUtc,
    required this.description,
  });

  final String id;
  final String eventType;
  final String subtype;
  final String title;
  final DateTime timestampUtc;
  final String? description;

  bool get isSolar => subtype.startsWith('solar_');
  bool get isLunar => subtype.startsWith('lunar_');

  factory AstronomyEvent.fromJson(Map<String, dynamic> json) {
    return AstronomyEvent(
      id: json['id'] as String? ?? 'event',
      eventType: json['event_type'] as String? ?? 'event',
      subtype: json['subtype'] as String? ?? 'generic',
      title: json['title'] as String? ?? 'Astronomy event',
      timestampUtc: DateTime.parse(
        json['timestamp_utc'] as String? ?? DateTime.now().toUtc().toIso8601String(),
      ).toUtc(),
      description: json['description'] as String?,
    );
  }
}
