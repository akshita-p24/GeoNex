import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../../core/constants/app_constants.dart';
import '../../core/models/citizen_report.dart';
import '../repositories/risk_repository.dart';

enum SyncStatus {
  idle,
  syncing,
  synced,
  offline,
  error,
}

class OfflineSyncService {
  final RiskRepository _repository;
  final List<CitizenReport> _offlineQueue = [];
  bool _isOnline = true;
  SyncStatus _syncStatus = SyncStatus.idle;

  final _statusController = StreamController<SyncStatus>.broadcast();
  final _queueController = StreamController<List<CitizenReport>>.broadcast();

  OfflineSyncService(this._repository) {
    _loadPersistedQueue();
  }

  bool get isOnline => _isOnline;
  SyncStatus get syncStatus => _syncStatus;
  List<CitizenReport> get offlineQueue => List.unmodifiable(_offlineQueue);
  Stream<SyncStatus> get statusStream => _statusController.stream;
  Stream<List<CitizenReport>> get queueStream => _queueController.stream;

  File _getStorageFile() {
    final tempDir = Directory.systemTemp;
    return File('${tempDir.path}/geonex_offline_reports.json');
  }

  Future<void> _loadPersistedQueue() async {
    try {
      final file = _getStorageFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        if (content.isNotEmpty) {
          final List<dynamic> jsonList = jsonDecode(content);
          _offlineQueue.clear();
          for (final item in jsonList) {
            _offlineQueue.add(
                CitizenReport.fromJson(item as Map<String, dynamic>));
          }
          _queueController.add(_offlineQueue);
        }
      }
    } catch (_) {}
  }

  Future<void> _savePersistedQueue() async {
    try {
      final file = _getStorageFile();
      final jsonList = _offlineQueue.map((r) => r.toJson()).toList();
      await file.writeAsString(jsonEncode(jsonList));
    } catch (_) {}
  }

  void setOnlineStatus(bool online) {
    _isOnline = online;
    if (!online) {
      _syncStatus = SyncStatus.offline;
    } else {
      _syncStatus = SyncStatus.idle;
      if (_offlineQueue.isNotEmpty) {
        syncAllPending();
      }
    }
    _statusController.add(_syncStatus);
  }

  Future<void> enqueueReport(CitizenReport report) async {
    final queuedReport = report.copyWith(
      isOfflineQueued: true,
      verificationStatus: ReportVerificationStatus.pendingUpload,
    );
    // Avoid duplicate queueing with same reportId
    final existingIdx =
        _offlineQueue.indexWhere((r) => r.reportId == report.reportId);
    if (existingIdx >= 0) {
      _offlineQueue[existingIdx] = queuedReport;
    } else {
      _offlineQueue.add(queuedReport);
    }
    await _savePersistedQueue();
    _queueController.add(_offlineQueue);

    if (_isOnline) {
      await syncAllPending();
    }
  }

  Future<int> syncAllPending() async {
    if (!_isOnline || _offlineQueue.isEmpty) return 0;

    _syncStatus = SyncStatus.syncing;
    _statusController.add(_syncStatus);

    final itemsToSync = List<CitizenReport>.from(_offlineQueue);
    int syncedCount = 0;
    bool hasError = false;

    for (final report in itemsToSync) {
      try {
        final toUpload = report.copyWith(
          isOfflineQueued: false,
          verificationStatus: ReportVerificationStatus.pendingUpload,
        );
        // Only remove from local queue after backend successfully accepts it
        await _repository.submitReport(toUpload);
        _offlineQueue.removeWhere((r) => r.reportId == report.reportId);
        await _savePersistedQueue();
        syncedCount++;
      } catch (e) {
        // Keep in offline queue on failure, do not remove
        hasError = true;
      }
    }

    _syncStatus = hasError
        ? (_offlineQueue.isEmpty ? SyncStatus.synced : SyncStatus.error)
        : SyncStatus.synced;
    _statusController.add(_syncStatus);
    _queueController.add(_offlineQueue);

    return syncedCount;
  }

  void dispose() {
    _statusController.close();
    _queueController.close();
  }
}

