import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/exposure_asset.dart';
import '../../state/app_state.dart';
import '../../widgets/interactive_map_canvas.dart';
import '../../widgets/risk_badge.dart';

class RiskMapScreen extends StatefulWidget {
  final AppState appState;
  final Function(String routeName, {Object? arguments})? onNavigateNamed;

  const RiskMapScreen({
    super.key,
    required this.appState,
    this.onNavigateNamed,
  });

  @override
  State<RiskMapScreen> createState() => _RiskMapScreenState();
}

class _RiskMapScreenState extends State<RiskMapScreen> {
  final TextEditingController _searchController =
      TextEditingController();

  @override
  void initState() {
    super.initState();

    _searchController.addListener(_onSearchTextChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchTextChanged);
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // SEARCH FIELD UI REFRESH
  // ---------------------------------------------------------------------------

  void _onSearchTextChanged() {
    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // SEARCH LOCATION
  //
  // IMPORTANT:
  // Typing does NOT change the selected location.
  //
  // The location is changed only when:
  //   1. The user presses Enter/Search.
  //   2. The user presses the arrow search button.
  // ---------------------------------------------------------------------------

  void _searchLocation() {
    final rawQuery = _searchController.text.trim();

    if (rawQuery.isEmpty) {
      return;
    }

    final query = rawQuery.toLowerCase();

    final matchingLocations = widget.appState.locations.where(
      (location) {
        final name = location.name.toLowerCase();
        final district = location.district.toLowerCase();

        return name.contains(query) ||
            district.contains(query);
      },
    ).toList();

    if (matchingLocations.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Location not found: $rawQuery',
          ),
        ),
      );

      return;
    }

    final location = matchingLocations.first;

    // Update the global selected location.
    widget.appState.selectLocation(location.id);

    // Keep the actual matched location name in the search box.
    _searchController.value = TextEditingValue(
      text: location.name,
      selection: TextSelection.collapsed(
        offset: location.name.length,
      ),
    );

    FocusScope.of(context).unfocus();

    if (mounted) {
      setState(() {});
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          'Selected: ${location.name}',
        ),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CLEAR SEARCH
  // ---------------------------------------------------------------------------

  void _clearSearch() {
    _searchController.clear();

    FocusScope.of(context).unfocus();

    if (mounted) {
      setState(() {});
    }
  }

  // ---------------------------------------------------------------------------
  // MAP LAYERS
  // ---------------------------------------------------------------------------

