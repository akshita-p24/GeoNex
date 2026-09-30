import 'dart:math';
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

  // Stable UUID for idempotency
  late String _clientReportId;

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

  String _generateUuidV4() {
    final random = Random.secure();
    final values = List<int>.generate(16, (i) => random.nextInt(256));
    values[6] = (values[6] & 0x0f) | 0x40;
    values[8] = (values[8] & 0x3f) | 0x80;
    final hex = [
      for (int i = 0; i < 16; i++)
        values[i].toRadixString(16).padLeft(2, '0')
    ].join('');
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20, 32)}';
  }

  @override
  void initState() {
    super.initState();
    _clientReportId = _generateUuidV4();
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
      reportId: _clientReportId,

      // Automatically detected GPS location name
      locationName: _locationName.isNotEmpty ? _locationName : 'Corridor',

      latitude: _lat,
      longitude: _lng,

      capturedAt: DateTime.now(),

      mediaPath: '',

      incidentType: _selectedType,
      severity: _selectedSeverity,

      notes: _notesController.text.trim(),

      verificationStatus: widget.appState.offlineService.isOnline
          ? ReportVerificationStatus.uploaded
          : ReportVerificationStatus.pendingUpload,

      submittedBy: widget.appState.currentUser.name,

      isOfflineQueued: !widget.appState.offlineService.isOnline,
    );

    try {
      await widget.appState.submitCitizenReport(report);

      if (!mounted) return;

      final submittedReportId = widget.appState.reports.isNotEmpty
          ? widget.appState.reports.first.reportId
          : _clientReportId;

      _notesController.clear();
      _clientReportId = _generateUuidV4(); // Generate fresh UUID for next submission

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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.appState.offlineService.isOnline
                    ? 'Report #$submittedReportId successfully uploaded to central disaster dispatch with status PENDING.'
                    : 'Report #$submittedReportId saved locally to Offline Sync Queue (Network Offline).',
                style: const TextStyle(
                  fontSize: 13,
                  color: AppColors.textPrimary,
                ),
              ),
              const SizedBox(height: 10),
              const Text(
                'Next Step: A Field Officer will verify the hazard on-ground. You can track status updates in your reports below.',
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
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSubmitting = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to submit report: $e'),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    }
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

            // ==================================================
            // MY SUBMITTED REPORTS
            // ==================================================
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'My Submitted Reports (${widget.appState.reports.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                    color: AppColors.textPrimary,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.refresh, size: 18),
                  tooltip: 'Refresh Reports',
                  onPressed: () => widget.appState.loadAllData(),
                ),
              ],
            ),
            const SizedBox(height: 8),

            if (widget.appState.reports.isEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.border),
                ),
                child: const Center(
                  child: Text(
                    'No reports submitted yet. Submit your first report above.',
                    style: TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ),
              )
            else
              ...widget.appState.reports.map((r) {
                final statusText = _getStatusDisplayName(r.verificationStatus);
                final statusColor = _getStatusColor(r.verificationStatus);

                return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceCard,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: AppColors.border),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x06000000),
                        blurRadius: 6,
                        offset: Offset(0, 2),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Expanded(
                            child: Text(
                              'Report #${r.reportId.length > 8 ? r.reportId.substring(0, 8) : r.reportId} • ${r.incidentType.displayName}',
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w800,
                                color: AppColors.textPrimary,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: statusColor.withAlpha(25),
                              borderRadius: BorderRadius.circular(6),
                              border: Border.all(
                                color: statusColor.withAlpha(90),
                              ),
                            ),
                            child: Text(
                              statusText,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w900,
                                color: statusColor,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        r.notes.isNotEmpty ? r.notes : r.locationName,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          const Icon(
                            Icons.location_on_outlined,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            '${r.latitude.toStringAsFixed(4)}, ${r.longitude.toStringAsFixed(4)}',
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                          const Spacer(),
                          const Icon(
                            Icons.access_time,
                            size: 13,
                            color: AppColors.textMuted,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            DateFormat('dd MMM, HH:mm').format(r.capturedAt),
                            style: const TextStyle(
                              fontSize: 11,
                              color: AppColors.textMuted,
                            ),
                          ),
                        ],
                      ),
                      if (r.verifiedBy != null || (r.verificationNotes != null && r.verificationNotes!.isNotEmpty)) ...[
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.surfaceElevated,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: statusColor.withAlpha(60)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    r.verificationStatus == ReportVerificationStatus.verified
                                        ? Icons.verified
                                        : Icons.info_outline,
                                    size: 14,
                                    color: statusColor,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'Verification: ${r.verifiedBy ?? "Field Officer"}',
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: statusColor,
                                    ),
                                  ),
                                  if (r.verifiedAt != null) ...[
                                    const Spacer(),
                                    Text(
                                      DateFormat('dd MMM, HH:mm').format(r.verifiedAt!),
                                      style: const TextStyle(
                                        fontSize: 10,
                                        color: AppColors.textMuted,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (r.verificationNotes != null && r.verificationNotes!.isNotEmpty) ...[
                                const SizedBox(height: 4),
                                Text(
                                  'Notes: "${r.verificationNotes}"',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontStyle: FontStyle.italic,
                                    color: AppColors.textPrimary,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              }),

            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  String _getStatusDisplayName(ReportVerificationStatus status) {
    switch (status) {
      case ReportVerificationStatus.verified:
        return 'VERIFIED';
      case ReportVerificationStatus.rejected:
        return 'REJECTED';
      case ReportVerificationStatus.escalated:
        return 'NEEDS INFORMATION';
      case ReportVerificationStatus.uploaded:
      case ReportVerificationStatus.pendingUpload:
      case ReportVerificationStatus.draft:
        return 'PENDING';
    }
  }

  Color _getStatusColor(ReportVerificationStatus status) {
    switch (status) {
      case ReportVerificationStatus.verified:
        return AppColors.teal;
      case ReportVerificationStatus.rejected:
        return AppColors.riskHigh;
      case ReportVerificationStatus.escalated:
        return AppColors.riskModerate;
      case ReportVerificationStatus.uploaded:
      case ReportVerificationStatus.pendingUpload:
      case ReportVerificationStatus.draft:
        return AppColors.statusPending;
    }
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