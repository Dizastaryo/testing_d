import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import '../core/design/design.dart';
import '../models/ble_device_model.dart';
import '../services/account_session.dart';
import '../services/user_resolver.dart';

class ScannerScreen extends StatefulWidget {
  const ScannerScreen({super.key});

  @override
  State<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends State<ScannerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final Map<String, BleDeviceModel> _devicesMap = {};
  final Map<String, bool> _likedMap = {};
  List<_ResolvedEntry> _cachedSortedDevices = [];
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

  List<_ResolvedEntry> get _sortedDevices {
    if (_cachedVersion == _devicesMapVersion) return _cachedSortedDevices;
    final entries = <_ResolvedEntry>[];
    for (final d in _devicesMap.values) {
      final resolved = _resolver.resolve(d);
      if (resolved.relationship == Relationship.unknown &&
          resolved.hasValidPacket &&
          resolved.mode == 0xFF) {
        continue;
      }
      entries.add(_ResolvedEntry(device: d, resolved: resolved));
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
              SeeUColors.accentSoft,
              SeeUColors.background,
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
                            color: SeeUColors.textTertiary,
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
                          color: _chipOn ? SeeUColors.accentSoft : SeeUColors.surface2,
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
                                color: _chipOn ? SeeUColors.accent : SeeUColors.textTertiary,
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
                                color: _chipOn ? SeeUColors.accent : SeeUColors.textTertiary,
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

            // ─── Radar / List toggle ───
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 4),
              child: Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: SeeUColors.surface2,
                  borderRadius: BorderRadius.circular(SeeURadii.pill),
                ),
                child: Row(
                  children: [
                    _buildToggleTab('Радар', 'radar'),
                    _buildToggleTab('Список', 'list'),
                  ],
                ),
              ),
            ),

            // ─── Content ───
            Expanded(
              child: _viewMode == 'radar'
                  ? _buildRadarView(entries)
                  : _buildListView(entries),
            ),
          ],
        ),
      ),
      floatingActionButton: _viewMode == 'list'
          ? Padding(
              padding: const EdgeInsets.only(bottom: 80),
              child: _buildFab(),
            )
          : null,
    );
  }

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
            color: isActive ? SeeUColors.surface : Colors.transparent,
            borderRadius: BorderRadius.circular(SeeURadii.pill),
            boxShadow: isActive ? SeeUShadows.sm : null,
          ),
          child: Center(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: isActive ? SeeUColors.textPrimary : SeeUColors.textTertiary,
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Radar view ────────────────────────────────────────────────────────

  Widget _buildRadarView(List<_ResolvedEntry> entries) {
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
                  painter: _DesignRadarPainter(
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
                  const Icon(Icons.bluetooth_disabled_rounded, size: 16, color: SeeUColors.accent),
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

  Widget _buildDeviceDot(_ResolvedEntry entry, int index, int total) {
    final c = context.seeuColors;
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

  void _showPersonSheet(_ResolvedEntry entry, String emoji) {
    HapticFeedback.mediumImpact();
    final alias = (entry.resolved.user?.name ?? '').isNotEmpty ? (entry.resolved.user?.name ?? '') : 'unknown_${entry.device.macAddress.substring(0, 5)}';
    final dist = _fmtDist(entry.device.rssi);
    final isOnline = entry.device.rssi > -80;

    showModalBottomSheet(
      context: context,
      backgroundColor: SeeUColors.surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (_) => _PersonSheet(
        emoji: emoji,
        alias: alias,
        distance: dist,
        isOnline: isOnline,
        rssi: entry.device.rssi,
        initialLiked: _likedMap[entry.device.macAddress] ?? false,
        onLikeChanged: (liked) {
          setState(() => _likedMap[entry.device.macAddress] = liked);
        },
      ),
    );
  }

  // ─── List view ─────────────────────────────────────────────────────────

  Widget _buildListView(List<_ResolvedEntry> entries) {
    final c = context.seeuColors;
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
    final c = context.seeuColors;
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
    final c = context.seeuColors;
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
                painter: _DesignRadarPainter(
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
    final c = context.seeuColors;
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
        painter: _EyeMarkPainter(),
      ),
    );
  }
}

// ─── Resolved entry ──────────────────────────────────────────────────────

class _ResolvedEntry {
  final BleDeviceModel device;
  final ResolvedDevice resolved;
  const _ResolvedEntry({required this.device, required this.resolved});
}

// ─── Person bottom sheet ─────────────────────────────────────────────────

class _PersonSheet extends StatefulWidget {
  final String emoji;
  final String alias;
  final String distance;
  final bool isOnline;
  final int rssi;
  final bool initialLiked;
  final void Function(bool liked)? onLikeChanged;

  const _PersonSheet({
    required this.emoji,
    required this.alias,
    required this.distance,
    required this.isOnline,
    required this.rssi,
    this.initialLiked = false,
    this.onLikeChanged,
  });

  @override
  State<_PersonSheet> createState() => _PersonSheetState();
}

class _PersonSheetState extends State<_PersonSheet> {
  late bool _liked;

  @override
  void initState() {
    super.initState();
    _liked = widget.initialLiked;
  }

  void _toggleLike() {
    HapticFeedback.mediumImpact();
    setState(() => _liked = !_liked);
    widget.onLikeChanged?.call(_liked);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Handle
          Container(
            width: 36,
            height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: SeeUColors.textQuaternary,
              borderRadius: BorderRadius.circular(99),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              children: [
                // Avatar + alias
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: SeeUColors.surface2,
                    border: Border.all(color: SeeUColors.borderSubtle),
                  ),
                  child: Center(child: Text(widget.emoji, style: const TextStyle(fontSize: 44))),
                ),
                const SizedBox(height: 14),
                Text(widget.alias, style: SeeUTypography.displayM),
                const SizedBox(height: 4),
                RichText(
                  text: TextSpan(
                    style: TextStyle(fontSize: 13, color: SeeUColors.textTertiary),
                    children: [
                      const TextSpan(text: 'виден только потому что '),
                      TextSpan(
                        text: 'рядом',
                        style: TextStyle(
                          color: SeeUColors.accent,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                // Stats
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SeeUColors.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.medium),
                  ),
                  child: Row(
                    children: [
                      _stat('Дистанция', widget.distance),
                      _stat('Сигнал', '${widget.rssi} dBm'),
                      _stat('Статус', widget.isOnline ? 'онлайн' : 'офлайн'),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                // Privacy notice
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeeUColors.accentSoft,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(Icons.shield_outlined, size: 18, color: SeeUColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Это псевдоним. Настоящий аккаунт скрыт. Вы можете только лайкнуть — и если вам ответят взаимно, появится возможность написать.',
                          style: TextStyle(
                            fontSize: 12,
                            color: SeeUColors.textSecondary,
                            height: 1.45,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                // Actions
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => Navigator.pop(context),
                        child: Container(
                          height: 52,
                          decoration: BoxDecoration(
                            color: SeeUColors.surface2,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Center(
                            child: Text(
                              'Закрыть',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: SeeUColors.textSecondary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      flex: 2,
                      child: GestureDetector(
                        onTap: _toggleLike,
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 200),
                          height: 52,
                          decoration: BoxDecoration(
                            color: _liked ? SeeUColors.like : SeeUColors.surface2,
                            borderRadius: BorderRadius.circular(16),
                            boxShadow: _liked
                                ? [
                                    BoxShadow(
                                      color: SeeUColors.like.withValues(alpha: 0.3),
                                      blurRadius: 16,
                                      offset: const Offset(0, 6),
                                    ),
                                  ]
                                : null,
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                _liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                size: 18,
                                color: _liked ? Colors.white : SeeUColors.textSecondary,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                _liked ? 'Лайк поставлен' : 'Поставить лайк',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: _liked ? Colors.white : SeeUColors.textSecondary,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(
      child: Column(
        children: [
          Text(value, style: SeeUTypography.displayS),
          const SizedBox(height: 2),
          Text(
            label.toUpperCase(),
            style: SeeUTypography.monoLabel.copyWith(fontSize: 10),
          ),
        ],
      ),
    );
  }
}

// ─── Radar painter (design version) ──────────────────────────────────────

class _DesignRadarPainter extends CustomPainter {
  final double sweepProgress;
  final double pulseProgress;

  _DesignRadarPainter({required this.sweepProgress, required this.pulseProgress});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = size.width / 2;
    const color = SeeUColors.accent;

    // Static rings
    for (var i = 1; i <= 3; i++) {
      final radius = maxRadius * (i / 3.0) * 0.75 + maxRadius * 0.25;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: 0.18)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 0.5,
      );
    }

    // Pulse rings
    for (var i = 0; i < 3; i++) {
      final t = (pulseProgress + i * 0.33) % 1.0;
      final radius = 30 + t * (maxRadius - 30);
      final opacity = (1.0 - t) * 0.5;
      canvas.drawCircle(
        center,
        radius,
        Paint()
          ..color = color.withValues(alpha: opacity)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5 * (1.0 - t) + 0.5,
      );
    }

    // Sweep cone
    canvas.save();
    canvas.translate(center.dx, center.dy);
    final sweepAngle = sweepProgress * 2 * math.pi;
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        startAngle: sweepAngle - 1.4,
        endAngle: sweepAngle,
        colors: [
          Colors.transparent,
          color.withValues(alpha: 0.18),
          color.withValues(alpha: 0.4),
          color.withValues(alpha: 0.5),
        ],
        stops: const [0.0, 0.6, 0.95, 1.0],
        tileMode: TileMode.clamp,
      ).createShader(Rect.fromCircle(center: Offset.zero, radius: maxRadius));
    canvas.drawCircle(Offset.zero, maxRadius, sweepPaint);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _DesignRadarPainter old) => true;
}

// ─── EyeMark painter ─────────────────────────────────────────────────────

class _EyeMarkPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);

    final eyePath = Path();
    eyePath.moveTo(s * 0.12, s / 2);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.2, s / 2, s * 0.2);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.2, s * 0.88, s / 2);
    eyePath.quadraticBezierTo(s * 0.65, s * 0.8, s / 2, s * 0.8);
    eyePath.quadraticBezierTo(s * 0.35, s * 0.8, s * 0.12, s / 2);
    eyePath.close();
    canvas.drawPath(eyePath, Paint()..color = const Color(0xFFFFF6F0));

    final irisPaint = Paint()
      ..shader = RadialGradient(
        center: const Alignment(-0.2, -0.2),
        colors: [const Color(0xFFFF6E50), const Color(0xFFC12A1A)],
      ).createShader(Rect.fromCircle(center: center, radius: s * 0.18));
    canvas.drawCircle(center, s * 0.18, irisPaint);

    canvas.drawCircle(
      Offset(s * 0.44, s * 0.44),
      s * 0.04,
      Paint()..color = Colors.white,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
