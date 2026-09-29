import 'dart:async';
import 'dart:io';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:video_player/video_player.dart';

import '../core/constants/app_colors.dart';

enum HazardScenePreset {
  activeLandslide(
    'Active Landslide Scarp',
    Color(0xFF3B1D11),
    Color(0xFF78350F),
  ),
  roadCrack(
    'Pavement Tension Cracks',
    Color(0xFF1E293B),
    Color(0xFF475569),
  ),
  debrisFlow(
    'Debris & Mud Flow',
    Color(0xFF292524),
    Color(0xFF57534E),
  ),
  retainingWall(
    'Retaining Wall Shear',
    Color(0xFF1C1917),
    Color(0xFF44403C),
  ),
  liveOptical(
    'Live Mountain Corridor',
    Color(0xFF0F172A),
    Color(0xFF334155),
  );

  final String label;
  final Color primaryTone;
  final Color secondaryTone;

  const HazardScenePreset(
    this.label,
    this.primaryTone,
    this.secondaryTone,
  );
}

enum CameraFilterMode {
  normal('Standard RGB'),
  edgeDetection('Edge / Fracture High-Pass'),
  thermal('Thermal Relief IR'),
  topoRelief('DEM Topo Contour');

  final String label;

  const CameraFilterMode(this.label);
}

class CameraViewfinderWidget extends StatefulWidget {
  final double latitude;
  final double longitude;
  final String locationName;
  final bool isVideoMode;
  final String gpsStatus;
  final ValueChanged<bool>? onModeChanged;
  final VoidCallback? onCapture;
  final ValueChanged<String>? onImageCaptured;
  final String? capturedImagePath;

  const CameraViewfinderWidget({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.locationName,
    this.isVideoMode = false,
    this.gpsStatus = 'LOCATING...',
    this.onModeChanged,
    this.onCapture,
    this.onImageCaptured,
    this.capturedImagePath,
  });

  @override
  State<CameraViewfinderWidget> createState() =>
      _CameraViewfinderWidgetState();
}

