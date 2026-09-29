import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:latlong2/latlong.dart';

class GisGeoJsonService {
  Future<List<List<LatLng>>> loadLineStrings(
    String assetPath,
  ) async {
    final jsonString = await rootBundle.loadString(assetPath);
    final data = jsonDecode(jsonString);

    final List<List<LatLng>> lines = [];

    if (data is! Map) {
      return lines;
    }

    final features = data['features'];

    if (features is! List) {
      return lines;
    }

    for (final feature in features) {
      if (feature is! Map) {
        continue;
      }

      final geometry = feature['geometry'];

      if (geometry is! Map) {
        continue;
      }

      if (geometry['type'] != 'LineString') {
        continue;
      }

      final coordinates = geometry['coordinates'];

      if (coordinates is! List) {
        continue;
      }

      final line = <LatLng>[];

      for (final coordinate in coordinates) {
        if (coordinate is! List || coordinate.length < 2) {
          continue;
        }

        final longitude = coordinate[0];
        final latitude = coordinate[1];

        if (longitude is num && latitude is num) {
          line.add(
            LatLng(
              latitude.toDouble(),
              longitude.toDouble(),
            ),
          );
        }
      }

      if (line.length >= 2) {
        lines.add(line);
      }
    }

    return lines;
  }

  Future<List<LatLng>> loadPoints(
    String assetPath,
  ) async {
    final jsonString = await rootBundle.loadString(assetPath);
    final data = jsonDecode(jsonString);

    final List<LatLng> points = [];

    if (data is! Map) {
      return points;
    }

    final features = data['features'];

    if (features is! List) {
      return points;
    }

    for (final feature in features) {
      if (feature is! Map) {
        continue;
      }

      final geometry = feature['geometry'];

      if (geometry is! Map) {
        continue;
      }

      if (geometry['type'] != 'Point') {
        continue;
      }

      final coordinates = geometry['coordinates'];

      if (coordinates is! List ||
          coordinates.length < 2) {
        continue;
      }

      final longitude = coordinates[0];
      final latitude = coordinates[1];

      if (longitude is num && latitude is num) {
        points.add(
          LatLng(
            latitude.toDouble(),
            longitude.toDouble(),
          ),
        );
      }
    }

    return points;
  }

  Future<List<List<LatLng>>> loadBoundary(
    String assetPath,
  ) async {
    final jsonString = await rootBundle.loadString(assetPath);
    final data = jsonDecode(jsonString);

    final List<List<LatLng>> boundaries = [];

    if (data is! Map) {
      return boundaries;
    }

    final features = data['features'];

    if (features is! List) {
      return boundaries;
    }

    for (final feature in features) {
      if (feature is! Map) {
        continue;
      }

      final geometry = feature['geometry'];

      if (geometry is! Map) {
        continue;
      }

      final type = geometry['type'];
      final coordinates = geometry['coordinates'];

      if (type == 'Polygon' &&
          coordinates is List) {
        _addPolygonRings(
          coordinates,
          boundaries,
        );
      }

      if (type == 'MultiPolygon' &&
          coordinates is List) {
        for (final polygon in coordinates) {
          if (polygon is List) {
            _addPolygonRings(
              polygon,
              boundaries,
            );
          }
        }
      }
    }

    return boundaries;
  }

  void _addPolygonRings(
    List polygon,
    List<List<LatLng>> output,
  ) {
    for (final ring in polygon) {
      if (ring is! List) {
        continue;
      }

      final points = <LatLng>[];

      for (final coordinate in ring) {
        if (coordinate is! List ||
            coordinate.length < 2) {
          continue;
        }

        final longitude = coordinate[0];
        final latitude = coordinate[1];

        if (longitude is num && latitude is num) {
          points.add(
            LatLng(
              latitude.toDouble(),
              longitude.toDouble(),
            ),
          );
        }
      }

      if (points.length >= 3) {
        output.add(points);
      }
    }
  }
}