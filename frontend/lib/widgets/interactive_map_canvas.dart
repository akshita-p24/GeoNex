import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../core/constants/app_colors.dart';
import '../core/models/citizen_report.dart';
import '../core/models/exposure_asset.dart';
import '../core/models/risk_data.dart';
import '../data/services/gis_geojson_service.dart';

enum GisStudyArea {
  papumPare,
  westKameng,
}

class InteractiveMapCanvas extends StatefulWidget {
  final List<RiskLocation> locations;
  final List<ExposureAsset> assets;
  final List<CitizenReport> reports;

  final String? selectedLocationId;

  final bool showRiskZones;
  final bool showRoads;
  final bool showRainfallOverlay;
  final bool showSoilMoistureOverlay;
  final bool showHistoricalLandslides;
  final bool showInfrastructure;
  final bool showCitizenReports;

  final GisStudyArea studyArea;
  final ValueChanged<String> onSelectLocation;
  final ValueChanged<ExposureAsset> onSelectAsset;
  final ValueChanged<CitizenReport> onSelectReport;

  const InteractiveMapCanvas({
    super.key,
    required this.locations,
    required this.assets,
    required this.reports,
    required this.selectedLocationId,
    required this.showRiskZones,
    required this.showRoads,
    required this.showRainfallOverlay,
    required this.showSoilMoistureOverlay,
    required this.showHistoricalLandslides,
    required this.showInfrastructure,
    required this.showCitizenReports,
    this.studyArea = GisStudyArea.papumPare,
    required this.onSelectLocation,
    required this.onSelectAsset,
    required this.onSelectReport,
  });

  @override
  State<InteractiveMapCanvas> createState() =>
      _InteractiveMapCanvasState();
}