class _CameraViewfinderWidgetState extends State<CameraViewfinderWidget>
    with TickerProviderStateMixin {
  late AnimationController _pulseController;
  late AnimationController _shutterFlashController;
  late AnimationController _focusRingController;

  CameraController? _cameraController;

  // ============================================================
  // CAMERA STATE
  // ============================================================

  double _zoomLevel = 1.0;
  double _minZoom = 1.0;
  double _maxZoom = 5.0;

  String _flashMode = 'Auto';

  HazardScenePreset _activeScene = HazardScenePreset.activeLandslide;
  CameraFilterMode _activeFilter = CameraFilterMode.normal;

  Offset? _focusPoint;

  bool _cameraReady = false;
  bool _cameraError = false;
  bool _isCaptured = false;

  String? _cameraErrorMessage;

  // ============================================================
  // PHOTO STATE
  // ============================================================

  String? _capturedImagePath;

  // ============================================================
  // VIDEO STATE
  // ============================================================

  VideoPlayerController? _videoPlayerController;

  bool _isVideoInitialized = false;
  bool _isRecording = false;

  Duration _recordingDuration = Duration.zero;
  Timer? _recordingTimer;

  String? _capturedVideoPath;

  // ============================================================
  // EVIDENCE STATE
  // ============================================================

  String? _capturedTimestamp;
  int _evidenceHash = 0;

  // ============================================================
  // INIT
  // ============================================================

  @override
  void initState() {
    super.initState();

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _shutterFlashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 250),
    );

    _focusRingController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 600),
    );

    _initializeCamera();
  }

  // ============================================================
  // CAMERA INITIALIZATION
  // ============================================================

  Future<void> _initializeCamera() async {
    try {
      final cameras = await availableCameras();

      if (cameras.isEmpty) {
        throw CameraException(
          'NoCamera',
          'No camera was found on this device.',
        );
      }

      CameraDescription selectedCamera = cameras.first;

      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.back) {
          selectedCamera = camera;
          break;
        }
      }

      final controller = CameraController(
        selectedCamera,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await controller.initialize();

      try {
        _minZoom = await controller.getMinZoomLevel();
        _maxZoom = await controller.getMaxZoomLevel();

        if (_maxZoom < _minZoom) {
          _maxZoom = _minZoom;
        }
      } catch (_) {
        _minZoom = 1.0;
        _maxZoom = 5.0;
      }

      try {
        await controller.setFlashMode(FlashMode.auto);
      } catch (_) {}

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _cameraController = controller;
        _cameraReady = true;
        _cameraError = false;
        _cameraErrorMessage = null;
      });
    } on CameraException catch (e) {
      if (!mounted) return;

      setState(() {
        _cameraError = true;
        _cameraReady = false;
        _cameraErrorMessage = _cameraExceptionMessage(e);
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _cameraError = true;
        _cameraReady = false;
        _cameraErrorMessage = 'Unable to initialize camera: $e';
      });
    }
  }

  // ============================================================
  // CAMERA ERROR
  // ============================================================

  String _cameraExceptionMessage(CameraException e) {
    switch (e.code) {
      case 'CameraAccessDenied':
        return 'Camera permission was denied. Please allow camera access in Android settings.';

      case 'CameraAccessDeniedWithoutPrompt':
        return 'Camera permission is disabled. Enable camera permission in Android settings.';

      case 'CameraAccessRestricted':
        return 'Camera access is restricted on this device.';

      case 'CameraAccessLimited':
        return 'Camera access is limited on this device.';

      case 'CameraAccessDeniedBySystem':
        return 'Camera access was denied by the system.';

      case 'AudioAccessDenied':
        return 'Audio permission was denied. Audio is not required.';

      default:
        return e.description ?? 'Unable to access the camera.';
    }
  }

  // ============================================================
  // DISPOSE
  // ============================================================

  @override
  void dispose() {
    _recordingTimer?.cancel();

    _videoPlayerController?.dispose();
    _cameraController?.dispose();

    _pulseController.dispose();
    _shutterFlashController.dispose();
    _focusRingController.dispose();

    super.dispose();
  }

  // ============================================================
  // MAIN CAPTURE HANDLER
  // ============================================================

  Future<void> _triggerCapture() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isCaptured) {
      return;
    }

    // VIDEO MODE
    if (widget.isVideoMode) {
      if (_isRecording) {
        await _stopVideoRecording();
      } else {
        await _startVideoRecording();
      }

      return;
    }

    // PHOTO MODE
    await _capturePhoto();
  }

  // ============================================================
  // PHOTO CAPTURE
  // ============================================================

  Future<void> _capturePhoto() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        controller.value.isTakingPicture ||
        _isCaptured ||
        _isRecording) {
      return;
    }

    try {
      _shutterFlashController.forward(from: 0.0);

      final XFile image = await controller.takePicture();

      final timestamp = DateTime.now();

      if (!mounted) return;

      setState(() {
        _isCaptured = true;
        _capturedImagePath = image.path;
        _capturedVideoPath = null;
        _capturedTimestamp =
            DateFormat('dd MMM yyyy • HH:mm:ss').format(timestamp);
        _evidenceHash = timestamp.millisecondsSinceEpoch.hashCode;
      });

      widget.onCapture?.call();
      widget.onImageCaptured?.call(image.path);

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.verified,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evidence photo captured: ${widget.locationName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.teal,
          duration: const Duration(seconds: 2),
        ),
      );
    } on CameraException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(_cameraExceptionMessage(e)),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to capture image: $e'),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    }
  }

  // ============================================================
  // START VIDEO RECORDING
  // ============================================================

  Future<void> _startVideoRecording() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isRecording ||
        _isCaptured) {
      return;
    }

    try {
      await controller.startVideoRecording();

      if (!mounted) return;

      setState(() {
        _isRecording = true;
        _recordingDuration = Duration.zero;
      });

      _recordingTimer?.cancel();

      _recordingTimer = Timer.periodic(
        const Duration(seconds: 1),
        (_) {
          if (!mounted || !_isRecording) return;

          setState(() {
            _recordingDuration += const Duration(seconds: 1);
          });
        },
      );

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Row(
            children: [
              Icon(
                Icons.fiber_manual_record,
                color: Colors.red,
                size: 18,
              ),
              SizedBox(width: 8),
              Text(
                'Video recording started',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
          duration: Duration(seconds: 1),
        ),
      );
    } on CameraException catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to start video: ${_cameraExceptionMessage(e)}',
          ),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to start video: $e'),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    }
  }

  // ============================================================
  // STOP VIDEO RECORDING
  // ============================================================

  Future<void> _stopVideoRecording() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        !_isRecording) {
      return;
    }

    try {
      final XFile video = await controller.stopVideoRecording();

      _recordingTimer?.cancel();

      final timestamp = DateTime.now();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
        _isCaptured = true;

        _capturedVideoPath = video.path;
        _capturedImagePath = null;

        _capturedTimestamp =
            DateFormat('dd MMM yyyy • HH:mm:ss').format(timestamp);

        _evidenceHash = timestamp.millisecondsSinceEpoch.hashCode;
      });

      // IMPORTANT:
      // Initialize the actual recorded video for playback.
      await _initializeVideoPlayer(video.path);

      if (!mounted) return;

      widget.onCapture?.call();

      widget.onImageCaptured?.call(video.path);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(
                Icons.verified,
                color: Colors.white,
                size: 18,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Evidence video captured: ${widget.locationName}',
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
          backgroundColor: AppColors.teal,
          duration: const Duration(seconds: 2),
        ),
      );
    } on CameraException catch (e) {
      _recordingTimer?.cancel();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Unable to stop video: ${_cameraExceptionMessage(e)}',
          ),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    } catch (e) {
      _recordingTimer?.cancel();

      if (!mounted) return;

      setState(() {
        _isRecording = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to save video: $e'),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    }
  }

  // ============================================================
  // VIDEO PLAYER INITIALIZATION
  // ============================================================

  Future<void> _initializeVideoPlayer(String videoPath) async {
    try {
      await _videoPlayerController?.dispose();

      final controller = VideoPlayerController.file(
        File(videoPath),
      );

      await controller.initialize();

      if (!mounted) {
        await controller.dispose();
        return;
      }

      setState(() {
        _videoPlayerController = controller;
        _isVideoInitialized = true;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _videoPlayerController = null;
        _isVideoInitialized = false;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to preview recorded video: $e'),
          backgroundColor: AppColors.riskHigh,
        ),
      );
    }
  }

  // ============================================================
  // VIDEO PLAY / PAUSE
  // ============================================================

  void _toggleVideoPlayback() {
    final controller = _videoPlayerController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
      } else {
        controller.play();
      }
    });
  }

  // ============================================================
  // VIDEO PREVIEW
  // ============================================================

  Widget _buildVideoPreview() {
    final controller = _videoPlayerController;

    if (controller == null ||
        !_isVideoInitialized ||
        !controller.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(
              color: AppColors.teal,
            ),
            SizedBox(height: 12),
            Text(
              'Preparing video preview...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    final aspectRatio = controller.value.aspectRatio > 0
        ? controller.value.aspectRatio
        : 16 / 9;

    return Container(
      color: Colors.black,
      child: Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: Stack(
            fit: StackFit.expand,
            children: [
              VideoPlayer(controller),

              // PLAY / PAUSE BUTTON
              Center(
                child: GestureDetector(
                  onTap: _toggleVideoPlayback,
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 58,
                    height: 58,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: AppColors.teal,
                        width: 1.5,
                      ),
                    ),
                    child: Icon(
                      controller.value.isPlaying
                          ? Icons.pause
                          : Icons.play_arrow,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                ),
              ),

              // VIDEO DURATION
              Positioned(
                top: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.75),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    _formatVideoDuration(
                      controller.value.position,
                    ),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ),

              // VIDEO PROGRESS BAR
              Positioned(
                left: 10,
                right: 10,
                bottom: 8,
                child: VideoProgressIndicator(
                  controller,
                  allowScrubbing: true,
                  padding: const EdgeInsets.symmetric(
                    vertical: 4,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // VIDEO TIME FORMAT
  // ============================================================

  String _formatVideoDuration(Duration duration) {
    final minutes =
        duration.inMinutes.remainder(60).toString().padLeft(2, '0');

    final seconds =
        duration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  // ============================================================
  // RECORDING TIME FORMAT
  // ============================================================

  String _formatRecordingDuration() {
    final minutes =
        _recordingDuration.inMinutes.remainder(60).toString().padLeft(2, '0');

    final seconds =
        _recordingDuration.inSeconds.remainder(60).toString().padLeft(2, '0');

    return '$minutes:$seconds';
  }

  // ============================================================
  // FOCUS
  // ============================================================

  Future<void> _handleTapToFocus(
    TapDownDetails details,
  ) async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isCaptured ||
        _isRecording) {
      return;
    }

    setState(() {
      _focusPoint = details.localPosition;
    });

    _focusRingController.forward(from: 0.0);

    final renderBox = context.findRenderObject();

    if (renderBox is RenderBox) {
      final size = renderBox.size;

      final dx =
          (details.localPosition.dx / size.width).clamp(0.0, 1.0);

      final dy =
          (details.localPosition.dy / size.height).clamp(0.0, 1.0);

      try {
        await controller.setFocusPoint(
          Offset(dx, dy),
        );
      } catch (_) {}
    }
  }

  // ============================================================
  // RETAKE
  // ============================================================

  Future<void> _retakePhoto() async {
    _recordingTimer?.cancel();

    await _videoPlayerController?.dispose();

    if (!mounted) return;

    setState(() {
      _videoPlayerController = null;
      _isVideoInitialized = false;

      _isCaptured = false;
      _isRecording = false;

      _recordingDuration = Duration.zero;

      _capturedImagePath = null;
      _capturedVideoPath = null;

      _capturedTimestamp = null;
      _evidenceHash = 0;
    });
  }

  // ============================================================
  // FLASH
  // ============================================================

  Future<void> _toggleFlash() async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized) {
      return;
    }

    String nextMode;

    if (_flashMode == 'Auto') {
      nextMode = 'On';
    } else if (_flashMode == 'On') {
      nextMode = 'Off';
    } else {
      nextMode = 'Auto';
    }

    try {
      final flashMode = switch (nextMode) {
        'On' => FlashMode.always,
        'Off' => FlashMode.off,
        _ => FlashMode.auto,
      };

      await controller.setFlashMode(flashMode);

      if (!mounted) return;

      setState(() {
        _flashMode = nextMode;
      });
    } catch (_) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Flash control is not available on this camera.',
          ),
        ),
      );
    }
  }

  // ============================================================
  // ZOOM
  // ============================================================

  Future<void> _setZoom(double requestedZoom) async {
    final controller = _cameraController;

    if (controller == null ||
        !controller.value.isInitialized ||
        _isCaptured ||
        _isRecording) {
      return;
    }

    final zoom =
        requestedZoom.clamp(_minZoom, _maxZoom);

    try {
      await controller.setZoomLevel(zoom);

      if (!mounted) return;

      setState(() {
        _zoomLevel = zoom;
      });
    } catch (_) {}
  }

  // ============================================================
  // CAMERA CONTENT
  // ============================================================

  Widget _buildCameraContent() {
    // CAMERA ERROR
    if (_cameraError) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.no_photography_outlined,
              color: Colors.white70,
              size: 44,
            ),
            const SizedBox(height: 12),
            const Text(
              'Camera unavailable',
              style: TextStyle(
                color: Colors.white,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _cameraErrorMessage ??
                  'Unable to access the camera.',
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                setState(() {
                  _cameraError = false;
                  _cameraReady = false;
                  _cameraErrorMessage = null;
                });

                _initializeCamera();
              },
              icon: const Icon(Icons.refresh),
              label: const Text('Retry camera'),
            ),
          ],
        ),
      );
    }

    // CAMERA STARTING
    if (!_cameraReady ||
        _cameraController == null ||
        !_cameraController!.value.isInitialized) {
      return Container(
        color: Colors.black,
        alignment: Alignment.center,
        child: const Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 12),
            Text(
              'Starting camera...',
              style: TextStyle(
                color: Colors.white70,
                fontSize: 12,
              ),
            ),
          ],
        ),
      );
    }

    // ==========================================================
    // CAPTURED VIDEO
    // ==========================================================

    if (_isCaptured &&
        _capturedVideoPath != null) {
      return _buildVideoPreview();
    }

    // ==========================================================
    // CAPTURED PHOTO
    // ==========================================================

    if (_isCaptured &&
        _capturedImagePath != null) {
      return Image.file(
        File(_capturedImagePath!),
        width: double.infinity,
        height: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (
          context,
          error,
          stackTrace,
        ) {
          return const Center(
            child: Text(
              'Captured image could not be displayed.',
              style: TextStyle(
                color: Colors.white,
              ),
            ),
          );
        },
      );
    }

    // ==========================================================
    // LIVE CAMERA
    // ==========================================================

    return CameraPreview(
      _cameraController!,
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(BuildContext context) {
    final timeStr = _isCaptured
        ? (_capturedTimestamp ??
            DateFormat(
              'dd MMM yyyy • HH:mm:ss',
            ).format(DateTime.now()))
        : DateFormat(
            'dd MMM yyyy • HH:mm:ss',
          ).format(DateTime.now());

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF070B10),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: _isCaptured
              ? AppColors.teal
              : (_isRecording
                  ? AppColors.riskHigh
                  : AppColors.border),
          width: _isCaptured || _isRecording ? 2 : 1,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18000000),
            blurRadius: 10,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Column(
          children: [
            // ====================================================
            // TOP CAMERA BAR
            // ====================================================

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              color: Colors.black.withValues(alpha: 0.85),
              child: Row(
                children: [
                  // FLASH
                  InkWell(
                    onTap:
                        _isRecording ? null : _toggleFlash,
                    borderRadius: BorderRadius.circular(6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: _flashMode == 'On'
                            ? AppColors.primaryPastel
                            : Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _flashMode == 'Off'
                                ? Icons.flash_off
                                : (_flashMode == 'On'
                                    ? Icons.flash_on
                                    : Icons.flash_auto),
                            size: 14,
                            color: _flashMode == 'On'
                                ? AppColors.primary
                                : Colors.white70,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            _flashMode,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              color: _flashMode == 'On'
                                  ? AppColors.primary
                                  : Colors.white70,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // SCENE
                  Expanded(
                    child: Container(
                      height: 28,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white10,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: DropdownButtonHideUnderline(
                        child:
                            DropdownButton<HazardScenePreset>(
                          value: _activeScene,
                          dropdownColor:
                              const Color(0xFF1E293B),
                          isExpanded: true,
                          icon: const Icon(
                            Icons.arrow_drop_down,
                            color: Colors.white70,
                            size: 16,
                          ),
                          style: const TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                          items:
                              HazardScenePreset.values.map((s) {
                            return DropdownMenuItem(
                              value: s,
                              child: Text(
                                s.label,
                                overflow:
                                    TextOverflow.ellipsis,
                              ),
                            );
                          }).toList(),
                          onChanged:
                              _isCaptured || _isRecording
                                  ? null
                                  : (newScene) {
                                      if (newScene != null) {
                                        setState(() {
                                          _activeScene =
                                              newScene;
                                        });
                                      }
                                    },
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(width: 8),

                  // FILTER
                  Container(
                    height: 28,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                    ),
                    decoration: BoxDecoration(
                      color:
                          _activeFilter !=
                                  CameraFilterMode.normal
                              ? AppColors.tealPastel
                              : Colors.white10,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: DropdownButtonHideUnderline(
                      child:
                          DropdownButton<CameraFilterMode>(
                        value: _activeFilter,
                        dropdownColor:
                            const Color(0xFF1E293B),
                        icon: Icon(
                          Icons.filter_b_and_w,
                          color: _activeFilter !=
                                  CameraFilterMode.normal
                              ? AppColors.teal
                              : Colors.white70,
                          size: 14,
                        ),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                          color: _activeFilter !=
                                  CameraFilterMode.normal
                              ? AppColors.teal
                              : Colors.white,
                        ),
                        items:
                            CameraFilterMode.values.map((f) {
                          return DropdownMenuItem(
                            value: f,
                            child: Text(f.label),
                          );
                        }).toList(),
                        onChanged:
                            _isCaptured || _isRecording
                                ? null
                                : (newFilter) {
                                    if (newFilter != null) {
                                      setState(() {
                                        _activeFilter =
                                            newFilter;
                                      });
                                    }
                                  },
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // ====================================================
            // CAMERA VIEW
            // ====================================================

            GestureDetector(
              onTapDown: _handleTapToFocus,
              child: SizedBox(
                height: 240,
                width: double.infinity,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    _buildCameraContent(),

                    // SCAN LINE
                    if (!_isCaptured &&
                        _cameraReady &&
                        !_isRecording)
                      AnimatedBuilder(
                        animation: _pulseController,
                        builder: (context, child) {
                          return Positioned(
                            top:
                                240 *
                                _pulseController.value,
                            left: 0,
                            right: 0,
                            child: Container(
                              height: 1.5,
                              color:
                                  AppColors.teal.withValues(
                                alpha: 0.4,
                              ),
                            ),
                          );
                        },
                      ),

                    // VIEWFINDER
                    Positioned.fill(
                      child: CustomPaint(
                        painter: _ViewfinderOverlayPainter(
                          accentColor: _isRecording
                              ? AppColors.riskHigh
                              : (widget.isVideoMode
                                  ? AppColors.riskHigh
                                  : AppColors.accent),
                        ),
                      ),
                    ),

                    // RECORDING INDICATOR
                    if (_isRecording)
                      Positioned(
                        top: 45,
                        left: 0,
                        right: 0,
                        child: Center(
                          child: Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black
                                  .withValues(alpha: 0.85),
                              borderRadius:
                                  BorderRadius.circular(20),
                              border: Border.all(
                                color:
                                    AppColors.riskHigh,
                              ),
                            ),
                            child: Row(
                              mainAxisSize:
                                  MainAxisSize.min,
                              children: [
                                Container(
                                  width: 9,
                                  height: 9,
                                  decoration:
                                      const BoxDecoration(
                                    color: Colors.red,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 7),
                                const Text(
                                  'RECORDING',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w900,
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  _formatRecordingDuration(),
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),

                    // FOCUS RING
                    if (_focusPoint != null &&
                        !_isCaptured &&
                        !_isRecording)
                      AnimatedBuilder(
                        animation: _focusRingController,
                        builder: (context, child) {
                          final scale =
                              1.5 -
                              (0.5 *
                                  _focusRingController.value);

                          final opacity =
                              1.0 -
                              (0.5 *
                                  _focusRingController.value);

                          return Positioned(
                            left: _focusPoint!.dx - 22,
                            top: _focusPoint!.dy - 22,
                            child: Transform.scale(
                              scale: scale,
                              child: Opacity(
                                opacity: opacity,
                                child: Container(
                                  width: 44,
                                  height: 44,
                                  decoration:
                                      BoxDecoration(
                                    border: Border.all(
                                      color:
                                          AppColors.accent,
                                      width: 1.8,
                                    ),
                                    borderRadius:
                                        BorderRadius.circular(
                                      6,
                                    ),
                                  ),
                                  child: const Center(
                                    child: Icon(
                                      Icons.gps_fixed,
                                      size: 14,
                                      color:
                                          AppColors.accent,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    // ==================================================
                    // TOP STATUS
                    // ==================================================

                    Positioned(
                      top: 10,
                      left: 10,
                      right: 10,
                      child: Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black
                                  .withValues(alpha: 0.75),
                              borderRadius:
                                  BorderRadius.circular(6),
                              border: Border.all(
                                color: _isRecording
                                    ? AppColors.riskHigh
                                    : (_isCaptured
                                        ? AppColors.teal
                                        : AppColors.teal
                                            .withValues(
                                            alpha: 0.5,
                                          )),
                              ),
                            ),
                            child: Row(
                              mainAxisSize:
                                  MainAxisSize.min,
                              children: [
                                Container(
                                  width: 7,
                                  height: 7,
                                  decoration:
                                      BoxDecoration(
                                    color: _isRecording
                                        ? Colors.red
                                        : AppColors.teal,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 5),
                                Text(
                                  _isRecording
                                      ? 'RECORDING VIDEO'
                                      : (_isCaptured
                                          ? 'SEALED EVIDENCE'
                                          : (_cameraReady
                                              ? (widget.isVideoMode
                                                  ? 'LIVE VIDEO CAMERA'
                                                  : 'LIVE CAMERA')
                                              : 'STARTING CAMERA')),
                                  style: TextStyle(
                                    color: _isRecording
                                        ? Colors.white
                                        : (_isCaptured
                                            ? AppColors.teal
                                            : Colors.white),
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w800,
                                    letterSpacing: 0.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 3,
                            ),
                            decoration: BoxDecoration(
                              color: Colors.black
                                  .withValues(alpha: 0.75),
                              borderRadius:
                                  BorderRadius.circular(6),
                            ),
                            child: Text(
                              _isRecording
                                  ? _formatRecordingDuration()
                                  : (_isCaptured
                                      ? 'HASH #${_evidenceHash.toRadixString(16).toUpperCase()}'
                                      : '${_zoomLevel.toStringAsFixed(1)}x ZOOM'),
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 10,
                                fontWeight:
                                    FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    // SHUTTER FLASH
                    if (!_isRecording && !_isCaptured)
                      AnimatedBuilder(
                        animation:
                            _shutterFlashController,
                        builder: (context, child) {
                          return Positioned.fill(
                            child: IgnorePointer(
                              child: Container(
                                color: Colors.white.withValues(
                                  alpha:
                                      1.0 -
                                      _shutterFlashController
                                          .value,
                                ),
                              ),
                            ),
                          );
                        },
                      ),

                    // ==================================================
                    // GPS / TIMESTAMP
                    // ==================================================

                    Positioned(
                      bottom: 8,
                      left: 8,
                      right: 8,
                      child: Container(
                        padding:
                            const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black
                              .withValues(alpha: 0.85),
                          borderRadius:
                              BorderRadius.circular(8),
                          border: Border.all(
                            color: _isCaptured
                                ? AppColors.teal.withValues(
                                    alpha: 0.8,
                                  )
                                : Colors.white12,
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment:
                              CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                const Icon(
                                  Icons.my_location,
                                  size: 12,
                                  color: AppColors.accent,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  'GPS: ${widget.latitude.toStringAsFixed(4)}°N, ${widget.longitude.toStringAsFixed(4)}°E',
                                  style: const TextStyle(
                                    color:
                                        AppColors.accent,
                                    fontSize: 10,
                                    fontWeight:
                                        FontWeight.w700,
                                  ),
                                ),
                                const Spacer(),
                                const Icon(
                                  Icons.verified,
                                  size: 13,
                                  color: AppColors.teal,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _isRecording
                                      ? 'RECORDING'
                                      : (_isCaptured
                                          ? 'HARDWARE SEALED'
                                          : widget.gpsStatus),
                                  style: TextStyle(
                                    color: _isRecording
                                        ? AppColors.riskHigh
                                        : (_isCaptured
                                            ? AppColors.teal
                                            : (widget.gpsStatus ==
                                                    'GPS LOCKED'
                                                ? AppColors.teal
                                                : Colors.orange)),
                                    fontSize: 9,
                                    fontWeight:
                                        FontWeight.w800,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                const Icon(
                                  Icons.access_time,
                                  size: 11,
                                  color:
                                      AppColors.textSecondary,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  timeStr,
                                  style: const TextStyle(
                                    color:
                                        AppColors.textSecondary,
                                    fontSize: 9,
                                    fontWeight:
                                        FontWeight.w500,
                                  ),
                                ),
                                const Spacer(),
                                Text(
                                  widget.locationName,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 9,
                                    fontWeight:
                                        FontWeight.w600,
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
              ),
            ),

            // ============================================================
            // BOTTOM CONTROLS
            // ============================================================

            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              color: Colors.black.withValues(alpha: 0.9),
              child: Row(
                mainAxisAlignment:
                    MainAxisAlignment.spaceBetween,
                children: [
                  // ZOOM BUTTONS
                  Row(
                    children: [0.5, 1.0, 2.0, 5.0]
                        .map((z) {
                      final isSelected =
                          (_zoomLevel - z).abs() < 0.1;

                      return Padding(
                        padding:
                            const EdgeInsets.only(right: 4),
                        child: InkWell(
                          onTap:
                              _isCaptured || _isRecording
                                  ? null
                                  : () => _setZoom(z),
                          borderRadius:
                              BorderRadius.circular(14),
                          child: Container(
                            width: 28,
                            height: 28,
                            alignment:
                                Alignment.center,
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? AppColors.primary
                                  : Colors.white10,
                              shape: BoxShape.circle,
                            ),
                            child: Text(
                              '${z == 0.5 ? ".5" : z.toInt()}x',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight:
                                    FontWeight.w800,
                                color: isSelected
                                    ? Colors.white
                                    : Colors.white70,
                              ),
                            ),
                          ),
                        ),
                      );
                    }).toList(),
                  ),

                  // ======================================================
                  // CAPTURED STATE
                  // ======================================================

                  if (_isCaptured)
                    Row(
                      children: [
                        OutlinedButton.icon(
                          onPressed: _retakePhoto,
                          icon: const Icon(
                            Icons.replay,
                            size: 13,
                            color: Colors.white70,
                          ),
                          label: const Text(
                            'Retake',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.white70,
                              fontWeight:
                                  FontWeight.w700,
                            ),
                          ),
                          style:
                              OutlinedButton.styleFrom(
                            side: const BorderSide(
                              color: Colors.white24,
                            ),
                            padding:
                                const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding:
                              const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 6,
                          ),
                          decoration: BoxDecoration(
                            color: AppColors.tealPastel,
                            borderRadius:
                                BorderRadius.circular(8),
                            border: Border.all(
                              color: AppColors.teal,
                            ),
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _capturedVideoPath != null
                                    ? Icons.videocam
                                    : Icons.check,
                                size: 14,
                                color: AppColors.teal,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _capturedVideoPath != null
                                    ? 'Video Captured'
                                    : 'Captured',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight:
                                      FontWeight.w800,
                                  color: AppColors.teal,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    )

                  // ======================================================
                  // RECORD / PHOTO BUTTON
                  // ======================================================

                  else
                    InkWell(
                      onTap: _cameraReady
                          ? _triggerCapture
                          : null,
                      borderRadius:
                          BorderRadius.circular(30),
                      child: AnimatedContainer(
                        duration:
                            const Duration(milliseconds: 150),
                        width: 52,
                        height: 52,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _cameraReady
                                ? (_isRecording
                                    ? Colors.red
                                    : Colors.white)
                                : Colors.white30,
                            width: 2.5,
                          ),
                          color: Colors.transparent,
                        ),
                        child: Center(
                          child: AnimatedContainer(
                            duration:
                                const Duration(milliseconds: 150),
                            width:
                                _isRecording ? 22 : 34,
                            height:
                                _isRecording ? 22 : 34,
                            decoration: BoxDecoration(
                              shape: _isRecording
                                  ? BoxShape.rectangle
                                  : BoxShape.circle,
                              borderRadius: _isRecording
                                  ? BorderRadius.circular(4)
                                  : null,
                              color: _cameraReady
                                  ? (widget.isVideoMode
                                      ? (_isRecording
                                          ? Colors.red
                                          : AppColors.riskHigh)
                                      : Colors.white)
                                  : Colors.white24,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// VIEWFINDER PAINTER
// ================================================================

class _ViewfinderOverlayPainter extends CustomPainter {
  final Color accentColor;

  _ViewfinderOverlayPainter({
    required this.accentColor,
  });

  @override
  void paint(
    Canvas canvas,
    Size size,
  ) {
    final bracketPaint = Paint()
      ..color = accentColor.withValues(alpha: 0.85)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    const double bSize = 18.0;
    const double pad = 16.0;

    // TOP LEFT
    canvas.drawLine(
      const Offset(
        pad,
        pad + bSize,
      ),
      const Offset(
        pad,
        pad,
      ),
      bracketPaint,
    );

    canvas.drawLine(
      const Offset(
        pad,
        pad,
      ),
      const Offset(
        pad + bSize,
        pad,
      ),
      bracketPaint,
    );

    // TOP RIGHT
    canvas.drawLine(
      Offset(
        size.width - pad - bSize,
        pad,
      ),
      Offset(
        size.width - pad,
        pad,
      ),
      bracketPaint,
    );

    canvas.drawLine(
      Offset(
        size.width - pad,
        pad,
      ),
      Offset(
        size.width - pad,
        pad + bSize,
      ),
      bracketPaint,
    );

    // BOTTOM LEFT
    canvas.drawLine(
      Offset(
        pad,
        size.height - pad - bSize,
      ),
      Offset(
        pad,
        size.height - pad,
      ),
      bracketPaint,
    );

    canvas.drawLine(
      Offset(
        pad,
        size.height - pad,
      ),
      Offset(
        pad + bSize,
        size.height - pad,
      ),
      bracketPaint,
    );

    // BOTTOM RIGHT
    canvas.drawLine(
      Offset(
        size.width - pad - bSize,
        size.height - pad,
      ),
      Offset(
        size.width - pad,
        size.height - pad,
      ),
      bracketPaint,
    );

    canvas.drawLine(
      Offset(
        size.width - pad,
        size.height - pad,
      ),
      Offset(
        size.width - pad,
        size.height - pad - bSize,
      ),
      bracketPaint,
    );

    // CENTER CROSSHAIR
    final center = Offset(
      size.width / 2,
      size.height / 2,
    );

    canvas.drawLine(
      Offset(
        center.dx - 10,
        center.dy,
      ),
      Offset(
        center.dx + 10,
        center.dy,
      ),
      bracketPaint,
    );

    canvas.drawLine(
      Offset(
        center.dx,
        center.dy - 10,
      ),
      Offset(
        center.dx,
        center.dy + 10,
      ),
      bracketPaint,
    );
  }

  @override
  bool shouldRepaint(
    covariant _ViewfinderOverlayPainter oldDelegate,
  ) {
    return oldDelegate.accentColor != accentColor;
  }
}