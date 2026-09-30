import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/citizen_report.dart';
import '../../state/app_state.dart';
import '../../widgets/camera_viewfinder_widget.dart';

class FieldVerificationScreen extends StatefulWidget {
  final AppState appState;
  final VoidCallback? onBack;

  const FieldVerificationScreen({
    super.key,
    required this.appState,
    this.onBack,
  });

  @override
  State<FieldVerificationScreen> createState() => _FieldVerificationScreenState();
}

class _FieldVerificationScreenState extends State<FieldVerificationScreen> {
  final TextEditingController _verificationNotesController = TextEditingController();
  CitizenReport? _selectedReport;

  @override
  void initState() {
    super.initState();
    final pending = widget.appState.reports.where((r) => r.verificationStatus == ReportVerificationStatus.uploaded).toList();
    if (pending.isNotEmpty) {
      _selectedReport = pending.first;
    } else if (widget.appState.reports.isNotEmpty) {
      _selectedReport = widget.appState.reports.first;
    }
  }

  @override
  void dispose() {
    _verificationNotesController.dispose();
    super.dispose();
  }

  String _statusLabel(ReportVerificationStatus status) {
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

  Color _statusColor(ReportVerificationStatus status) {
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

  Future<void> _handleVerificationAction(ReportVerificationStatus status) async {
    if (_selectedReport == null) return;

    final notes = _verificationNotesController.text.trim();
    final actionLabel = _statusLabel(status);

    try {
      await widget.appState.verifyFieldReport(
        _selectedReport!.reportId,
        status,
        notes: notes.isNotEmpty ? notes : 'Ground check completed by Field Officer.',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              status == ReportVerificationStatus.verified
                  ? 'Report #${_selectedReport!.reportId.length > 8 ? _selectedReport!.reportId.substring(0, 8) : _selectedReport!.reportId} VERIFIED! Incident persisted to backend.'
                  : 'Report #${_selectedReport!.reportId.length > 8 ? _selectedReport!.reportId.substring(0, 8) : _selectedReport!.reportId} status updated to: $actionLabel',
            ),
            backgroundColor: _statusColor(status),
            duration: const Duration(seconds: 4),
          ),
        );
        _verificationNotesController.clear();
        setState(() {
          final pending = widget.appState.reports.where((r) => r.verificationStatus == ReportVerificationStatus.uploaded || r.verificationStatus == ReportVerificationStatus.pendingUpload).toList();
          _selectedReport = pending.isNotEmpty ? pending.first : (widget.appState.reports.isNotEmpty ? widget.appState.reports.first : null);
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Verification failed: $e'),
            backgroundColor: AppColors.riskHigh,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pendingReports = widget.appState.reports.where((r) => r.verificationStatus == ReportVerificationStatus.uploaded || r.verificationStatus == ReportVerificationStatus.pendingUpload).toList();
    final allReports = widget.appState.reports;

    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('Field Verification'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: 'Refresh Reports',
            onPressed: () => widget.appState.loadAllData(),
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Top feedback loop indicator banner in Pastel Teal
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: AppColors.tealPastel,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.teal.withAlpha(80)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.autorenew, color: AppColors.teal, size: 22),
                  SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Feedback Loop Active: Verifying an incident dynamically increases localized susceptibility factors and triggers automatic priority recalculations.',
                      style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary, height: 1.3),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),

            if (_selectedReport != null) ...[
              // Active Report Inspection Card matching wireframe
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceCard,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.border),
                  boxShadow: const [
                    BoxShadow(color: Color(0x08000000), blurRadius: 8, offset: Offset(0, 2)),
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
                            'Report #${_selectedReport!.reportId.length > 8 ? _selectedReport!.reportId.substring(0, 8) : _selectedReport!.reportId}',
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w900,
                              color: AppColors.primary,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: _statusColor(_selectedReport!.verificationStatus).withAlpha(25),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: _statusColor(_selectedReport!.verificationStatus).withAlpha(90)),
                          ),
                          child: Text(
                            _statusLabel(_selectedReport!.verificationStatus),
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w900,
                              color: _statusColor(_selectedReport!.verificationStatus),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'Type: ${_selectedReport!.incidentType.displayName} • Location: ${_selectedReport!.locationName}',
                      style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                    ),
                    Text(
                      'Severity: ${_selectedReport!.severity.displayName.toUpperCase()}',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w800, color: AppColors.riskHigh),
                    ),
                    const SizedBox(height: 12),

