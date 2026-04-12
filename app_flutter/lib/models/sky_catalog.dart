class SkyStar {
  const SkyStar({
    required this.id,
    required this.name,
    required this.rightAscensionHours,
    required this.declinationDegrees,
    required this.magnitude,
  });

  final String id;
  final String name;
  final double rightAscensionHours;
  final double declinationDegrees;
  final double magnitude;

  factory SkyStar.fromJson(Map<String, dynamic> json) {
    return SkyStar(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Star',
      rightAscensionHours: (json['ra_hours'] as num?)?.toDouble() ?? 0,
      declinationDegrees: (json['dec_degrees'] as num?)?.toDouble() ?? 0,
      magnitude: (json['magnitude'] as num?)?.toDouble() ?? 6,
    );
  }
}

class ZodiacConstellation {
  const ZodiacConstellation({
    required this.id,
    required this.name,
    required this.labelRightAscensionHours,
    required this.labelDeclinationDegrees,
    required this.starIds,
    required this.segments,
  });

  final String id;
  final String name;
  final double labelRightAscensionHours;
  final double labelDeclinationDegrees;
  final List<String> starIds;
  final List<List<String>> segments;

  factory ZodiacConstellation.fromJson(Map<String, dynamic> json) {
    return ZodiacConstellation(
      id: json['id'] as String? ?? '',
      name: json['name'] as String? ?? 'Constellation',
      labelRightAscensionHours:
          (json['label_ra_hours'] as num?)?.toDouble() ?? 0,
      labelDeclinationDegrees:
          (json['label_dec_degrees'] as num?)?.toDouble() ?? 0,
      starIds: (json['star_ids'] as List<dynamic>? ?? const [])
          .map((value) => value as String)
          .toList(growable: false),
      segments: (json['segments'] as List<dynamic>? ?? const [])
          .map(
            (segment) => (segment as List<dynamic>)
                .map((value) => value as String)
                .toList(growable: false),
          )
          .toList(growable: false),
    );
  }
}

class SkyCatalog {
  SkyCatalog({
    required this.version,
    required this.stars,
    required this.constellations,
  }) : starsById = <String, SkyStar>{
          for (final star in stars) star.id: star,
        };

  final String version;
  final List<SkyStar> stars;
  final List<ZodiacConstellation> constellations;
  final Map<String, SkyStar> starsById;

  factory SkyCatalog.fromJson(Map<String, dynamic> json) {
    return SkyCatalog(
      version: json['catalog_version'] as String? ?? 'sky-catalog-v1',
      stars: (json['stars'] as List<dynamic>? ?? const [])
          .map((value) => SkyStar.fromJson(value as Map<String, dynamic>))
          .toList(growable: false),
      constellations:
          (json['constellations'] as List<dynamic>? ?? const [])
              .map(
                (value) => ZodiacConstellation.fromJson(
                  value as Map<String, dynamic>,
                ),
              )
              .toList(growable: false),
    );
  }
}
