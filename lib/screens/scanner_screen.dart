import 'dart:async';
import 'dart:math' as math;
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import '../core/api/api_endpoints.dart';
import '../core/design/design.dart';
import '../models/ble_device_model.dart';
import '../services/account_session.dart';
import '../services/user_resolver.dart';
import 'widgets/scanner_painters.dart';
import 'widgets/scanner_person_sheet.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final Map<String, BleDeviceModel> _devicesMap = {};
  final Map<String, bool> _likedMap = {};
  List<ScannerResolvedEntry> _cachedSortedDevices = [];
  int _devicesMapVersion = 0;
  int _cachedVersion = -1;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  bool _isScanning = false;
  bool _bluetoothOn = true;
  // _chipOn is visual-only placeholder for now; does not actually toggle BLE advertising
  bool _chipOn = true;
  String _viewMode = 'radar'; // radar | list

  late AnimationController _pulseController;
  late AnimationController _sweepController;
  late AnimationController _floatController;

  late UserResolver _resolver;
  final _session = AccountSession.instance;

  @override
  void initState() {
    super.initState();
    _resolver = UserResolver(_session);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat();

    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 7200),
    )..repeat();

    _floatController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3000),
    )..repeat(reverse: true);

    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (mounted) setState(() => _isScanning = scanning);
    });

    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() => _bluetoothOn = state == BluetoothAdapterState.on);
      }
    });

    WidgetsBinding.instance.addObserver(this);
    _session.addListener(_onSessionChanged);
    _startScan();
  }

  void _pauseAnimations() {
    _pulseController.stop();
    _sweepController.stop();
    _floatController.stop();
  }

  void _resumeAnimations() {
    if (_viewMode == 'radar') {
      _pulseController.repeat();
      _sweepController.repeat();
      _floatController.repeat(reverse: true);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      _pauseAnimations();
    } else if (state == AppLifecycleState.resumed) {
      _resumeAnimations();
    }
  }

  void _onSessionChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _session.removeListener(_onSessionChanged);
    _scanSub?.cancel();
    _isScanSub?.cancel();
    _adapterStateSub?.cancel();
    _pulseController.dispose();
    _sweepController.dispose();
    _floatController.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  List<ScannerResolvedEntry> get _sortedDevices {
    if (_cachedVersion == _devicesMapVersion) return _cachedSortedDevices;
    final entries = <ScannerResolvedEntry>[];
    for (final d in _devicesMap.values) {
      final resolved = _resolver.resolve(d);
      if (resolved.relationship == Relationship.unknown &&
          resolved.hasValidPacket &&
          resolved.mode == 0xFF) {
        continue;
      }
      entries.add(ScannerResolvedEntry(device: d, resolved: resolved));
    }
    entries.sort((a, b) {
      final orderCmp = _resolver.sortOrder(a.resolved.relationship)
          .compareTo(_resolver.sortOrder(b.resolved.relationship));
      if (orderCmp != 0) return orderCmp;
      return b.device.rssi.compareTo(a.device.rssi);
    });
    _cachedSortedDevices = entries;
    _cachedVersion = _devicesMapVersion;
    return entries;
  }

  Future<bool> _requestBlePermissions() async {
    // Check adapter state; unauthorized means BLE permissions were denied by the OS.
    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.unauthorized) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Нет разрешений Bluetooth/геолокации — поиск недоступен'),
          ),
        );
      }
      return false;
    }
    return true;
  }

  Future<void> _startScan() async {
    if (!await _requestBlePermissions()) return;
    _devicesMap.clear();
    _devicesMapVersion++;
    setState(() {});
    _scanSub?.cancel();
    _scanSub = FlutterBluePlus.onScanResults.listen((results) {
      for (final r in results) {
        if (r.advertisementData.advName != 'ESP32C3_TAG') continue;
        final device = BleDeviceModel.fromScanResult(r);
        _devicesMap[device.macAddress] = device;
      }
      _devicesMapVersion++;
      if (mounted) setState(() {});
    });
    try {
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 5),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка сканирования: $e')),
        );
      }
    }
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  void _toggleScan() {
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }

  String _fmtDist(int rssi) {
    // Approximate distance from RSSI
    final dist = _rssiToMeters(rssi);
    final meters = math.max(1, dist.round());
    if (dist < 100) return '$meters м';
    if (dist < 1000) return '${(dist / 10).round() * 10} м';
    return '${(dist / 1000).toStringAsFixed(1)} км';
  }

  double _rssiToMeters(int rssi) {
    // Simple RSSI to distance approximation
    final ratio = rssi / -60.0;
    if (ratio < 1.0) return math.pow(ratio, 10).toDouble();
    return (0.89976 * math.pow(ratio, 7.7095) + 0.111).toDouble();
  }

  String _personWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'человек';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) return 'человека';
    return 'человек';
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final entries = _sortedDevices;

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.5),
            radius: 1.2,
            colors: [
              c.accentSoft,
              c.bg,
            ],
          ),
        ),
        child: Column(
          children: [
            // ─── Top bar ───
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                child: Row(
                  children: [
                    // EyeMark + location
                    _buildEyeMark(28),
                    const SizedBox(width: 8),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'СЕЙЧАС ВОКРУГ',
                          style: SeeUTypography.monoLabel.copyWith(
                            color: c.ink3,
                            letterSpacing: 0.8,
                          ),
                        ),
                        Text(
                          'Поиск · ${entries.length} ${_personWord(entries.length)}',
                          style: SeeUTypography.subtitle.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const Spacer(),
                    // Chip status button
                    GestureDetector(
                      onTap: () {
                        HapticFeedback.lightImpact();
                        setState(() => _chipOn = !_chipOn);
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: _chipOn ? c.accentSoft : c.surface2,
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _chipOn ? SeeUColors.accent : c.ink3,
                                boxShadow: _chipOn
                                    ? [BoxShadow(color: SeeUColors.accent, blurRadius: 8)]
                                    : null,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'чип ${_chipOn ? "вкл" : "выкл"}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                                color: _chipOn ? SeeUColors.accent : c.ink3,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // ─── Content: radar + device list below ───
            Expanded(
              child: entries.isEmpty
                  ? _buildRadarView(entries)
                  : _buildRadarWithList(entries),
            ),
          ],
        ),
      ),
    );
  }

  // ignore: unused_element
  Widget _buildToggleTab(String label, String mode) {
    final c = context.seeuColors;
    final isActive = _viewMode == mode;
    return Expanded(
      child: GestureDetector(
        onTap: () {
          HapticFeedback.selectionClick();
          setState(() => _viewMode = mode);
          if (mode == 'radar') {
            _resumeAnimations();
          } else {
            _pauseAnimations();
          }
        },
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
            color: isActive ? c.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            boxShadow: isActive ? SeeUShadows.sm : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? c.ink : c.ink3,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Radar view ────────────────────────────────────────────────────────

  Widget _buildRadarView(List<ScannerResolvedEntry> entries) {
    final c = context.seeuColors;
    return Stack(
      children: [
        // Radar
        Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: AnimatedBuilder(
              animation: Listenable.merge([_sweepController, _pulseController, _floatController]),
              builder: (_, __) {
                return CustomPaint(
                  painter: ScannerRadarPainter(
                    sweepProgress: _sweepController.value,
                    pulseProgress: _pulseController.value,
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Center "You" avatar
                      Positioned.fill(
                        child: Center(
                          child: Transform.translate(
                            offset: Offset(0, -4 * math.sin(_floatController.value * math.pi)),
                            child: Container(
                              width: 56,
                              height: 56,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: SeeUColors.surface,
                                border: Border.all(color: SeeUColors.accent, width: 2),
                                boxShadow: [
                                  BoxShadow(
                                    color: SeeUColors.accent.withValues(alpha: 0.35),
                                    blurRadius: 16,
                                    offset: const Offset(0, 4),
                                  ),
                                ],
                              ),
                              child: const Center(
                                child: Text('🦊', style: TextStyle(fontSize: 28)),
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Device dots
                      ...entries.asMap().entries.map((e) {
                        final idx = e.key;
                        final entry = e.value;
                        return _buildDeviceDot(entry, idx, entries.length);
                      }),
                    ],
                  ),
                );
              },
            ),
          ),
        ),

        // Distance labels (positioned relative to radar center at 160,160 inside the 320×320 box)
        Center(
          child: SizedBox(
            width: 320,
            height: 320,
            child: Stack(
              children: [
                // "10м" label near inner ring (r≈80), at left side of center
                Positioned(
                  top: 160 - 6,
                  left: 160 - 80 + 4,
                  child: Text(
                    '10м',
                    style: SeeUTypography.mono.copyWith(
                      fontSize: 9,
                      color: c.ink3,
                      letterSpacing: 1,
                    ),
                  ),
                ),
                // "50м" label near outer ring (r≈160), at left side of center
                Positioned(
                  top: 160 - 6,
                  left: 4,
                  child: Text(
                    '50м',
                    style: SeeUTypography.mono.copyWith(
                      fontSize: 9,
                      color: c.ink3,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        // Bluetooth off banner
        if (!_bluetoothOn)
          Positioned(
            top: 12,
            left: 24,
            right: 24,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(SeeURadii.medium),
                border: Border.all(color: c.line),
                boxShadow: SeeUShadows.sm,
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsRegular.bluetoothSlash, size: 16, color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Text(
                    'Bluetooth выключен',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: c.ink,
                    ),
                  ),
                ],
              ),
            ),
          ),

        // Bottom hint (placed above the FAB at bottom:100 to avoid overlap)
        Positioned(
          bottom: 160,
          left: 0,
          right: 0,
          child: Center(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12, color: c.ink3),
                children: [
                  TextSpan(
                    text: '${entries.length} ',
                    style: const TextStyle(
                      color: SeeUColors.accent,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  TextSpan(text: '${_personWord(entries.length)} рядом · нажми, чтобы лайкнуть'),
                ],
              ),
            ),
          ),
        ),

        // Scan toggle button (bottom center)
        Positioned(
          bottom: 100,
          left: 0,
          right: 0,
          child: Center(child: _buildFab()),
        ),
      ],
    );
  }

  Widget _buildRadarWithList(List<ScannerResolvedEntry> entries) {
    final emojis = ['🌅', '🚀', '🍑', '🐈\u200D⬛', '🦊', '🛸', '🍞', '🌿', '✨'];
    return RefreshIndicator(
      color: SeeUColors.accent,
      onRefresh: () async {
        // Pull-to-refresh = manual rescan: clear cached devices and start
        // a fresh BLE scan window. The scan resolves async; we don't await
        // it because it runs as a stream subscription. Returning quickly
        // closes the spinner — a long-running re-scan would be confusing.
        await _startScan();
      },
      child: ListView(
      padding: const EdgeInsets.only(bottom: 120),
      children: [
        // Compact radar at top
        SizedBox(
          height: 260,
          child: Center(
            child: SizedBox(
              width: 240,
              height: 240,
              child: AnimatedBuilder(
                animation: Listenable.merge([_sweepController, _pulseController, _floatController]),
                builder: (_, __) {
                  return CustomPaint(
                    painter: ScannerRadarPainter(
                      sweepProgress: _sweepController.value,
                      pulseProgress: _pulseController.value,
                    ),
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        Positioned.fill(
                          child: Center(
                            child: Transform.translate(
                              offset: Offset(0, -3 * math.sin(_floatController.value * math.pi)),
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SeeUColors.surface,
                                  border: Border.all(color: SeeUColors.accent, width: 2),
                                  boxShadow: [
                                    BoxShadow(
                                      color: SeeUColors.accent.withValues(alpha: 0.35),
                                      blurRadius: 12,
                                    ),
                                  ],
                                ),
                                child: const Center(child: Text('🦊', style: TextStyle(fontSize: 22))),
                              ),
                            ),
                          ),
                        ),
                        ...entries.map((entry) {
                          final angle = (entry.device.macAddress.hashCode * 51 + 30) * math.pi / 180;
                          final dist = _rssiToMeters(entry.device.rssi);
                          final r = (dist / 50).clamp(0.0, 1.0) * 80 + 20;
                          final x = math.cos(angle) * r;
                          final y = math.sin(angle) * r;
                          final emoji = emojis[entry.device.macAddress.hashCode.abs() % emojis.length];
                          return Positioned(
                            top: 120 + y - 16,
                            left: 120 + x - 16,
                            child: GestureDetector(
                              onTap: () => _showPersonSheet(entry, emoji),
                              child: Container(
                                width: 32,
                                height: 32,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: SeeUColors.surface,
                                  border: Border.all(color: SeeUColors.borderSubtle, width: 1),
                                  boxShadow: SeeUShadows.sm,
                                ),
                                child: Center(child: Text(emoji, style: const TextStyle(fontSize: 16))),
                              ),
                            ),
                          );
                        }),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        ),
        // Scan button
        Center(child: _buildFab()),
        const SizedBox(height: 16),
        // Found list
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 18),
          child: Text(
            'Найдено ${entries.length} ${_personWord(entries.length)}',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: context.seeuColors.ink2,
            ),
          ),
        ),
        const SizedBox(height: 8),
        ...entries.asMap().entries.map((e) {
          final index = e.key;
          final entry = e.value;
          final emoji = emojis[entry.device.macAddress.hashCode.abs() % emojis.length];
          final alias = (entry.resolved.user?.name ?? '').isNotEmpty
              ? (entry.resolved.user?.name ?? '')
              : 'user_${entry.device.macAddress.substring(0, 5)}';
          final isOnline = entry.device.rssi > -80;

          return TweenAnimationBuilder<double>(
            key: ValueKey(entry.device.macAddress),
            tween: Tween(begin: 0.0, end: 1.0),
            duration: Duration(milliseconds: 300 + index * 40),
            curve: Curves.easeOutCubic,
            builder: (_, val, child) => Opacity(
              opacity: val,
              child: Transform.translate(offset: Offset(0, 8 * (1 - val)), child: child),
            ),
            child: GestureDetector(
              onTap: () => _showPersonSheet(entry, emoji),
              child: Container(
                margin: const EdgeInsets.fromLTRB(18, 0, 18, 8),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: SeeUColors.surface,
                  borderRadius: BorderRadius.circular(SeeURadii.medium),
                  border: Border.all(color: SeeUColors.borderSubtle, width: 0.5),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: SeeUColors.surface,
                        border: Border.all(color: SeeUColors.borderSubtle, width: 1.5),
                      ),
                      child: Center(child: Text(emoji, style: const TextStyle(fontSize: 20))),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(alias, style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600)),
                          const SizedBox(height: 2),
                          Text(
                            '${_fmtDist(entry.device.rssi)} · ${isOnline ? "онлайн" : "далеко"}',
                            style: TextStyle(fontSize: 12, color: context.seeuColors.ink3),
                          ),
                        ],
                      ),
                    ),
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: isOnline ? SeeUColors.success : context.seeuColors.ink4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ],
      ),
    );
  }

  Widget _buildDeviceDot(ScannerResolvedEntry entry, int index, int total) {
    final angle = (entry.device.macAddress.hashCode * 51 + 30) * math.pi / 180;
    final dist = _rssiToMeters(entry.device.rssi);
    final r = (dist / 50).clamp(0.0, 1.0) * 110 + 28;
    final x = math.cos(angle) * r;
    final y = math.sin(angle) * r;

    final emojis = ['🌅', '🚀', '🍑', '🐈\u200D⬛', '🦊', '🛸', '🍞', '🌿', '✨'];
    final emoji = emojis[entry.device.macAddress.hashCode.abs() % emojis.length];
    final isOnline = entry.device.rssi > -80;

    return Positioned(
      top: 160 + y - 22,
      left: 160 + x - 22,
      child: GestureDetector(
        onTap: () => _showPersonSheet(entry, emoji),
        child: TweenAnimationBuilder<double>(
          key: ValueKey(entry.device.macAddress),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 500 + (dist * 20).round()),
          curve: Curves.easeOutBack,
          builder: (_, val, child) => Transform.scale(scale: val, child: child),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: SeeUColors.surface,
                  border: Border.all(color: SeeUColors.borderSubtle, width: 1.5),
                  boxShadow: SeeUShadows.md,
                ),
                child: Stack(
                  children: [
                    Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                    if (isOnline)
                      Positioned(
                        bottom: -2,
                        right: -2,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: SeeUColors.success,
                            border: Border.all(color: SeeUColors.surface, width: 2),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 2),
              Text(
                _fmtDist(entry.device.rssi),
                style: SeeUTypography.mono.copyWith(fontSize: 9, color: SeeUColors.textTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showPersonSheet(ScannerResolvedEntry entry, String emoji) {
    HapticFeedback.mediumImpact();
    final alias = (entry.resolved.user?.name ?? '').isNotEmpty ? (entry.resolved.user?.name ?? '') : 'unknown_${entry.device.macAddress.substring(0, 5)}';
    final dist = _fmtDist(entry.device.rssi);
    final isOnline = entry.device.rssi > -80;
    final publicHex = entry.device.seeuPacket?.idHex;

    showModalBottomSheet(
      context: context,
      backgroundColor: SeeUColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => ScannerPersonSheet(
        emoji: emoji,
        alias: alias,
        distance: dist,
        isOnline: isOnline,
        rssi: entry.device.rssi,
        initialLiked: _likedMap[entry.device.macAddress] ?? false,
        onLikeChanged: (liked) {
          setState(() => _likedMap[entry.device.macAddress] = liked);
        },
        // Show «Открыть профиль» only if we have a usable BLE id.
        onOpenProfile: (publicHex != null && publicHex.isNotEmpty)
            ? () => _resolveAndOpen(publicHex)
            : null,
      ),
    );
  }

  /// Calls the backend `/users/by-device/:publicId` to turn a BLE chip's
  /// public ID into a real account, then navigates to its profile.
  Future<void> _resolveAndOpen(String publicHex) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final dio = Dio(BaseOptions(baseUrl: ApiEndpoints.baseUrl));
      final r = await dio.get('/users/by-device/$publicHex');
      final data = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
      final username = (data as Map)['username'] as String? ?? '';
      if (!mounted) return;
      if (username.isEmpty) {
        messenger.showSnackBar(
          const SnackBar(content: Text('Профиль не найден')),
        );
        return;
      }
      context.push('/profile/$username');
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      messenger.showSnackBar(
        SnackBar(
          content: Text(code == 404
              ? 'Никто не привязал эту метку'
              : 'Не удалось найти профиль'),
        ),
      );
    }
  }

  // ─── List view ─────────────────────────────────────────────────────────

  // ignore: unused_element
  Widget _buildListView(List<ScannerResolvedEntry> entries) {
    if (entries.isEmpty) return _buildEmptyState();

    final emojis = ['🌅', '🚀', '🍑', '🐈\u200D⬛', '🦊', '🛸', '🍞', '🌿', '✨'];

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 120),
      itemCount: entries.length + (_chipOn ? 0 : 1),
      itemBuilder: (context, index) {
        if (!_chipOn && index == entries.length) {
          return _buildChipOffBanner();
        }

        final entry = entries[index];
        final emoji = emojis[entry.device.macAddress.hashCode.abs() % emojis.length];
        final alias = (entry.resolved.user?.name ?? '').isNotEmpty
            ? (entry.resolved.user?.name ?? '')
            : 'user_${entry.device.macAddress.substring(0, 5)}';
        final isOnline = entry.device.rssi > -80;

        return TweenAnimationBuilder<double>(
          key: ValueKey(entry.device.macAddress),
          tween: Tween(begin: 0.0, end: 1.0),
          duration: Duration(milliseconds: 300 + index * 40),
          curve: Curves.easeOutCubic,
          builder: (_, val, child) => Opacity(
            opacity: val,
            child: Transform.translate(
              offset: Offset(0, 8 * (1 - val)),
              child: child,
            ),
          ),
          child: GestureDetector(
            onTap: () => _showPersonSheet(entry, emoji),
            child: Container(
              margin: const EdgeInsets.only(bottom: 8),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: SeeUColors.surface,
                borderRadius: BorderRadius.circular(SeeURadii.medium),
                border: Border.all(color: SeeUColors.borderSubtle, width: 0.5),
              ),
              child: Row(
                children: [
                  // Avatar
                  Stack(
                    children: [
                      Container(
                        width: 46,
                        height: 46,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: SeeUColors.surface2,
                        ),
                        child: Center(child: Text(emoji, style: const TextStyle(fontSize: 22))),
                      ),
                      if (isOnline)
                        Positioned(
                          bottom: 0,
                          right: 0,
                          child: Container(
                            width: 12,
                            height: 12,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: SeeUColors.success,
                              border: Border.all(color: SeeUColors.surface, width: 2),
                            ),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(width: 12),
                  // Info
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          alias,
                          style: SeeUTypography.mono.copyWith(
                            fontSize: 14,
                            color: SeeUColors.textPrimary,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          children: [
                            Text(
                              _fmtDist(entry.device.rssi),
                              style: TextStyle(fontSize: 12, color: SeeUColors.textTertiary),
                            ),
                            Container(
                              width: 2,
                              height: 2,
                              margin: const EdgeInsets.symmetric(horizontal: 8),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: SeeUColors.textQuaternary,
                              ),
                            ),
                            Text(
                              '${entry.device.rssi} dBm',
                              style: TextStyle(fontSize: 12, color: SeeUColors.textTertiary),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Like button
                  GestureDetector(
                    onTap: () {
                      HapticFeedback.lightImpact();
                      setState(() {
                        final mac = entry.device.macAddress;
                        _likedMap[mac] = !(_likedMap[mac] ?? false);
                      });
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: (_likedMap[entry.device.macAddress] ?? false)
                            ? SeeUColors.like
                            : Colors.transparent,
                        border: Border.all(
                          color: (_likedMap[entry.device.macAddress] ?? false)
                              ? SeeUColors.like
                              : SeeUColors.borderSubtle,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          (_likedMap[entry.device.macAddress] ?? false)
                              ? Icons.favorite_rounded
                              : Icons.favorite_border_rounded,
                          size: 18,
                          color: (_likedMap[entry.device.macAddress] ?? false)
                              ? Colors.white
                              : SeeUColors.textSecondary,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildChipOffBanner() {
    return Container(
      padding: const EdgeInsets.all(20),
      margin: const EdgeInsets.only(top: 8),
      decoration: BoxDecoration(
        color: SeeUColors.accentSoft,
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(color: SeeUColors.borderSubtle, width: 0.5),
      ),
      child: Column(
        children: [
          Icon(Icons.bluetooth_disabled_rounded, size: 20, color: SeeUColors.accent),
          const SizedBox(height: 6),
          Text(
            'Чип выключен',
            style: SeeUTypography.subtitle.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 4),
          Text(
            'Включите чип, чтобы вас видели вокруг.\nСами вы видите всех в любом случае.',
            style: TextStyle(fontSize: 12, color: context.seeuColors.ink3, height: 1.4),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 200,
            height: 200,
            child: AnimatedBuilder(
              animation: Listenable.merge([_sweepController, _pulseController]),
              builder: (_, __) => CustomPaint(
                painter: ScannerRadarPainter(
                  sweepProgress: _sweepController.value,
                  pulseProgress: _pulseController.value,
                ),
                child: Center(
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: SeeUColors.surface,
                      border: Border.all(color: SeeUColors.accent, width: 2),
                    ),
                    child: const Center(
                      child: Text('🦊', style: TextStyle(fontSize: 28)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 24),
          Text(
            _isScanning ? 'Ищем людей рядом...' : 'Никого рядом',
            style: SeeUTypography.displayS,
          ),
          const SizedBox(height: 8),
          Text(
            _isScanning ? 'Люди с SeeU появятся здесь' : 'Нажмите кнопку поиска',
            style: TextStyle(fontSize: 13, color: SeeUColors.textTertiary),
          ),
        ],
      ),
    );
  }

  Widget _buildFab() {
    return Tappable.scaled(
      onTap: _bluetoothOn ? _toggleScan : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 300),
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: _isScanning ? SeeUColors.textPrimary : SeeUColors.accent,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          boxShadow: [
            BoxShadow(
              color: (_isScanning ? SeeUColors.textPrimary : SeeUColors.accent)
                  .withValues(alpha: 0.4),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _isScanning ? Icons.stop_rounded : Icons.play_arrow_rounded,
              color: Colors.white,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              _isScanning ? 'Стоп' : 'Поиск',
              style: SeeUTypography.subtitle.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEyeMark(double size) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.22),
        gradient: const RadialGradient(
          center: Alignment(-0.2, -0.3),
          colors: [Color(0xFFFF8060), Color(0xFFFF5A3C)],
        ),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.accent.withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: CustomPaint(
        size: Size(size, size),
        painter: ScannerEyeMarkPainter(),
      ),
    );
  }
}

