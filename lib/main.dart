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
  // Опорная точка: GPS + пиксели
  static const double refLat = 50.248886;
  static const double refLon = 66.919850;
  static const double refX = 2746.0;
  static const double refY = 4846.0;

  late final double _degPerPxLat;
  late final double _degPerPxLon;

  Offset? userPixel;
  double userHeading = 0;
  StreamSubscription<Position>? _positionStream;
  final TransformationController _controller = TransformationController();

  @override
  void initState() {
    super.initState();

    // Градусы на пиксель — 1 пиксель = 1 метр
    const metersPerDegLat = 111320.0;
    final metersPerDegLon = metersPerDegLat * cos(refLat * pi / 180);

    _degPerPxLat = 1 / metersPerDegLat;
    _degPerPxLon = 1 / metersPerDegLon;

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

  Offset _geoToPixel(double lat, double lon) {
    final dLat = refLat - lat;
    final dLon = lon - refLon;
    final dy = dLat / _degPerPxLat;
    final dx = dLon / _degPerPxLon;
    return Offset(refX + dx, refY + dy);
  }

  LatLng _pixelToGeo(Offset p) {
    final dx = p.dx - refX;
    final dy = p.dy - refY;
    final lon = refLon + dx * _degPerPxLon;
    final lat = refLat - dy * _degPerPxLat;
    return LatLng(lat, lon);
  }

  void _showCopiedSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Скопировано: $text'),
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

    _controller.value = Matrix4.identity()
      ..translate(dx, dy)
      ..scale(scale);
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
                  if (userPixel != null)
                    Positioned(
                      left: userPixel!.dx - 1,
                      top: userPixel!.dy - 1,
                      child: Transform.rotate(
                        angle: userHeading * pi / 180,
                        child: const Icon(Icons.navigation, size: 2),
                      ),
                    ),
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

class LatLng {
  final double lat, lng;
  LatLng(this.lat, this.lng);
}
