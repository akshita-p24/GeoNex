import 'package:flutter/material.dart';

import '../../core/constants/app_colors.dart';
import '../../core/constants/app_constants.dart';
import '../../core/models/route_model.dart';
import '../../state/app_state.dart';

class RiskAwareRoutingScreen extends StatefulWidget {
  final AppState appState;
  final VoidCallback? onBack;

  const RiskAwareRoutingScreen({
    super.key,
    required this.appState,
    this.onBack,
  });

  @override
  State<RiskAwareRoutingScreen> createState() =>
      _RiskAwareRoutingScreenState();
}

class _RiskAwareRoutingScreenState
    extends State<RiskAwareRoutingScreen> {
  List<RiskRoute> _routes = [];
  RiskRoute? _selectedRoute;

  bool _isLoading = true;
  String? _errorMessage;

  String get _origin =>
      widget.appState.selectedLocation?.name ?? 'Current Location';

  String get _destination => 'Nearest Hospital';

  @override
  void initState() {
    super.initState();
    _loadRoutes();
  }

  Future<void> _loadRoutes() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final routes = await widget.appState.repository.getRoutes(
        _origin,
        _destination,
      );

      if (!mounted) return;

      setState(() {
        _routes = routes;
        _selectedRoute = routes.isEmpty
            ? null
            : routes.firstWhere(
                (route) => route.isRecommended,
                orElse: () => routes.first,
              );
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;

      setState(() {
        _routes = [];
        _selectedRoute = null;
        _isLoading = false;
        _errorMessage = e.toString();
      });
    }
  }

  void _selectRoute(RiskRoute route) {
    setState(() {
      _selectedRoute = route;
    });
  }

  Color _riskColor(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return AppColors.riskLow;
      case RiskLevel.moderate:
        return AppColors.riskModerate;
      case RiskLevel.high:
        return AppColors.riskHigh;
      case RiskLevel.critical:
        return AppColors.riskCritical;
    }
  }

  Color _riskBackground(RiskLevel level) {
    switch (level) {
      case RiskLevel.low:
        return AppColors.riskLowPastel;
      case RiskLevel.moderate:
        return AppColors.riskModeratePastel;
      case RiskLevel.high:
        return AppColors.riskHighPastel;
      case RiskLevel.critical:
        return AppColors.riskCriticalPastel;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack == null
            ? null
            : IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              ),
        title: const Text('Safe Route'),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.error_outline,
                size: 48,
                color: Colors.redAccent,
              ),
              const SizedBox(height: 12),
              const Text(
                'Unable to load safe routes',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadRoutes,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_routes.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.alt_route,
                size: 48,
                color: AppColors.textSecondary,
              ),
              const SizedBox(height: 12),
              const Text(
                'No routes available',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'No risk-aware routes were returned for the selected location.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _loadRoutes,
                icon: const Icon(Icons.refresh),
                label: const Text('Try Again'),
              ),
            ],
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: _loadRoutes,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildRouteHeader(),
          const SizedBox(height: 16),
          _buildRouteVisualization(),
          const SizedBox(height: 16),
          _buildComparisonCard(),
          const SizedBox(height: 16),
          const Text(
            'Available Routes',
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 10),
          ..._routes.map(_buildRouteCard),
          const SizedBox(height: 16),
          if (_selectedRoute != null) _buildSelectedRouteAction(),
        ],
      ),
    );
  }

  Widget _buildRouteHeader() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        children: [
          _routeEndpoint(
            icon: Icons.my_location,
            title: 'Origin',
            value: _origin,
          ),
          const Padding(
            padding: EdgeInsets.only(left: 11),
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                height: 22,
                child: VerticalDivider(
                  width: 1,
                  thickness: 1,
                ),
              ),
            ),
          ),
          _routeEndpoint(
            icon: Icons.local_hospital_outlined,
            title: 'Destination',
            value: _destination,
          ),
        ],
      ),
    );
  }

  Widget _routeEndpoint({
    required IconData icon,
    required String title,
    required String value,
  }) {
    return Row(
      children: [
        Icon(
          icon,
          size: 22,
          color: AppColors.primary,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildRouteVisualization() {
    final route = _selectedRoute;

    return Container(
      height: 220,
      width: double.infinity,
      decoration: BoxDecoration(
        color: const Color(0xFFF4F7FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: route == null
          ? const Center(
              child: Text('No route selected'),
            )
          : CustomPaint(
              painter: _RoutePainter(
                route: route,
                riskColor: _riskColor(route.riskLevel),
              ),
              child: const SizedBox.expand(),
            ),
    );
  }

  Widget _buildComparisonCard() {
    final recommended = _routes.firstWhere(
      (route) => route.isRecommended,
      orElse: () => _routes.first,
    );

    final highestRisk = _routes.reduce(
      (a, b) => a.riskScore > b.riskScore ? a : b,
    );

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Route Safety Comparison',
            style: TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w900,
              color: AppColors.textPrimary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _comparisonMetric(
                  'Recommended',
                  '${recommended.riskScore.toInt()}/100',
                  recommended.riskLevel,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _comparisonMetric(
                  'Highest Risk',
                  '${highestRisk.riskScore.toInt()}/100',
                  highestRisk.riskLevel,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _comparisonMetric(
    String label,
    String value,
    RiskLevel level,
  ) {
    final color = _riskColor(level);

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _riskBackground(level),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: color,
            ),
          ),
          Text(
            level.name.toUpperCase(),
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRouteCard(RiskRoute route) {
    final isSelected = identical(route, _selectedRoute);
    final riskColor = _riskColor(route.riskLevel);

    return GestureDetector(
      onTap: () => _selectRoute(route),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : AppColors.border,
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected
              ? const [
                  BoxShadow(
                    color: Color(0x12000000),
                    blurRadius: 8,
                    offset: Offset(0, 3),
                  ),
                ]
              : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    route.name,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w900,
                      color: AppColors.textPrimary,
                    ),
                  ),
                ),
                if (route.isRecommended)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.primaryPastel,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: const Text(
                      'RECOMMENDED',
                      style: TextStyle(
                        fontSize: 8,
                        fontWeight: FontWeight.w900,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                _routeStat(
                  Icons.route,
                  '${route.distanceKm.toStringAsFixed(1)} km',
                ),
                const SizedBox(width: 16),
                _routeStat(
                  Icons.schedule,
                  '${route.estimatedDurationMinutes} min',
                ),
                const SizedBox(width: 16),
                _routeStat(
                  Icons.warning_amber_outlined,
                  '${route.riskScore.toInt()}/100',
                  color: riskColor,
                ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _riskBackground(route.riskLevel),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                route.avoidanceReason,
                style: TextStyle(
                  fontSize: 11,
                  height: 1.4,
                  fontWeight: FontWeight.w600,
                  color: riskColor,
                ),
              ),
            ),
            if (route.hazardPointsOnRoute.isNotEmpty) ...[
              const SizedBox(height: 10),
              const Text(
                'Hazards on route',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  color: AppColors.textSecondary,
                ),
              ),
              const SizedBox(height: 5),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: route.hazardPointsOnRoute.map(
                  (hazard) {
                    return Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.riskHighPastel,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        hazard,
                        style: const TextStyle(
                          fontSize: 9,
                          fontWeight: FontWeight.w700,
                          color: AppColors.riskHigh,
                        ),
                      ),
                    );
                  },
                ).toList(),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _routeStat(
    IconData icon,
    String text, {
    Color color = AppColors.textSecondary,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          icon,
          size: 15,
          color: color,
        ),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(
            fontSize: 11,
            fontWeight: FontWeight.w700,
            color: color,
          ),
        ),
      ],
    );
  }

  Widget _buildSelectedRouteAction() {
    final route = _selectedRoute!;

    return Column(
      children: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    '${route.name} selected for navigation.',
                  ),
                ),
              );
            },
            icon: const Icon(Icons.navigation_outlined),
            label: const Text('Use Selected Route'),
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Route geometry shown here is prototype/mock routing data.',
          textAlign: TextAlign.center,
          style: const TextStyle(
            fontSize: 10,
            color: AppColors.textMuted,
          ),
        ),
      ],
    );
  }
}