class _InteractiveMapCanvasState
    extends State<InteractiveMapCanvas> {
  final MapController _mapController =
      MapController();

  final GisGeoJsonService _gisService =
      GisGeoJsonService();
  String _studyAreaName() {
    switch (widget.studyArea) {
      case GisStudyArea.papumPare:
        return 'Papum Pare';

      case GisStudyArea.westKameng:
        return 'West Kameng';
    }
  }
  // ============================================================
  // GIS DATA
  // ============================================================

  List<List<LatLng>> _roads = [];
  List<List<LatLng>> _rivers = [];
  List<LatLng> _villages = [];
  List<List<LatLng>> _boundary = [];

  bool _gisLoading = true;
  String? _gisError;

  // ============================================================
  // DEFAULT MAP POSITION
  // ============================================================

  static const LatLng _defaultCenter =
      LatLng(27.3000, 94.0000);

  static const double _defaultZoom = 7.5;

  // ============================================================
  // INITIALIZATION
  // ============================================================

  @override
  void initState() {
    super.initState();
    _loadGisLayers();
  }

  // ============================================================
  // LOAD GIS DATA
  // ============================================================
  Future<void> _loadGisLayers() async {
  try {
    final String roadsPath;
    final String riversPath;
    final String villagesPath;
    final String boundaryPath;

    switch (widget.studyArea) {
      case GisStudyArea.papumPare:
        roadsPath =
            'assets/gis/roads_papum_papum.geojson';

        riversPath =
            'assets/gis/rivers_papum_pare.geojson';

        villagesPath =
            'assets/gis/villages_papum_pare.geojson';

        boundaryPath =
            'assets/gis/papum_pare_boundary.geojson';

        break;

      case GisStudyArea.westKameng:
        roadsPath =
            'assets/gis/west_kameng/roads_west_kameng.geojson';

        riversPath =
            'assets/gis/west_kameng/rivers_west_kameng.geojson';

        villagesPath =
            'assets/gis/west_kameng/villages_west_kameng.geojson';

        boundaryPath =
            'assets/gis/west_kameng/west_kameng_boundary.geojson';

        break;
    }

    final roads =
        await _gisService.loadLineStrings(roadsPath);

    final rivers =
        await _gisService.loadLineStrings(riversPath);

    final villages =
        await _gisService.loadPoints(villagesPath);

    final boundary =
        await _gisService.loadBoundary(boundaryPath);

    if (!mounted) {
      return;
    }

    setState(() {
      _roads = roads;
      _rivers = rivers;
      _villages = villages;
      _boundary = boundary;
      _gisLoading = false;
      _gisError = null;
    });
  } catch (e) {
    if (!mounted) {
      return;
    }

    setState(() {
      _gisLoading = false;
      _gisError = e.toString();
    });
  }
}

  // ============================================================
  // SELECTED LOCATION
  // ============================================================

  @override
  void didUpdateWidget(
  covariant InteractiveMapCanvas oldWidget,
) {
  super.didUpdateWidget(oldWidget);

  if (widget.studyArea != oldWidget.studyArea) {
    setState(() {
      _roads = [];
      _rivers = [];
      _villages = [];
      _boundary = [];
      _gisLoading = true;
      _gisError = null;
    });

    _loadGisLayers();
  }

  if (widget.selectedLocationId !=
          oldWidget.selectedLocationId &&
      widget.selectedLocationId != null) {
    _moveToSelectedLocation();
  }
}

  void _moveToSelectedLocation() {
    final selected = _selectedLocation();

    if (selected == null) {
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }

      _mapController.move(
        LatLng(
          selected.latitude,
          selected.longitude,
        ),
        11.5,
      );
    });
  }

  RiskLocation? _selectedLocation() {
    final id = widget.selectedLocationId;

    if (id == null) {
      return null;
    }

    for (final location in widget.locations) {
      if (location.id == id) {
        return location;
      }
    }

    return null;
  }

  LatLng _selectedCenter() {
    final selected = _selectedLocation();

    if (selected == null) {
      return _defaultCenter;
    }

    return LatLng(
      selected.latitude,
      selected.longitude,
    );
  }

  // ============================================================
  // RISK
  // ============================================================

  RiskResult? _riskResult(
    RiskLocation location,
  ) {
    return location.calculatedResult;
  }

  Color _riskColor(
    RiskLocation location,
  ) {
    final result = _riskResult(location);

    if (result != null) {
      return result.color;
    }

    return AppColors.riskModerate;
  }

  double _riskScore(
    RiskLocation location,
  ) {
    return _riskResult(location)?.riskScore ?? 0.0;
  }

  double _riskRadius(
    RiskLocation location,
  ) {
    final score = _riskScore(location);

    if (score >= 80) {
      return 2500;
    }

    if (score >= 65) {
      return 1800;
    }

    if (score >= 40) {
      return 1200;
    }

    return 800;
  }

  // ============================================================
  // RISK ZONES
  // ============================================================

  List<CircleMarker> _buildRiskZones() {
    if (!widget.showRiskZones) {
      return [];
    }

    return widget.locations.map((location) {
      final color = _riskColor(location);

      return CircleMarker(
        point: LatLng(
          location.latitude,
          location.longitude,
        ),
        radius: _riskRadius(location),
        useRadiusInMeter: true,
        color: color.withValues(alpha: 0.20),
        borderColor: color.withValues(alpha: 0.75),
        borderStrokeWidth: 2,
      );
    }).toList();
  }

  // ============================================================
  // RAINFALL
  // ============================================================

  List<CircleMarker> _buildRainfallOverlay() {
    if (!widget.showRainfallOverlay) {
      return [];
    }

    return widget.locations.map((location) {
      final rainfall =
          location.dynamicConditions.rainfallMm;

      final radius =
          (500 + rainfall * 40).clamp(
        500.0,
        5000.0,
      );

      final intensity =
          (rainfall / 150.0).clamp(
        0.10,
        0.55,
      );

      return CircleMarker(
        point: LatLng(
          location.latitude,
          location.longitude,
        ),
        radius: radius,
        useRadiusInMeter: true,
        color: Colors.blue.withValues(
          alpha: intensity,
        ),
        borderColor: Colors.blue.withValues(
          alpha: 0.45,
        ),
        borderStrokeWidth: 1,
      );
    }).toList();
  }

  // ============================================================
  // SOIL MOISTURE
  // ============================================================

  List<CircleMarker> _buildSoilMoistureOverlay() {
    if (!widget.showSoilMoistureOverlay) {
      return [];
    }

    return widget.locations.map((location) {
      final moisture =
          location.dynamicConditions.soilMoistureIndex
              .clamp(0.0, 1.0);

      final radius =
          700 + (moisture * 1800);

      return CircleMarker(
        point: LatLng(
          location.latitude,
          location.longitude,
        ),
        radius: radius,
        useRadiusInMeter: true,
        color: Colors.teal.withValues(
          alpha: 0.10 + (moisture * 0.25),
        ),
        borderColor: Colors.teal.withValues(
          alpha: 0.45,
        ),
        borderStrokeWidth: 1,
      );
    }).toList();
  }

  // ============================================================
  // ROADS
  // ============================================================

  List<Polyline> _buildRoadOverlays() {
    if (!widget.showRoads) {
      return [];
    }

    return _roads.map((road) {
      return Polyline(
        points: road,
        strokeWidth: 1.5,
        color: Colors.orange.withValues(
          alpha: 0.75,
        ),
      );
    }).toList();
  }

  // ============================================================
  // RIVERS
  // ============================================================

  List<Polyline> _buildRiverOverlays() {
    return _rivers.map((river) {
      return Polyline(
        points: river,
        strokeWidth: 2.0,
        color: Colors.blue.withValues(
          alpha: 0.80,
        ),
      );
    }).toList();
  }

  // ============================================================
  // BOUNDARY
  // ============================================================

  List<Polyline> _buildBoundaryOverlay() {
    return _boundary.map((ring) {
      return Polyline(
        points: ring,
        strokeWidth: 2.5,
        color: Colors.white.withValues(
          alpha: 0.85,
        ),
      );
    }).toList();
  }

  // ============================================================
  // VILLAGES
  // ============================================================

  List<Marker> _buildVillageMarkers() {
    return _villages.map((point) {
      return Marker(
        point: point,
        width: 18,
        height: 18,
        child: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white,
            border: Border.all(
              color: Colors.deepPurple,
              width: 2,
            ),
          ),
          child: const Icon(
            Icons.home,
            size: 10,
            color: Colors.deepPurple,
          ),
        ),
      );
    }).toList();
  }

  // ============================================================
  // LOCATION MARKERS
  // ============================================================

  List<Marker> _buildLocationMarkers() {
    return widget.locations.map((location) {
      final selected =
          location.id == widget.selectedLocationId;

      final color = _riskColor(location);
      final score = _riskScore(location);

      return Marker(
        point: LatLng(
          location.latitude,
          location.longitude,
        ),
        width: selected ? 150 : 120,
        height: selected ? 90 : 75,
        child: GestureDetector(
          onTap: () {
            widget.onSelectLocation(location.id);

            _mapController.move(
              LatLng(
                location.latitude,
                location.longitude,
              ),
              11.5,
            );
          },
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (selected)
                Container(
                  padding:
                      const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(
                      alpha: 0.85,
                    ),
                    borderRadius:
                        BorderRadius.circular(6),
                    border: Border.all(
                      color: color,
                      width: 1,
                    ),
                  ),
                  child: Text(
                    location.name,
                    maxLines: 1,
                    overflow:
                        TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),

              const SizedBox(height: 3),

              Container(
                width: selected ? 34 : 28,
                height: selected ? 34 : 28,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: color,
                  border: Border.all(
                    color: Colors.white,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: color.withValues(
                        alpha: 0.45,
                      ),
                      blurRadius: 8,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    score.round().toString(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }).toList();
  }

  // ============================================================
  // HISTORICAL LANDSLIDES
  // ============================================================

  List<Marker> _buildHistoricalLandslideMarkers() {
    if (!widget.showHistoricalLandslides) {
      return [];
    }

    // No historical landslide GeoJSON has been
    // provided yet. Do not invent locations.
    return [];
  }

  // ============================================================
  // INFRASTRUCTURE
  // ============================================================

  List<Marker> _buildInfrastructureMarkers() {
    if (!widget.showInfrastructure) {
      return [];
    }

    // ExposureAsset coordinate fields have not been
    // provided, so do not guess them.
    return [];
  }

  // ============================================================
  // CITIZEN REPORTS
  // ============================================================

  List<Marker> _buildCitizenReportMarkers() {
    if (!widget.showCitizenReports) {
      return [];
    }

    // CitizenReport coordinate fields have not been
    // provided, so do not guess them.
    return [];
  }

  // ============================================================
  // LEGEND
  // ============================================================

  Widget _buildLegend() {
    return Positioned(
      left: 12,
      bottom: 12,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.black.withValues(
            alpha: 0.82,
          ),
          borderRadius:
              BorderRadius.circular(8),
          border: Border.all(
            color: Colors.white.withValues(
              alpha: 0.12,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            const Text(
              'RISK LEVEL',
              style: TextStyle(
                color: Colors.white,
                fontSize: 9,
                fontWeight: FontWeight.w800,
                letterSpacing: 1,
              ),
            ),

            const SizedBox(height: 7),

            _legendItem(
              AppColors.riskLow,
              'LOW',
            ),

            _legendItem(
              AppColors.riskModerate,
              'MODERATE',
            ),

            _legendItem(
              AppColors.riskHigh,
              'HIGH',
            ),

            _legendItem(
              AppColors.riskCritical,
              'CRITICAL',
            ),

            const SizedBox(height: 7),

            _legendLine(
              Colors.orange,
              'Roads',
            ),

            _legendLine(
              Colors.blue,
              'Rivers',
            ),

            _legendLine(
              Colors.white,
              'Papum Pare Boundary',
            ),

            _legendVillage(
              Colors.deepPurple,
              'Villages',
            ),
          ],
        ),
      ),
    );
  }

  Widget _legendItem(
    Color color,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendLine(
    Color color,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 14,
            height: 3,
            color: color,
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _legendVillage(
    Color color,
    String label,
  ) {
    return Padding(
      padding: const EdgeInsets.only(
        bottom: 4,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 9,
            height: 9,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.white,
              border: Border.all(
                color: color,
                width: 2,
              ),
            ),
          ),
          const SizedBox(width: 7),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 8,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LAYER STATUS
  // ============================================================

  Widget _buildLayerStatus() {
    final activeLayers = <String>[
      _studyAreaName(),
    ];

    if (widget.showRiskZones) {
      activeLayers.add('Risk');
    }

    if (widget.showRoads) {
      activeLayers.add('Roads');
    }

    if (widget.showRainfallOverlay) {
      activeLayers.add('Rain');
    }

    if (widget.showSoilMoistureOverlay) {
      activeLayers.add('Soil');
    }

    if (widget.showHistoricalLandslides) {
      activeLayers.add('GSI');
    }

    if (widget.showInfrastructure) {
      activeLayers.add('Assets');
    }

    if (widget.showCitizenReports) {
      activeLayers.add('Reports');
    }

    if (_rivers.isNotEmpty) {
      activeLayers.add('Rivers');
    }

    if (_villages.isNotEmpty) {
      activeLayers.add('Villages');
    }

    if (activeLayers.isEmpty) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: 12,
      right: 12,
      child: Container(
        padding:
            const EdgeInsets.symmetric(
          horizontal: 9,
          vertical: 6,
        ),
        decoration: BoxDecoration(
          color: Colors.black.withValues(
            alpha: 0.80,
          ),
          borderRadius:
              BorderRadius.circular(7),
        ),
        child: Text(
          activeLayers.join(' • '),
          style: const TextStyle(
            color: Colors.white,
            fontSize: 8,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }

  // ============================================================
  // GIS STATUS
  // ============================================================

  Widget _buildGisStatus() {
    if (_gisLoading) {
      return Positioned(
        top: 12,
        left: 12,
        child: Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 7,
          ),
          decoration: BoxDecoration(
            color: Colors.black.withValues(
              alpha: 0.82,
            ),
            borderRadius:
                BorderRadius.circular(7),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child:
                    CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              ),
              SizedBox(width: 7),
              Text(
                'Loading GIS...',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 9,
                ),
              ),
            ],
          ),
        ),
      );
    }

    if (_gisError != null) {
      return Positioned(
        top: 12,
        left: 12,
        child: Container(
          constraints:
              const BoxConstraints(
            maxWidth: 240,
          ),
          padding:
              const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: Colors.red.withValues(
              alpha: 0.85,
            ),
            borderRadius:
                BorderRadius.circular(7),
          ),
          child: Text(
            'GIS loading failed\n$_gisError',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 9,
            ),
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final center =
        widget.selectedLocationId != null
            ? _selectedCenter()
            : _defaultCenter;

    return ClipRRect(
      borderRadius:
          BorderRadius.circular(12),
      child: Stack(
        children: [
          FlutterMap(
            mapController:
                _mapController,

            options: MapOptions(
              initialCenter: center,
              initialZoom: _defaultZoom,
              minZoom: 5,
              maxZoom: 18,
              interactionOptions:
                  const InteractionOptions(
                flags: InteractiveFlag.all,
              ),
            ),

            children: [
              // =================================================
              // BASE MAP
              // =================================================

              TileLayer(
                urlTemplate:
                    'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName:
                    'com.riskoraction.sih_risk_to_action',
              ),

              // =================================================
              // PAPUM PARE BOUNDARY
              // =================================================

              if (_boundary.isNotEmpty)
                PolylineLayer(
                  polylines:
                      _buildBoundaryOverlay(),
                ),

              // =================================================
              // RIVERS
              // =================================================

              if (_rivers.isNotEmpty)
                PolylineLayer(
                  polylines:
                      _buildRiverOverlays(),
                ),

              // =================================================
              // ROADS
              // =================================================

              if (widget.showRoads &&
                  _roads.isNotEmpty)
                PolylineLayer(
                  polylines:
                      _buildRoadOverlays(),
                ),

              // =================================================
              // RISK ZONES
              // =================================================

              if (widget.showRiskZones)
                CircleLayer(
                  circles:
                      _buildRiskZones(),
                ),

              // =================================================
              // RAINFALL
              // =================================================

              if (widget.showRainfallOverlay)
                CircleLayer(
                  circles:
                      _buildRainfallOverlay(),
                ),

              // =================================================
              // SOIL MOISTURE
              // =================================================

              if (widget.showSoilMoistureOverlay)
                CircleLayer(
                  circles:
                      _buildSoilMoistureOverlay(),
                ),

              // =================================================
              // VILLAGES
              // =================================================

              if (_villages.isNotEmpty)
                MarkerLayer(
                  markers:
                      _buildVillageMarkers(),
                ),

              // =================================================
              // HISTORICAL LANDSLIDES
              // =================================================

              if (widget.showHistoricalLandslides)
                MarkerLayer(
                  markers:
                      _buildHistoricalLandslideMarkers(),
                ),

              // =================================================
              // INFRASTRUCTURE
              // =================================================

              if (widget.showInfrastructure)
                MarkerLayer(
                  markers:
                      _buildInfrastructureMarkers(),
                ),

              // =================================================
              // CITIZEN REPORTS
              // =================================================

              if (widget.showCitizenReports)
                MarkerLayer(
                  markers:
                      _buildCitizenReportMarkers(),
                ),

              // =================================================
              // RISK LOCATIONS
              // =================================================

              MarkerLayer(
                markers:
                    _buildLocationMarkers(),
              ),

              // =================================================
              // ATTRIBUTION
              // =================================================

              RichAttributionWidget(
                attributions: [
                  TextSourceAttribution(
                    'OpenStreetMap contributors',
                  ),
                ],
              ),
            ],
          ),

          _buildLegend(),

          _buildLayerStatus(),

          _buildGisStatus(),

          // ====================================================
          // RECENTER
          // ====================================================

          Positioned(
            right: 12,
            bottom: 12,
            child:
                FloatingActionButton.small(
              heroTag:
                  'risk_map_recenter',
              backgroundColor:
                  Colors.black.withValues(
                alpha: 0.82,
              ),
              foregroundColor:
                  Colors.white,
              onPressed: () {
                final selected =
                    _selectedLocation();

                if (selected != null) {
                  _mapController.move(
                    LatLng(
                      selected.latitude,
                      selected.longitude,
                    ),
                    11.5,
                  );
                } else {
                  _mapController.move(
                    _defaultCenter,
                    _defaultZoom,
                  );
                }
              },
              child: const Icon(
                Icons.my_location,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}