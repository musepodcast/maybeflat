class CityCatalogEntry {
  const CityCatalogEntry({
    required this.name,
    required this.latitude,
    required this.longitude,
  });

  final String name;
  final double latitude;
  final double longitude;

  @override
  String toString() => name;
}

const cityCatalog = <CityCatalogEntry>[
  CityCatalogEntry(name: 'New York, USA', latitude: 40.7128, longitude: -74.0060),
  CityCatalogEntry(name: 'Los Angeles, USA', latitude: 34.0522, longitude: -118.2437),
  CityCatalogEntry(name: 'Chicago, USA', latitude: 41.8781, longitude: -87.6298),
  CityCatalogEntry(name: 'Houston, USA', latitude: 29.7604, longitude: -95.3698),
  CityCatalogEntry(name: 'Miami, USA', latitude: 25.7617, longitude: -80.1918),
  CityCatalogEntry(name: 'Seattle, USA', latitude: 47.6062, longitude: -122.3321),
  CityCatalogEntry(name: 'Anchorage, USA', latitude: 61.2181, longitude: -149.9003),
  CityCatalogEntry(name: 'Mexico City, Mexico', latitude: 19.4326, longitude: -99.1332),
  CityCatalogEntry(name: 'Toronto, Canada', latitude: 43.6532, longitude: -79.3832),
  CityCatalogEntry(name: 'Vancouver, Canada', latitude: 49.2827, longitude: -123.1207),
  CityCatalogEntry(name: 'Honolulu, USA', latitude: 21.3069, longitude: -157.8583),
  CityCatalogEntry(name: 'Reykjavik, Iceland', latitude: 64.1466, longitude: -21.9426),
  CityCatalogEntry(name: 'London, UK', latitude: 51.5074, longitude: -0.1278),
  CityCatalogEntry(name: 'Paris, France', latitude: 48.8566, longitude: 2.3522),
  CityCatalogEntry(name: 'Madrid, Spain', latitude: 40.4168, longitude: -3.7038),
  CityCatalogEntry(name: 'Rome, Italy', latitude: 41.9028, longitude: 12.4964),
  CityCatalogEntry(name: 'Berlin, Germany', latitude: 52.5200, longitude: 13.4050),
  CityCatalogEntry(name: 'Moscow, Russia', latitude: 55.7558, longitude: 37.6173),
  CityCatalogEntry(name: 'Cairo, Egypt', latitude: 30.0444, longitude: 31.2357),
  CityCatalogEntry(name: 'Cape Town, South Africa', latitude: -33.9249, longitude: 18.4241),
  CityCatalogEntry(name: 'Nairobi, Kenya', latitude: -1.2921, longitude: 36.8219),
  CityCatalogEntry(name: 'Lagos, Nigeria', latitude: 6.5244, longitude: 3.3792),
  CityCatalogEntry(name: 'Dubai, UAE', latitude: 25.2048, longitude: 55.2708),
  CityCatalogEntry(name: 'Mumbai, India', latitude: 19.0760, longitude: 72.8777),
  CityCatalogEntry(name: 'Delhi, India', latitude: 28.6139, longitude: 77.2090),
  CityCatalogEntry(name: 'Bangkok, Thailand', latitude: 13.7563, longitude: 100.5018),
  CityCatalogEntry(name: 'Singapore', latitude: 1.3521, longitude: 103.8198),
  CityCatalogEntry(name: 'Jakarta, Indonesia', latitude: -6.2088, longitude: 106.8456),
  CityCatalogEntry(name: 'Beijing, China', latitude: 39.9042, longitude: 116.4074),
  CityCatalogEntry(name: 'Shanghai, China', latitude: 31.2304, longitude: 121.4737),
  CityCatalogEntry(name: 'Seoul, South Korea', latitude: 37.5665, longitude: 126.9780),
  CityCatalogEntry(name: 'Tokyo, Japan', latitude: 35.6764, longitude: 139.6500),
  CityCatalogEntry(name: 'Manila, Philippines', latitude: 14.5995, longitude: 120.9842),
  CityCatalogEntry(name: 'Sydney, Australia', latitude: -33.8688, longitude: 151.2093),
  CityCatalogEntry(name: 'Melbourne, Australia', latitude: -37.8136, longitude: 144.9631),
  CityCatalogEntry(name: 'Auckland, New Zealand', latitude: -36.8509, longitude: 174.7645),
  CityCatalogEntry(name: 'Sao Paulo, Brazil', latitude: -23.5558, longitude: -46.6396),
  CityCatalogEntry(name: 'Rio de Janeiro, Brazil', latitude: -22.9068, longitude: -43.1729),
  CityCatalogEntry(name: 'Buenos Aires, Argentina', latitude: -34.6037, longitude: -58.3816),
  CityCatalogEntry(name: 'Lima, Peru', latitude: -12.0464, longitude: -77.0428),
  CityCatalogEntry(name: 'Quito, Ecuador', latitude: -0.1807, longitude: -78.4678),
  CityCatalogEntry(name: 'Santiago, Chile', latitude: -33.4489, longitude: -70.6693),
  CityCatalogEntry(name: 'Bogota, Colombia', latitude: 4.7110, longitude: -74.0721),
  CityCatalogEntry(name: 'McMurdo Station, Antarctica', latitude: -77.8419, longitude: 166.6863),
  CityCatalogEntry(name: 'Amundsen-Scott South Pole Station, Antarctica', latitude: -90.0, longitude: 0.0),
  CityCatalogEntry(name: 'Vinson Massif, Antarctica', latitude: -78.5250, longitude: -85.6167),
  CityCatalogEntry(name: 'Mount Erebus, Antarctica', latitude: -77.5300, longitude: 167.1600),
  CityCatalogEntry(name: 'Ross Ice Shelf, Antarctica', latitude: -81.5000, longitude: -175.0000),
  CityCatalogEntry(name: 'Palmer Station, Antarctica', latitude: -64.7741, longitude: -64.0538),
];
