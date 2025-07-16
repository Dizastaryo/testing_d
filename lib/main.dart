import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:geolocator/geolocator.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter/services.dart';

void main() => runApp(const MyApp());

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
  // Размер карты в пикселях
  final double imageSize = 6160.0;

  // Точка №1: GPS ↔ пиксели
  final double lat1 = 50.254141;
  final double lon1 = 66.923138;
  final double x1 = 3000;
  final double y1 = 4162;

  // Точка №2: GPS ↔ пиксели
  final double lat2 = 50.248923;
  final double lon2 = 66.902318;
  final double x2 = 1504;
  final double y2 = 4847;

  Offset? userPixel;
  Offset? manualMarker;
  final TransformationController _controller = TransformationController();

  @override
  void initState() {
    super.initState();
    requestPermissionAndLocate();
  }

  Future<void> requestPermissionAndLocate() async {
    if (await Permission.location.request().isGranted) {
      final pos = await Geolocator.getCurrentPosition();
      setState(() {
        userPixel = geoToPixel(pos.latitude, pos.longitude);
      });
    }
  }

  // масштаб в пикс./градус
  double get pixelsPerLat => (y2 - y1) / (lat1 - lat2);
  double get pixelsPerLon => (x2 - x1) / (lon2 - lon1);

  /// GPS → пиксели
  Offset geoToPixel(double lat, double lon) {
    final dx = (lon - lon1) * pixelsPerLon + x1;
    final dy = (lat1 - lat) * pixelsPerLat + y1;
    return Offset(dx, dy);
  }

  /// пиксели → GPS
  LatLng pixelToGeo(Offset p) {
    final lon = ((p.dx - x1) / pixelsPerLon) + lon1;
    final lat = lat1 - ((p.dy - y1) / pixelsPerLat);
    return LatLng(lat, lon);
  }

  void showCopiedSnackBar(String text) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Скопировано: $text'), duration: const Duration(seconds: 2)),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Custom SVG Map GPS')),
      body: InteractiveViewer(
        constrained: false,
        boundaryMargin: const EdgeInsets.all(double.infinity),
        minScale: 1,
        maxScale: 5,
        transformationController: _controller,
        child: SizedBox(
          width: imageSize,
          height: imageSize,
          child: Stack(children: [
            // фон и тапы
            GestureDetector(
              onTapDown: (d) {
                final p = d.localPosition;
                setState(() => manualMarker = p);
                final coords = pixelToGeo(p);
                final txt = '${coords.lat.toStringAsFixed(6)}, ${coords.lng.toStringAsFixed(6)}';
                Clipboard.setData(ClipboardData(text: txt));
                showCopiedSnackBar(txt);
              },
              child: SvgPicture.asset(
                'assets/map.svg',
                width: imageSize,
                height: imageSize,
                fit: BoxFit.cover,
              ),
            ),
            // GPS-маркер
            if (userPixel != null)
              Positioned(
                left: userPixel!.dx - 16,
                top: userPixel!.dy - 32,
                child: const Icon(Icons.my_location, color: Colors.blue, size: 32),
              ),
            // Маркер тапa
            if (manualMarker != null)
              Positioned(
                left: manualMarker!.dx - 16,
                top: manualMarker!.dy - 32,
                child: const Icon(Icons.place, color: Colors.red, size: 32),
              ),
          ]),
        ),
      ),
    );
  }
}

class LatLng {
  final double lat, lng;
  LatLng(this.lat, this.lng);
}
