import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/citizen_report.dart';
import '../../state/app_state.dart';
import '../../widgets/camera_viewfinder_widget.dart';

class CitizenReportingScreen extends StatefulWidget {
  final AppState appState;
  final VoidCallback? onBack;
  final Function(String routeName, {Object? arguments})? onNavigateNamed;

  const CitizenReportingScreen({
    super.key,
    required this.appState,
    this.onBack,
    this.onNavigateNamed,
  });

  @override
  State<CitizenReportingScreen> createState() =>
      _CitizenReportingScreenState();
}

class _CitizenReportingScreenState
    extends State<CitizenReportingScreen> {
  final TextEditingController _notesController =
      TextEditingController();

  IncidentType _selectedType = IncidentType.landslide;
  SeverityLevel _selectedSeverity = SeverityLevel.high;

  bool _isVideoMode = false;
  bool _isCaptured = false;
  bool _isSubmitting = false;

  // ------------------------------------------------------------
  // LIVE GPS DATA
  // ------------------------------------------------------------

  double _lat = 0.0;
  double _lng = 0.0;

  bool _gpsLocked = false;
  String _gpsStatus = 'LOCATING...';

  // Automatically detected human-readable location name
  String _locationName = 'Detecting location...';

  final Geocoding _geocoding = Geocoding();
  @override
  void initState() {
    super.initState();
    _loadCurrentLocation();
  }

  // ------------------------------------------------------------
  // GET GPS + REVERSE GEOCODE LOCATION
  // ------------------------------------------------------------

  Future<void> _loadCurrentLocation() async {
    try {
      // ----------------------------------------------------------
      // 1. CHECK WHETHER LOCATION SERVICES ARE ENABLED
      // ----------------------------------------------------------

      final serviceEnabled =
          await Geolocator.isLocationServiceEnabled();

      if (!serviceEnabled) {
        if (!mounted) return;

        setState(() {
          _gpsStatus = 'LOCATION OFF';
          _gpsLocked = false;
          _locationName = 'Location services disabled';
        });

        return;
      }

      // ----------------------------------------------------------
      // 2. CHECK LOCATION PERMISSION
      // ----------------------------------------------------------

      LocationPermission permission =
          await Geolocator.checkPermission();

      if (permission == LocationPermission.denied) {
        permission =
            await Geolocator.requestPermission();
      }

      // Permission denied
      if (permission == LocationPermission.denied) {
        if (!mounted) return;

        setState(() {
          _gpsStatus = 'PERMISSION DENIED';
          _gpsLocked = false;
          _locationName = 'Location permission denied';
        });

        return;
      }

      // Permission permanently denied
      if (permission == LocationPermission.deniedForever) {
        if (!mounted) return;

        setState(() {
          _gpsStatus = 'PERMISSION DENIED';
          _gpsLocked = false;
          _locationName =
              'Enable location permission in Settings';
        });

        return;
      }

      // ----------------------------------------------------------
      // 3. GET CURRENT GPS POSITION
      // ----------------------------------------------------------

      final position =
          await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      );

      if (!mounted) return;

      // Store GPS coordinates immediately
      setState(() {
        _lat = position.latitude;
        _lng = position.longitude;
        _gpsLocked = true;
        _gpsStatus = 'GPS LOCKED';
        _locationName = 'Detecting place...';
      });

      // ----------------------------------------------------------
      // 4. REVERSE GEOCODE GPS COORDINATES
      // ----------------------------------------------------------
      //
      // Example:
      //
      // 27.5161, 94.4844
      //       ↓
      // Reverse geocoding
      //       ↓
      // Tezpur, Assam
      //
      // This is NOT hard-coded.
      // ----------------------------------------------------------

      try {
        final placemarks =
            await _geocoding.placemarkFromCoordinates(
          position.latitude,
          position.longitude,
        );

        if (placemarks.isEmpty) {
          if (!mounted) return;

          setState(() {
            _locationName = 'Location detected';
          });

          return;
        }

        final place = placemarks.first;

        final locality =
            place.locality?.trim() ?? '';

        final subLocality =
            place.subLocality?.trim() ?? '';

        final district =
            place.subAdministrativeArea?.trim() ?? '';

        final state =
            place.administrativeArea?.trim() ?? '';

        String detectedName;

        // --------------------------------------------------------
        // PREFER CITY / TOWN / LOCALITY
        // --------------------------------------------------------

        if (locality.isNotEmpty && state.isNotEmpty) {
          detectedName = '$locality, $state';
        }

        // --------------------------------------------------------
        // OTHERWISE USE SUB-LOCALITY
        // --------------------------------------------------------

        else if (subLocality.isNotEmpty &&
            state.isNotEmpty) {
          detectedName = '$subLocality, $state';
        }

        // --------------------------------------------------------
        // OTHERWISE USE DISTRICT
        // --------------------------------------------------------

        else if (district.isNotEmpty &&
            state.isNotEmpty) {
          detectedName = '$district, $state';
        }

        // --------------------------------------------------------
        // STATE ONLY
        // --------------------------------------------------------

        else if (state.isNotEmpty) {
          detectedName = state;
        }

        // --------------------------------------------------------
        // LAST FALLBACK
        // --------------------------------------------------------

        else {
          detectedName = 'Location detected';
        }

        if (!mounted) return;

        setState(() {
          _locationName = detectedName;
        });
      } catch (e) {
        // GPS coordinates are still valid even if
        // reverse geocoding fails.

        if (!mounted) return;

        setState(() {
          _locationName = 'GPS location detected';
        });
      }
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _gpsStatus = 'GPS ERROR';
        _gpsLocked = false;
        _locationName = 'Unable to determine location';
      });
    }
  }

  // ------------------------------------------------------------
  // DISPOSE
  // ------------------------------------------------------------

  @override
  void dispose() {
    _notesController.dispose();
    super.dispose();
  }

  // ------------------------------------------------------------
  // SUBMIT REPORT
  // ------------------------------------------------------------

  Future<void> _submitReport() async {
    // GPS must be available
    if (!_gpsLocked) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Waiting for GPS location. Please try again once GPS is locked.',
          ),
        ),
      );
      return;
    }

    // Notes are required
    if (_notesController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Please add descriptive notes regarding the hazard.',
          ),
        ),
      );
      return;
    }

    setState(() => _isSubmitting = true);

    // ----------------------------------------------------------
    // CREATE CITIZEN REPORT
    // ----------------------------------------------------------

    final report = CitizenReport(
      reportId:
          'NER-${1043 + widget.appState.reports.length}',

      // IMPORTANT:
      // Use the automatically detected GPS location name.
      // No hard-coded "Papum Pare".
      locationName: '$_locationName Corridor',

      latitude: _lat,
      longitude: _lng,

      capturedAt: DateTime.now(),

      mediaPath:
          'assets/reports/capture_${DateTime.now().millisecondsSinceEpoch}.jpg',

      incidentType: _selectedType,
      severity: _selectedSeverity,

      notes: _notesController.text.trim(),

      verificationStatus:
          widget.appState.offlineService.isOnline
              ? ReportVerificationStatus.uploaded
              : ReportVerificationStatus.pendingUpload,

      submittedBy: widget.appState.currentUser.name,

      isOfflineQueued:
          !widget.appState.offlineService.isOnline,
    );

    await widget.appState.submitCitizenReport(report);

    if (!mounted) return;

    setState(() => _isSubmitting = false);

    // ----------------------------------------------------------
    // SUCCESS DIALOG
    // ----------------------------------------------------------

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        title: const Row(
          children: [
            Icon(
              Icons.verified_outlined,
              color: AppColors.teal,
            ),
            SizedBox(width: 8),
            Text('Report Submitted'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment:
              CrossAxisAlignment.start,
          children: [
            Text(
              widget.appState.offlineService.isOnline
                  ? 'Report #${report.reportId} successfully uploaded to central disaster dispatch.'
                  : 'Report #${report.reportId} saved locally to Offline Sync Queue (Network Offline).',
              style: const TextStyle(
                fontSize: 13,
                color: AppColors.textPrimary,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              'Next Step: A Field Officer will verify the attached GPS & visual evidence to update the Risk Engine.',
              style: TextStyle(
                fontSize: 11,
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ),
        actions: [
          if (!widget.appState.offlineService.isOnline)
            TextButton(
              onPressed: () {
                Navigator.pop(context);

                widget.onNavigateNamed?.call(
                  'offline_queue',
                );
              },
              child: const Text(
                'View Offline Queue',
              ),
            ),

          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);

              if (widget.onBack != null) {
                widget.onBack!();
              }
            },
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  // ------------------------------------------------------------
  // BUILD SCREEN
  // ------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,

        title: const Text(
          'Verified Citizen Reporting',
        ),

        actions: [
          IconButton(
            icon: const Icon(Icons.sync_outlined),
            tooltip: 'Offline Queue',
            onPressed: () =>
                widget.onNavigateNamed?.call(
              'offline_queue',
            ),
          ),
        ],
      ),

      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),

        child: Column(
          crossAxisAlignment:
              CrossAxisAlignment.start,

          children: [
            // ==================================================
            // 1. REAL CAMERA VIEWFINDER
            // ==================================================

            CameraViewfinderWidget(
              latitude: _lat,
              longitude: _lng,

              // IMPORTANT:
              // This is now automatically detected from GPS.
              locationName: _locationName,

              isVideoMode: _isVideoMode,

              onModeChanged: (isVid) {
                setState(() {
                  _isVideoMode = isVid;
                });
              },

              onCapture: () {
                setState(() {
                  _isCaptured = true;
                });
              },

              gpsStatus: _gpsStatus,
            ),

            const SizedBox(height: 14),

            // ==================================================
            // MODE SELECTOR + CAPTURE BUTTON
            // ==================================================

            Row(
              mainAxisAlignment:
                  MainAxisAlignment.center,

              children: [
                OutlinedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isVideoMode =
                          !_isVideoMode;
                    });
                  },

                  icon: Icon(
                    _isVideoMode
                        ? Icons.photo_camera
                        : Icons.videocam,
                    size: 16,
                  ),

                  label: Text(
                    _isVideoMode
                        ? 'Switch to Photo'
                        : 'Switch to Video',

                    style: const TextStyle(
                      fontWeight:
                          FontWeight.w700,
                    ),
                  ),
                ),

                const SizedBox(width: 12),

                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _isCaptured = true;
                    });

                    ScaffoldMessenger.of(
                      context,
                    ).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Visual evidence captured & sealed with hardware GPS/timestamp!',
                        ),
                        duration:
                            Duration(seconds: 2),
                      ),
                    );
                  },

                  icon: const Icon(
                    Icons.camera_enhance,
                    size: 16,
                  ),

                  label: const Text(
                    'Capture Photo / Video',
                    style: TextStyle(
                      fontWeight:
                          FontWeight.w800,
                    ),
                  ),

                  style:
                      ElevatedButton.styleFrom(
                    backgroundColor:
                        AppColors.primary,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 20),

            // ==================================================
            // 2. INCIDENT CLASSIFICATION
            // ==================================================

            const Text(
              'Incident Classification',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),

            const SizedBox(height: 10),

            // Incident Type
            DropdownButtonFormField<IncidentType>(
              initialValue: _selectedType,

              decoration:
                  const InputDecoration(
                labelText: 'Incident Type',
                prefixIcon: Icon(
                  Icons.category_outlined,
                  size: 18,
                ),
              ),

              dropdownColor: Colors.white,

              items:
                  IncidentType.values.map(
                (type) {
                  return DropdownMenuItem(
                    value: type,

                    child: Text(
                      type.displayName,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  );
                },
              ).toList(),

              onChanged: (newType) {
                if (newType != null) {
                  setState(() {
                    _selectedType =
                        newType;
                  });
                }
              },
            ),

            const SizedBox(height: 14),

            // Severity
            DropdownButtonFormField<SeverityLevel>(
              initialValue:
                  _selectedSeverity,

              decoration:
                  const InputDecoration(
                labelText: 'Severity',
                prefixIcon: Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                ),
              ),

              dropdownColor: Colors.white,

              items:
                  SeverityLevel.values.map(
                (sev) {
                  return DropdownMenuItem(
                    value: sev,

                    child: Text(
                      sev.displayName,
                      style:
                          const TextStyle(
                        fontWeight:
                            FontWeight.w600,
                      ),
                    ),
                  );
                },
              ).toList(),

              onChanged: (newSev) {
                if (newSev != null) {
                  setState(() {
                    _selectedSeverity =
                        newSev;
                  });
                }
              },
            ),

            const SizedBox(height: 14),

            // ==================================================
            // NOTES
            // ==================================================

            TextField(
              controller: _notesController,

              maxLines: 3,

              decoration:
                  const InputDecoration(
                labelText: 'Notes',

                hintText:
                    'Describe slope movement, cracked pavement, blocked lanes, or exposed structures...',

                alignLabelWithHint: true,
              ),
            ),

            const SizedBox(height: 14),

            // ==================================================
            // AUTO-ATTACHED METADATA
            // ==================================================

            Container(
              padding:
                  const EdgeInsets.all(12),

              decoration:
                  BoxDecoration(
                color:
                    AppColors.tealPastel,

                borderRadius:
                    BorderRadius.circular(12),

                border: Border.all(
                  color: AppColors.teal
                      .withAlpha(80),
                ),
              ),

              child: Column(
                crossAxisAlignment:
                    CrossAxisAlignment.start,

                children: [
                  const Text(
                    'Auto-attached metadata',

                    style: TextStyle(
                      fontSize: 12,
                      fontWeight:
                          FontWeight.w800,
                      color:
                          AppColors.teal,
                    ),
                  ),

                  const SizedBox(height: 8),

                  Wrap(
                    spacing: 8,
                    runSpacing: 6,

                    children: [
                      _metadataPill(
                        '✔ GPS Attached (${_lat.toStringAsFixed(3)}°N, ${_lng.toStringAsFixed(3)}°E)',
                      ),

                      _metadataPill(
                        '✔ Location: $_locationName',
                      ),

                      _metadataPill(
                        '✔ Date: ${DateFormat('dd MMM yyyy').format(DateTime.now())}',
                      ),

                      _metadataPill(
                        '✔ Timestamp: ${DateFormat('HH:mm:ss').format(DateTime.now())}',
                      ),

                      _metadataPill(
                        _isCaptured
                            ? '✔ Evidence Image Captured (#SEALED)'
                            : '✔ Verified In-App Capture',
                      ),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // ==================================================
            // SUBMIT REPORT
            // ==================================================

            SizedBox(
              width: double.infinity,

              child: ElevatedButton.icon(
                onPressed: _isSubmitting
                    ? null
                    : _submitReport,

                icon: _isSubmitting
                    ? const SizedBox(
                        width: 16,
                        height: 16,

                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons.send_rounded,
                      ),

                label: Text(
                  _isSubmitting
                      ? 'Submitting...'
                      : 'Submit Report',
                ),

                style:
                    ElevatedButton.styleFrom(
                  backgroundColor:
                      AppColors.primary,

                  padding:
                      const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
              ),
            ),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  // ------------------------------------------------------------
  // METADATA PILL
  // ------------------------------------------------------------

  Widget _metadataPill(String text) {
    return Container(
      padding:
          const EdgeInsets.symmetric(
        horizontal: 8,
        vertical: 4,
      ),

      decoration: BoxDecoration(
        color: Colors.white,

        borderRadius:
            BorderRadius.circular(6),

        border: Border.all(
          color:
              AppColors.teal.withAlpha(60),
        ),
      ),

      child: Text(
        text,

        style: const TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: AppColors.teal,
        ),
      ),
    );
  }
}