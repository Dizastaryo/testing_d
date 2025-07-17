import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:permission_handler/permission_handler.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Custom SVG Map GPS',
      theme: ThemeData(useMaterial3: true),
      home: const MapPage(),
    );
  }
}

class MapPage extends StatefulWidget {
  const MapPage({super.key});

  @override
  State<MapPage> createState() => _MapPageState();
}

class _MapPageState extends State<MapPage> {
  final double imageSize = 6160.0;
  final double lat1 = 50.254141, lon1 = 66.923138, x1 = 3000, y1 = 4162;
  final double lat2 = 50.248923, lon2 = 66.902318, x2 = 1504, y2 = 4847;

  Offset? userPixel;
  double userHeading = 0;
  StreamSubscription<Position>? _positionStream;
  final TransformationController _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    _requestPermissionAndTrack();
  }

  Future<void> _requestPermissionAndTrack() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return;
    }
    if (perm == LocationPermission.deniedForever) {
      await openAppSettings();
      return;
    }

    _positionStream =
        Geolocator.getPositionStream(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.best,
            distanceFilter: 5,
          ),
        ).listen((Position pos) {
          setState(() {
            userPixel = _geoToPixel(pos.latitude, pos.longitude);
            userHeading = pos.heading;
          });
        });
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    super.dispose();
  }

  double get _pixelsPerLat => (y2 - y1) / (lat1 - lat2);
  double get _pixelsPerLon => (x2 - x1) / (lon2 - lon1);

  Offset _geoToPixel(double lat, double lon) {
    final dx = (lon - lon1) * _pixelsPerLon + x1;
    final dy = (lat1 - lat) * _pixelsPerLat + y1;
    return Offset(dx, dy);
  }

  LatLng _pixelToGeo(Offset p) {
    final lon = ((p.dx - x1) / _pixelsPerLon) + lon1;
    final lat = lat1 - ((p.dy - y1) / _pixelsPerLat);
    return LatLng(lat, lon);
  }

  void _showCopiedSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Скопировано: \$text'),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _goToUserLocation() {
    if (userPixel == null) return;
    final scale = _controller.value.getMaxScaleOnAxis();
    final size = MediaQuery.of(context).size;
    final dx = -userPixel!.dx * scale + size.width / 2;
    final dy = -userPixel!.dy * scale + size.height / 2;

    setState(() {
      _controller.value = Matrix4.identity()
        ..translate(dx, dy)
        ..scale(scale);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom SVG Map GPS')),
      body: Stack(
        children: [
          InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(double.infinity),
            minScale: 1,
            maxScale: 5,
            transformationController: _controller,
            child: SizedBox(
              width: imageSize,
              height: imageSize,
              child: Stack(
                children: [
                  GestureDetector(
                    onTapDown: (details) {
                      final p = details.localPosition;
                      final coords = _pixelToGeo(p);
                      final txt =
                          '${coords.lat.toStringAsFixed(6)}, ${coords.lng.toStringAsFixed(6)}';
                      Clipboard.setData(ClipboardData(text: txt));
                      _showCopiedSnackBar(txt);
                    },
                    child: SvgPicture.asset(
                      'assets/map.svg',
                      width: imageSize,
                      height: imageSize,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (userPixel != null) ...[
                    Positioned(
                      left: userPixel!.dx - 75,
                      top: userPixel!.dy - 75,
                      child: CustomPaint(
                        size: const Size(150, 150),
                        painter: RadarPainter(heading: userHeading),
                      ),
                    ),
                    Positioned(
                      left: userPixel!.dx - 1,
                      top: userPixel!.dy - 1,
                      child: Transform.rotate(
                        angle: userHeading * pi / 180,
                        child: const Icon(Icons.navigation, size: 2),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
          Positioned(
            bottom: 16,
            right: 16,
            child: FloatingActionButton(
              onPressed: _goToUserLocation,
              child: const Icon(Icons.my_location),
            ),
          ),
        ],
      ),
    );
  }
}

class RadarPainter extends CustomPainter {
  final double heading;
  RadarPainter({required this.heading});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;

    final circlePaint = Paint()
      ..color = Colors.blue.withOpacity(0.2)
      ..style = PaintingStyle.fill;

    final sectorPaint = Paint()
      ..color = Colors.blue.withOpacity(0.4)
      ..style = PaintingStyle.fill;

    canvas.drawCircle(center, radius, circlePaint);

    final startAngle = (heading - 30) * pi / 180;
    final sweepAngle = 60 * pi / 180;
    final path = Path()
      ..moveTo(center.dx, center.dy)
      ..arcTo(
        Rect.fromCircle(center: center, radius: radius),
        startAngle,
        sweepAngle,
        false,
      )
      ..close();

    canvas.drawPath(path, sectorPaint);
  }

  @override
  bool shouldRepaint(covariant RadarPainter oldDelegate) {
    return oldDelegate.heading != heading;
  }
}

class LatLng {
  final double lat, lng;
  LatLng(this.lat, this.lng);
}
