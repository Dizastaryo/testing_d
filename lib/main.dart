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
  Offset? manualMarker;
  final TransformationController _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    _requestPermissionAndLocate();
  }

  Future<void> _requestPermissionAndLocate() async {
    // Проверяем статус разрешений
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return;
    }
    if (perm == LocationPermission.deniedForever) {
      // Предложим открыть настройки
      await openAppSettings();
      return;
    }
    if (perm == LocationPermission.always ||
        perm == LocationPermission.whileInUse) {
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        userPixel = _geoToPixel(pos.latitude, pos.longitude);
      });
    }
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
                      setState(() => manualMarker = p);
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
                      left: userPixel!.dx - 24,
                      top: userPixel!.dy - 24,
                      child: Image.asset(
                        'assets/me.png',
                        width: 48,
                        height: 48,
                      ),
                    ),
                  if (manualMarker != null)
                    Positioned(
                      left: manualMarker!.dx - 16,
                      top: manualMarker!.dy - 32,
                      child: const Icon(
                        Icons.place,
                        color: Colors.red,
                        size: 32,
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