class _RoutePainter extends CustomPainter {
  final RiskRoute route;
  final Color riskColor;

  const _RoutePainter({
    required this.route,
    required this.riskColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (route.waypoints.isEmpty) {
      return;
    }

    final latitudes =
        route.waypoints.map((point) => point.latitude).toList();
    final longitudes =
        route.waypoints.map((point) => point.longitude).toList();

    final minLat = latitudes.reduce(
      (a, b) => a < b ? a : b,
    );
    final maxLat = latitudes.reduce(
      (a, b) => a > b ? a : b,
    );
    final minLon = longitudes.reduce(
      (a, b) => a < b ? a : b,
    );
    final maxLon = longitudes.reduce(
      (a, b) => a > b ? a : b,
    );

    final latRange = (maxLat - minLat).abs();
    final lonRange = (maxLon - minLon).abs();

    Offset toOffset(RouteCoordinate point) {
      final x = lonRange == 0
          ? size.width / 2
          : ((point.longitude - minLon) / lonRange) *
              (size.width - 80) +
              40;

      final y = latRange == 0
          ? size.height / 2
          : size.height -
              (((point.latitude - minLat) / latRange) *
                      (size.height - 70) +
                  35);

      return Offset(x, y);
    }

    final routePaint = Paint()
      ..color = riskColor
      ..strokeWidth = 6
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();

    for (int i = 0; i < route.waypoints.length; i++) {
      final point = toOffset(route.waypoints[i]);

      if (i == 0) {
        path.moveTo(point.dx, point.dy);
      } else {
        path.lineTo(point.dx, point.dy);
      }
    }

    canvas.drawPath(path, routePaint);

    final start = toOffset(route.waypoints.first);
    final end = toOffset(route.waypoints.last);

    final startPaint = Paint()
      ..color = AppColors.primary
      ..style = PaintingStyle.fill;

    final endPaint = Paint()
      ..color = riskColor
      ..style = PaintingStyle.fill;

    canvas.drawCircle(start, 9, startPaint);
    canvas.drawCircle(end, 9, endPaint);

    final startTextPainter = TextPainter(
      text: const TextSpan(
        text: 'START',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    startTextPainter.paint(
      canvas,
      Offset(
        start.dx - startTextPainter.width / 2,
        start.dy + 13,
      ),
    );

    final endTextPainter = TextPainter(
      text: const TextSpan(
        text: 'DESTINATION',
        style: TextStyle(
          color: AppColors.textPrimary,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    endTextPainter.paint(
      canvas,
      Offset(
        end.dx - endTextPainter.width / 2,
        end.dy + 13,
      ),
    );

    for (final waypoint in route.waypoints.skip(1).take(
          route.waypoints.length - 2,
        )) {
      final point = toOffset(waypoint);

      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.fill;

      canvas.drawCircle(point, 7, markerPaint);

      final borderPaint = Paint()
        ..color = riskColor
        ..strokeWidth = 2
        ..style = PaintingStyle.stroke;

      canvas.drawCircle(point, 7, borderPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _RoutePainter oldDelegate) {
    return oldDelegate.route != route ||
        oldDelegate.riskColor != riskColor;
  }
}