                    // Visual Evidence Camera Preview Frame / Real Media
                    if (_selectedReport!.mediaPath.isNotEmpty && !_selectedReport!.mediaPath.startsWith('assets/'))
                      Container(
                        height: 140,
                        width: double.infinity,
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              const Icon(Icons.perm_media, color: AppColors.teal, size: 28),
                              const SizedBox(height: 6),
                              Text(
                                'Attached Media: ${_selectedReport!.mediaPath.split('/').last}',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: AppColors.textPrimary),
                              ),
                            ],
                          ),
                        ),
                      )
                    else if (_selectedReport!.mediaPath.isEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: AppColors.surfaceElevated,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: AppColors.border),
                        ),
                        child: const Row(
                          children: [
                            Icon(Icons.image_not_supported_outlined, size: 16, color: AppColors.textSecondary),
                            SizedBox(width: 8),
                            Text(
                              'No media available',
                              style: TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                            ),
                          ],
                        ),
                      )
                    else
                      CameraViewfinderWidget(
                        latitude: _selectedReport!.latitude,
                        longitude: _selectedReport!.longitude,
                        locationName: _selectedReport!.locationName,
                      ),

                    if (_selectedReport!.validationResult != null) ...[
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(10),
                        margin: const EdgeInsets.only(bottom: 12),
                        decoration: BoxDecoration(
                          color: _selectedReport!.validationResult!['classification'] == 'RELEVANT_HAZARD'
                              ? AppColors.teal.withAlpha(20)
                              : AppColors.riskModerate.withAlpha(20),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: _selectedReport!.validationResult!['classification'] == 'RELEVANT_HAZARD'
                                ? AppColors.teal.withAlpha(70)
                                : AppColors.riskModerateBorder,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.psychology,
                              size: 18,
                              color: _selectedReport!.validationResult!['classification'] == 'RELEVANT_HAZARD'
                                  ? AppColors.teal
                                  : AppColors.riskModerate,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'AI Media Validation: ${_selectedReport!.validationResult!['classification'] ?? 'UNKNOWN'} (${(((_selectedReport!.validationResult!['confidence'] as num?)?.toDouble() ?? 0.0) * 100).toInt()}% confidence)',
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: AppColors.textPrimary),
                                  ),
                                  Text(
                                    'Status: ${_selectedReport!.validationResult!['validation_status'] ?? 'MANUAL_REVIEW_REQUIRED'} • Assistive only',
                                    style: const TextStyle(fontSize: 10, color: AppColors.textSecondary),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],

                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.surfaceElevated,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Citizen Description: "${_selectedReport!.notes.isNotEmpty ? _selectedReport!.notes : _selectedReport!.locationName}"',
                        style: const TextStyle(fontSize: 12, color: AppColors.textSecondary, fontStyle: FontStyle.italic),
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Field Officer Notes Input
                    TextField(
                      controller: _verificationNotesController,
                      maxLines: 2,
                      decoration: const InputDecoration(
                        labelText: 'Field Officer Assessment Notes',
                        hintText: 'Confirm soil displacement, road blockage extent, or heavy machinery requirement...',
                      ),
                    ),
                    const SizedBox(height: 14),

                    // Verification Action Buttons (`Verify`, `Reject`, `Needs Information`)
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _handleVerificationAction(ReportVerificationStatus.rejected),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.riskHigh,
                              side: const BorderSide(color: AppColors.riskHighBorder),
                            ),
                            child: const Text('Reject', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => _handleVerificationAction(ReportVerificationStatus.escalated),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.riskModerate,
                              side: const BorderSide(color: AppColors.riskModerateBorder),
                            ),
                            child: const Text('Needs Info', style: TextStyle(fontWeight: FontWeight.w700)),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: ElevatedButton(
                            onPressed: () => _handleVerificationAction(ReportVerificationStatus.verified),
                            style: ElevatedButton.styleFrom(backgroundColor: AppColors.teal),
                            child: const Text('Verify', style: TextStyle(fontWeight: FontWeight.w800)),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],

            // Assigned / Pending Reports Queue
            Text(
              'Pending Verification Queue (${pendingReports.length})',
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: AppColors.textPrimary),
            ),
            const SizedBox(height: 10),

            if (allReports.isEmpty)
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
                    'No reports available in the verification queue.',
                    style: TextStyle(fontSize: 12, color: AppColors.textSecondary),
                  ),
                ),
              )
            else
              ...allReports.map((r) {
                final isSelected = r.reportId == _selectedReport?.reportId;
                final statusColor = _statusColor(r.verificationStatus);
                final statusText = _statusLabel(r.verificationStatus);

                return GestureDetector(
                  onTap: () => setState(() => _selectedReport = r),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: isSelected ? AppColors.primaryPastel : AppColors.surfaceCard,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: isSelected ? AppColors.primary : AppColors.border,
                        width: isSelected ? 1.5 : 1.0,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          r.verificationStatus == ReportVerificationStatus.verified
                              ? Icons.verified
                              : (r.verificationStatus == ReportVerificationStatus.rejected
                                  ? Icons.cancel_outlined
                                  : Icons.pending_actions),
                          color: statusColor,
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '#${r.reportId.length > 8 ? r.reportId.substring(0, 8) : r.reportId} • ${r.incidentType.displayName}',
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                              ),
                              Text(
                                r.notes.isNotEmpty ? r.notes : r.locationName,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(fontSize: 11, color: AppColors.textSecondary),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          statusText,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                            color: statusColor,
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
