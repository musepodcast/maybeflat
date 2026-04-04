class CitySearchResult {
  const CitySearchResult({
    required this.geonameId,
    required this.name,
    required this.displayName,
    required this.latitude,
    required this.longitude,
    required this.countryCode,
    required this.countryName,
    required this.population,
    this.admin1Name,
  });

  final int geonameId;
  final String name;
  final String displayName;
  final double latitude;
  final double longitude;
  final String countryCode;
  final String countryName;
  final int population;
  final String? admin1Name;

  factory CitySearchResult.fromJson(Map<String, dynamic> json) {
    return CitySearchResult(
      geonameId: (json['geoname_id'] as num).toInt(),
      name: json['name'] as String? ?? 'Unnamed',
      displayName: json['display_name'] as String? ?? json['name'] as String? ?? 'Unnamed',
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      countryCode: json['country_code'] as String? ?? '',
      countryName: json['country_name'] as String? ?? '',
      population: (json['population'] as num?)?.toInt() ?? 0,
      admin1Name: json['admin1_name'] as String?,
    );
  }

  @override
  String toString() => displayName;
}