  void _showLayersBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(20),
        ),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(20.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment:
                        MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'Map Layers & Overlays',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: AppColors.textPrimary,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.close,
                          size: 18,
                        ),
                        onPressed: () =>
                            Navigator.pop(context),
                      ),
                    ],
                  ),

                  const Divider(),

                  _layerSwitchTile(
                    'Risk Zones & Hazard Polygons',
                    widget.appState.layerRiskZones,
                    'riskZones',
                    setModalState,
                  ),

                  _layerSwitchTile(
                    'Road Networks & Arteries',
                    widget.appState.layerRoads,
                    'roads',
                    setModalState,
                  ),

                  _layerSwitchTile(
                    'Rainfall Heatmap (IMD)',
                    widget.appState.layerRainfall,
                    'rainfall',
                    setModalState,
                  ),

                  _layerSwitchTile(
                    'Soil Moisture Index (SMAP)',
                    widget.appState.layerSoilMoisture,
                    'soilMoisture',
                    setModalState,
                  ),

                  _layerSwitchTile(
                    'Historical Landslide Scars (GSI)',
                    widget.appState
                        .layerHistoricalLandslides,
                    'historicalLandslides',
                    setModalState,
                  ),

                  _layerSwitchTile(
                    'Critical Infrastructure & Hospitals',
                    widget.appState.layerInfrastructure,
                    'infrastructure',
                    setModalState,
                  ),

                  _layerSwitchTile(
                    'Verified Citizen Reports',
                    widget.appState.layerCitizenReports,
                    'citizenReports',
                    setModalState,
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _layerSwitchTile(
    String title,
    bool value,
    String key,
    StateSetter setModalState,
  ) {
    return SwitchListTile(
      title: Text(
        title,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: AppColors.textPrimary,
        ),
      ),
      value: value,
      activeThumbColor: AppColors.primary,
      contentPadding: EdgeInsets.zero,
      dense: true,
      onChanged: (_) {
        widget.appState.toggleLayer(key);

        setModalState(() {});

        setState(() {});
      },
    );
  }

  // ---------------------------------------------------------------------------
  // BUILD
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final selectedLoc = widget.appState.selectedLocation;
    final riskResult = selectedLoc?.calculatedResult;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Interactive Risk Map'),
        actions: [
          IconButton(
            icon: const Icon(
              Icons.layers_outlined,
            ),
            tooltip: 'Layer Toggles',
            onPressed: _showLayersBottomSheet,
          ),
        ],
      ),

      body: Stack(
        children: [
          // -------------------------------------------------------------------
          // MAP
          // -------------------------------------------------------------------

          Positioned.fill(
            child: InteractiveMapCanvas(
              locations: widget.appState.locations,
              assets: widget.appState.assets,
              reports: widget.appState.reports,
              selectedLocationId:
                  widget.appState.selectedLocationId,

              showRiskZones:
                  widget.appState.layerRiskZones,

              showRoads:
                  widget.appState.layerRoads,

              showRainfallOverlay:
                  widget.appState.layerRainfall,

              showSoilMoistureOverlay:
                  widget.appState.layerSoilMoisture,

              showHistoricalLandslides:
                  widget.appState
                      .layerHistoricalLandslides,

              showInfrastructure:
                  widget.appState.layerInfrastructure,

              showCitizenReports:
                  widget.appState.layerCitizenReports,

              // ---------------------------------------------------------------
              // MAP LOCATION SELECTION
              // ---------------------------------------------------------------

              onSelectLocation: (locId) {
                widget.appState.selectLocation(locId);

                // Put the selected location into the search field.
                final selected = widget.appState.selectedLocation;

                if (selected != null) {
                  _searchController.value =
                      TextEditingValue(
                    text: selected.name,
                    selection:
                        TextSelection.collapsed(
                      offset: selected.name.length,
                    ),
                  );
                }

                setState(() {});
              },

              // ---------------------------------------------------------------
              // ASSET SELECTION
              // ---------------------------------------------------------------

              onSelectAsset: (asset) {
                widget.appState.selectLocation(
                  asset.locationId,
                );

                final selected =
                    widget.appState.selectedLocation;

                if (selected != null) {
                  _searchController.value =
                      TextEditingValue(
                    text: selected.name,
                    selection:
                        TextSelection.collapsed(
                      offset: selected.name.length,
                    ),
                  );
                }

                _showAssetDialog(asset);
              },

              // ---------------------------------------------------------------
              // CITIZEN REPORT SELECTION
              // ---------------------------------------------------------------

              onSelectReport: (report) {
                _showReportDialog(report);
              },
            ),
          ),

          // -------------------------------------------------------------------
          // SEARCH BAR
          // -------------------------------------------------------------------

          Positioned(
            top: 12,
            left: 12,
            right: 60,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(
                horizontal: 12,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withAlpha(240),
                borderRadius:
                    BorderRadius.circular(12),
                border: Border.all(
                  color: AppColors.border,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x10000000),
                    blurRadius: 8,
                    offset: Offset(0, 2),
                  ),
                ],
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.search,
                    size: 18,
                    color: AppColors.textSecondary,
                  ),

                  const SizedBox(width: 8),

                  Expanded(
                    child: TextField(
                      controller:
                          _searchController,

                      textInputAction:
                          TextInputAction.search,

                      decoration:
                          const InputDecoration(
                        hintText:
                            'Search location...',
                        border:
                            InputBorder.none,
                        isDense: true,
                      ),

                      // IMPORTANT:
                      // Search only after pressing Enter.
                      onSubmitted: (_) {
                        _searchLocation();
                      },
                    ),
                  ),

                  // -----------------------------------------------------------
                  // CLEAR BUTTON
                  // -----------------------------------------------------------

                  if (_searchController
                      .text
                      .isNotEmpty)
                    IconButton(
                      icon: const Icon(
                        Icons.clear,
                        size: 18,
                      ),
                      tooltip: 'Clear',
                      onPressed: _clearSearch,
                    ),

                  // -----------------------------------------------------------
                  // SEARCH BUTTON
                  // -----------------------------------------------------------

                  IconButton(
                    icon: const Icon(
                      Icons.arrow_forward,
                      size: 20,
                    ),
                    tooltip: 'Search',
                    onPressed: _searchLocation,
                  ),
                ],
              ),
            ),
          ),

          // -------------------------------------------------------------------
          // SELECTED LOCATION DETAILS
          // -------------------------------------------------------------------

          if (selectedLoc != null)
            Positioned(
              bottom: 12,
              left: 12,
              right: 12,
              child: Container(
                padding:
                    const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius:
                      BorderRadius.circular(16),
                  border: Border.all(
                    color: AppColors.border,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Color(0x15000000),
                      blurRadius: 14,
                      offset: Offset(0, 4),
                    ),
                  ],
                ),

                child: Column(
                  mainAxisSize:
                      MainAxisSize.min,
                  crossAxisAlignment:
                      CrossAxisAlignment.start,

                  children: [
                    // ---------------------------------------------------------
                    // LOCATION NAME + RISK
                    // ---------------------------------------------------------

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,

                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment:
                                CrossAxisAlignment
                                    .start,
                            children: [
                              Text(
                                selectedLoc.name,
                                maxLines: 2,
                                overflow:
                                    TextOverflow
                                        .ellipsis,
                                style:
                                    const TextStyle(
                                  fontSize: 16,
                                  fontWeight:
                                      FontWeight
                                          .w900,
                                  color: AppColors
                                      .textPrimary,
                                ),
                              ),

                              Text(
                                '${selectedLoc.district}, ${selectedLoc.state}',
                                style:
                                    const TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      FontWeight
                                          .w500,
                                  color: AppColors
                                      .textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),

                        const SizedBox(width: 10),

                        RiskBadge(
                          riskLevel:
                              riskResult?.riskLevel ??
                                  RiskLevel.high,
                          score:
                              riskResult?.riskScore,
                          isCompact: true,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ---------------------------------------------------------
                    // RISK METRICS
                    // ---------------------------------------------------------

                    Row(
                      mainAxisAlignment:
                          MainAxisAlignment
                              .spaceBetween,
                      children: [
                        _infoMetric(
                          'Rainfall',
                          '${selectedLoc.dynamicConditions.rainfallMm.toInt()} mm',
                          AppColors.primary,
                          AppColors.primaryPastel,
                        ),

                        _infoMetric(
                          'Soil Moisture',
                          '${(selectedLoc.dynamicConditions.soilMoistureIndex * 100).toInt()}%',
                          AppColors.riskModerate,
                          AppColors
                              .riskModeratePastel,
                        ),

                        _infoMetric(
                          'Slope',
                          '${selectedLoc.susceptibility.slopeAngleDegrees.toInt()}°',
                          AppColors.riskHigh,
                          AppColors.riskHighPastel,
                        ),

                        _infoMetric(
                          'Confidence',
                          '${((riskResult?.confidence ?? 0.93) * 100).toInt()}%',
                          AppColors.teal,
                          AppColors.tealPastel,
                        ),
                      ],
                    ),

                    const SizedBox(height: 12),

                    // ---------------------------------------------------------
                    // ACTION BUTTONS
                    // ---------------------------------------------------------

                    Row(
                      children: [
                        Expanded(
                          child:
                              ElevatedButton.icon(
                            onPressed: () {
                              widget
                                  .onNavigateNamed
                                  ?.call(
                                'risk_details',
                              );
                            },

                            icon: const Icon(
                              Icons
                                  .assessment_outlined,
                              size: 14,
                            ),

                            label:
                                const Text(
                              'View Risk Details',
                              style:
                                  TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),

                            style:
                                ElevatedButton
                                    .styleFrom(
                              backgroundColor:
                                  AppColors
                                      .primary,
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(width: 8),

                        Expanded(
                          child:
                              OutlinedButton.icon(
                            onPressed: () {
                              final selected =
                                  widget.appState
                                      .selectedLocation;

                              if (selected ==
                                  null) {
                                return;
                              }

                              widget
                                  .onNavigateNamed
                                  ?.call(
                                'risk_routing',
                              );
                            },

                            icon: const Icon(
                              Icons.alt_route,
                              size: 14,
                            ),

                            label:
                                const Text(
                              'Get Safe Route',
                              style:
                                  TextStyle(
                                fontSize: 12,
                                fontWeight:
                                    FontWeight
                                        .w700,
                              ),
                            ),

                            style:
                                OutlinedButton
                                    .styleFrom(
                              padding:
                                  const EdgeInsets
                                      .symmetric(
                                vertical: 10,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // INFO METRIC
  // ---------------------------------------------------------------------------

  Widget _infoMetric(
    String label,
    String value,
    Color color,
    Color backgroundColor,
  ) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 6,
      ),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius:
            BorderRadius.circular(8),
        border: Border.all(
          color: color.withAlpha(50),
        ),
      ),
      child: Column(
        crossAxisAlignment:
            CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: AppColors.textMuted,
            ),
          ),

          const SizedBox(height: 1),

          Text(
            value,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // ASSET DIALOG
  // ---------------------------------------------------------------------------

  void _showAssetDialog(
    ExposureAsset asset,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,

        title: Row(
          children: [
            Icon(
              asset.type.icon,
              color: AppColors.primary,
            ),

            const SizedBox(width: 8),

            Expanded(
              child: Text(
                asset.name,
                style:
                    const TextStyle(
                  fontSize: 15,
                  fontWeight:
                      FontWeight.w800,
                ),
              ),
            ),
          ],
        ),

        content: Column(
          mainAxisSize:
              MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              'Type: ${asset.type.displayName}',
              style:
                  const TextStyle(
                color:
                    AppColors.textSecondary,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Exposure Level: ${asset.exposureLevel.toInt()}%',
              style:
                  const TextStyle(
                color:
                    AppColors.riskHigh,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Connectivity Impact: ${asset.connectivityImpact.toInt()}%',
              style:
                  const TextStyle(
                color:
                    AppColors.primary,
                fontWeight:
                    FontWeight.w800,
              ),
            ),

            const SizedBox(height: 4),

            Text(
              'Population at Risk: ${asset.estimatedPopulationAtRisk}',
              style:
                  const TextStyle(
                color:
                    AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 8),

            Text(
              'Notes: ${asset.notes}',
              style:
                  const TextStyle(
                fontSize: 12,
                color:
                    AppColors.textSecondary,
              ),
            ),
          ],
        ),

        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context),
            child:
                const Text('Close'),
          ),
        ],
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // CITIZEN REPORT DIALOG
  // ---------------------------------------------------------------------------

  void _showReportDialog(
    dynamic report,
  ) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,

        title: Text(
          'Report #${report.reportId}',
        ),

        content: Text(
          '${report.notes}\n\n'
          'Status: ${report.verificationStatus.name.toUpperCase()}',
        ),

        actions: [
          TextButton(
            onPressed: () =>
                Navigator.pop(context),
            child:
                const Text('Close'),
          ),
        ],
      ),
    );
  }
}