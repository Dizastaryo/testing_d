import 'dart:async';
import 'dart:ui' as ui;
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:flutter/services.dart';
import 'package:flutter_blue_plus/flutter_blue_plus.dart';
import 'package:go_router/go_router.dart';
import '../core/api/api_client.dart';
import '../core/design/design.dart';
import '../core/providers/auth_provider.dart';
import '../core/providers/scanner_provider.dart';
import '../models/ble_device_model.dart';
import '../services/account_session.dart';
import '../services/user_resolver.dart';
import 'widgets/my_bracelet_sheet.dart';
import 'widgets/scanner_painters.dart';
import '../features/spark/spark_send_sheet.dart';

// ── Entry: BLE device + resolved local info + server profile ─────────────────

class ScannerResolvedEntry {
  final BleDeviceModel device;
  final ResolvedDevice resolved;
  final ScanProfile? scanProfile;

  const ScannerResolvedEntry({
    required this.device,
    required this.resolved,
    this.scanProfile,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class ScannerScreen extends ConsumerStatefulWidget {
  const ScannerScreen({super.key});

  @override
  ConsumerState<ScannerScreen> createState() => _ScannerScreenState();
}

class _ScannerScreenState extends ConsumerState<ScannerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final Map<String, BleDeviceModel> _devicesMap = {};
  List<ScannerResolvedEntry> _cachedSortedDevices = [];
  int _devicesMapVersion = 0;
  int _cachedVersion = -1;
  StreamSubscription<List<ScanResult>>? _scanSub;
  StreamSubscription<bool>? _isScanSub;
  StreamSubscription<BluetoothAdapterState>? _adapterStateSub;
  bool _isScanning = false;
  bool _bluetoothOn = true;

  late AnimationController _pulseController;

  late UserResolver _resolver;

  final Map<String, ScanProfile> _scanProfiles = {};
  Timer? _resolveTimer;

  @override
  void initState() {
    super.initState();
    _resolver = UserResolver(AccountSession.instance);

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3600),
    )..repeat();

    _isScanSub = FlutterBluePlus.isScanning.listen((scanning) {
      if (!mounted) return;
      setState(() => _isScanning = scanning);
      // Волны радара живут только пока идёт скан — на паузе замирают.
      if (scanning) {
        if (!_pulseController.isAnimating) _pulseController.repeat();
      } else {
        _pulseController.stop();
      }
    });

    _adapterStateSub = FlutterBluePlus.adapterState.listen((state) {
      if (mounted) {
        setState(() => _bluetoothOn = state == BluetoothAdapterState.on);
      }
    });

    WidgetsBinding.instance.addObserver(this);
    _startScan();
  }

  void _pauseAnimations() {
    _pulseController.stop();
  }

  void _resumeAnimations() {
    // Возобновляем дыхание радара только если скан активен.
    if (_isScanning && !_pulseController.isAnimating) {
      _pulseController.repeat();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      _pauseAnimations();
    } else if (state == AppLifecycleState.resumed) {
      _resumeAnimations();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _resolveTimer?.cancel();
    _scanSub?.cancel();
    _isScanSub?.cancel();
    _adapterStateSub?.cancel();
    _pulseController.dispose();
    FlutterBluePlus.stopScan();
    super.dispose();
  }

  // Returns only entries with a resolved real user profile.
  List<ScannerResolvedEntry> get _sortedDevices {
    if (_cachedVersion == _devicesMapVersion) return _cachedSortedDevices;
    final entries = <ScannerResolvedEntry>[];
    for (final d in _devicesMap.values) {
      final resolved = _resolver.resolve(d);
      if (resolved.isMyChip) continue;
      if (resolved.relationship == Relationship.unknown &&
          resolved.hasValidPacket &&
          resolved.mode == 0xFF) {
        continue;
      }
      if (!resolved.hasValidPacket) continue;
      final profile = d.seeuPacket != null
          ? _scanProfiles[d.seeuPacket!.idHex]
          : null;
      // Only show entries where backend resolved a real user.
      if (profile == null || profile.username.isEmpty) continue;
      entries.add(ScannerResolvedEntry(
        device: d,
        resolved: resolved,
        scanProfile: profile,
      ));
    }
    entries.sort((a, b) => b.device.rssi.compareTo(a.device.rssi));
    _cachedSortedDevices = entries;
    _cachedVersion = _devicesMapVersion;
    return entries;
  }

  Future<bool> _requestBlePermissions() async {
    final state = await FlutterBluePlus.adapterState.first;
    if (state == BluetoothAdapterState.unauthorized) {
      if (mounted) {
        showSeeUSnackBar(context, 'Нет разрешений Bluetooth/геолокации',
            tone: SeeUTone.danger);
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
      bool changed = false;
      for (final r in results) {
        final name = r.advertisementData.advName;
        if (name != 'SeeUBand' && name != 'ESP32C3_TAG') continue;
        final device = BleDeviceModel.fromScanResult(r);
        _devicesMap[device.macAddress] = device;
        changed = true;
      }
      if (changed) {
        _devicesMapVersion++;
        if (mounted) setState(() {});
        _scheduleResolve();
      }
    });
    try {
      await FlutterBluePlus.startScan(
        continuousUpdates: true,
        removeIfGone: const Duration(seconds: 5),
      );
    } catch (e) {
      if (mounted) {
        showSeeUSnackBar(context, 'Ошибка сканирования: $e',
            tone: SeeUTone.danger);
      }
    }
  }

  void _scheduleResolve() {
    _resolveTimer?.cancel();
    _resolveTimer = Timer(const Duration(milliseconds: 500), () async {
      final hashes = <String>[];
      for (final d in _devicesMap.values) {
        final hex = d.seeuPacket?.idHex;
        if (hex != null && hex.isNotEmpty && !_scanProfiles.containsKey(hex)) {
          hashes.add(hex);
        }
      }
      if (hashes.isEmpty) return;
      try {
        final api = ref.read(apiClientProvider);
        final resolved = await resolveScanProfiles(api, hashes);
        if (mounted && resolved.isNotEmpty) {
          setState(() {
            _scanProfiles.addAll(resolved);
            _devicesMapVersion++;
          });
        }
      } catch (_) {}
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  void _toggleScan() {
    HapticFeedback.lightImpact();
    if (_isScanning) {
      _stopScan();
    } else {
      _startScan();
    }
  }

  String _personWord(int count) {
    final mod10 = count % 10;
    final mod100 = count % 100;
    if (mod10 == 1 && mod100 != 11) return 'человек';
    if (mod10 >= 2 && mod10 <= 4 && (mod100 < 10 || mod100 >= 20)) {
      return 'человека';
    }
    return 'человек';
  }

  String _topTitle(List<ScannerResolvedEntry> entries) {
    if (entries.isNotEmpty) {
      return '${entries.length} ${_personWord(entries.length)} рядом';
    }
    return _isScanning ? 'Ищем рядом…' : 'На паузе';
  }

  // Честный индикатор близости из RSSI: 3 — рядом, 2 — близко, 1 — далеко.
  int _rssiLevel(int rssi) {
    if (rssi >= -60) return 3;
    if (rssi >= -75) return 2;
    return 1;
  }

  String _rssiLabel(int rssi) {
    switch (_rssiLevel(rssi)) {
      case 3:
        return 'рядом';
      case 2:
        return 'близко';
      default:
        return 'далеко';
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final entries = _sortedDevices;
    final user = ref.watch(authProvider).user;
    final showList = entries.isNotEmpty; // ≥1 человек → сразу список (B).

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: const Alignment(0, -0.5),
            radius: 1.2,
            colors: [c.accentSoft, c.bg],
          ),
        ),
        child: Column(
          children: [
            // Top bar — editorial-заголовок + пилюля браслета. Кнопка play/pause
            // показывается только в режиме списка; в радаре управление скана —
            // одна большая кнопка (без дублирующей верхней).
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(18, 8, 18, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'СЕЙЧАС ВОКРУГ',
                            style: SeeUTypography.monoLabel.copyWith(
                                color: c.ink3, letterSpacing: 0.8),
                          ),
                          Text(
                            _topTitle(entries),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: SeeUTypography.subtitle
                                .copyWith(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    if (showList) ...[
                      _buildScanToggle(c),
                      const SizedBox(width: 8),
                    ],
                    _buildMyBraceletPill(c),
                  ],
                ),
              ),
            ),
            // Content: список (B) либо радар (A/C).
            Expanded(
              child: showList
                  ? _buildAccountList(entries)
                  : _buildRadarView(user?.avatarUrl),
            ),
          ],
        ),
      ),
    );
  }

  // ── Top control: Stop/Start (стеклянная круглая кнопка) ──────────────────────

  Widget _buildScanToggle(SeeUThemeColors c) {
    return Tappable.scaled(
      onTap: _bluetoothOn ? _toggleScan : null,
      scaleFactor: 0.9,
      child: ClipOval(
        child: BackdropFilter(
          filter: ui.ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(alpha: 0.18),
                  Colors.white.withValues(alpha: 0.04),
                ],
              ),
              border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.45),
                  width: 0.8),
            ),
            child: Icon(
              _isScanning ? PhosphorIconsBold.pause : PhosphorIconsBold.play,
              size: 20,
              color: _bluetoothOn ? SeeUColors.accent : c.ink4,
            ),
          ),
        ),
      ),
    );
  }

  // ── B: Account list ──────────────────────────────────────────────────────────

  Widget _buildAccountList(List<ScannerResolvedEntry> entries) {
    final c = context.seeuColors;
    final paused = !_isScanning;
    // Никакого pull-to-refresh — скан живёт постоянно и сам обновляет список.
    return ListView(
      padding: const EdgeInsets.only(top: 4, bottom: 120),
      children: [
        if (paused) _buildPausedBanner(c),
        // Section header
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 12),
          child: Text(
            'Рядом сейчас',
            style:
                SeeUTypography.displayS.copyWith(fontWeight: FontWeight.w500),
          ),
        ),
        // Account cards (людей точками в радаре НЕ дублируем).
        ...entries.asMap().entries.map(
              (e) => _buildPersonCard(e.value, e.key),
            ),
      ],
    );
  }

  Widget _buildPausedBanner(SeeUThemeColors c) {
    return Container(
      margin: const EdgeInsets.fromLTRB(18, 8, 18, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: c.surface.withValues(alpha: 0.7),
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5), width: 0.8),
      ),
      child: Row(
        children: [
          const Icon(PhosphorIconsFill.pause, size: 15, color: SeeUColors.accent),
          const SizedBox(width: 8),
          Text('Скан на паузе',
              style: SeeUTypography.caption
                  .copyWith(fontWeight: FontWeight.w600, color: c.ink)),
        ],
      ),
    );
  }

  Widget _buildPersonCard(ScannerResolvedEntry entry, int index) {
    final c = context.seeuColors;
    final profile = entry.scanProfile!;

    return TweenAnimationBuilder<double>(
      key: ValueKey(entry.device.macAddress),
      tween: Tween(begin: 0.0, end: 1.0),
      duration: Duration(milliseconds: 300 + index * 40),
      curve: Curves.easeOutCubic,
      builder: (_, val, child) => Opacity(
        opacity: val,
        child:
            Transform.translate(offset: Offset(0, 8 * (1 - val)), child: child),
      ),
      child: GestureDetector(
        onTap: () {
          HapticFeedback.lightImpact();
          context.push('/profile/${profile.username}');
        },
        child: Container(
          margin: const EdgeInsets.fromLTRB(18, 0, 18, 10),
          padding: const EdgeInsets.all(14),
          // «Дешёвое стекло» — тинт+градиент+бордюр, без BackdropFilter (скролл-лента).
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                c.surface.withValues(alpha: 0.85),
                c.surface.withValues(alpha: 0.55),
              ],
            ),
            borderRadius: BorderRadius.circular(SeeURadii.medium),
            border:
                Border.all(color: Colors.white.withValues(alpha: 0.6), width: 0.8),
            boxShadow: SeeUShadows.sm,
          ),
          child: Row(
            children: [
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: c.surface2,
                backgroundImage: profile.avatarUrl.isNotEmpty
                    ? CachedNetworkImageProvider(profile.avatarUrl)
                    : null,
                child: profile.avatarUrl.isEmpty
                    ? Text(
                        profile.username.isNotEmpty
                            ? profile.username[0].toUpperCase()
                            : '?',
                        style: SeeUTypography.subtitle.copyWith(
                            fontWeight: FontWeight.w600, color: c.ink2),
                      )
                    : null,
              ),
              const SizedBox(width: 12),
              // Username + честный индикатор близости
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '@${profile.username}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: SeeUTypography.subtitle.copyWith(
                          fontWeight: FontWeight.w600, color: c.ink),
                    ),
                    const SizedBox(height: 4),
                    _buildProximity(entry.device.rssi, c),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Spark button (отправка Spark — отдельным действием)
              _buildSparkButton(c, profile),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProximity(int rssi, SeeUThemeColors c) {
    final level = _rssiLevel(rssi);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // 3 полоски сигнала
        Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: List.generate(3, (i) {
            final active = i < level;
            return Container(
              width: 3,
              height: 5.0 + i * 4,
              margin: const EdgeInsets.only(right: 2),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(1),
                color: active
                    ? SeeUColors.accent
                    : c.ink4.withValues(alpha: 0.3),
              ),
            );
          }),
        ),
        const SizedBox(width: 6),
        Text(
          _rssiLabel(rssi),
          style: SeeUTypography.monoLabel
              .copyWith(color: c.ink3, letterSpacing: 0.6),
        ),
      ],
    );
  }

  Widget _buildSparkButton(SeeUThemeColors c, ScanProfile profile) {
    return Tappable.scaled(
      onTap: () {
        HapticFeedback.mediumImpact();
        SparkSendSheet.show(
          context,
          ref,
          receiverId: profile.userId,
          receiverName: profile.fullName.isNotEmpty
              ? profile.fullName
              : profile.username,
          proofDeviceHash: profile.deviceHash,
          avatarUrl: profile.avatarUrl,
        );
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.accentSoft,
        ),
        child: const Icon(PhosphorIconsFill.fireSimple,
            size: 20, color: SeeUColors.accent),
      ),
    );
  }

  // ── A / C: Radar view (ищем / пауза) ─────────────────────────────────────────

  Widget _buildRadarView(String? avatarUrl) {
    final c = context.seeuColors;
    final paused = !_isScanning;
    return Stack(
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Радар с фото профиля в центре. На паузе — приглушён и не дышит
              // (контроллер остановлен, значение заморожено).
              Opacity(
                opacity: paused ? 0.55 : 1.0,
                child: SizedBox(
                  width: 260,
                  height: 260,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (_, __) => CustomPaint(
                      painter: ScannerRadarPainter(
                          pulseProgress: _pulseController.value),
                      child: Center(child: _buildCenterAvatar(avatarUrl, 104)),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                paused ? 'Скан на паузе' : 'Ищем людей рядом…',
                style: SeeUTypography.displayS,
              ),
              const SizedBox(height: 8),
              Text(
                paused
                    ? 'Поиск приостановлен — возобновите, когда будете\nрядом с другими пользователями SeeU'
                    : 'Держите Bluetooth включённым и будьте\nрядом с другими пользователями SeeU',
                textAlign: TextAlign.center,
                style: SeeUTypography.caption
                    .copyWith(color: c.ink3, height: 1.45),
              ),
              const SizedBox(height: 28),
              _buildScanControlBig(paused),
            ],
          ),
        ),
        if (!_bluetoothOn)
          Positioned(
            top: 12,
            left: 24,
            right: 24,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(SeeURadii.medium),
                border: Border.all(color: c.line),
                boxShadow: SeeUShadows.sm,
              ),
              child: Row(
                children: [
                  const Icon(PhosphorIconsRegular.bluetoothSlash,
                      size: 16, color: SeeUColors.accent),
                  const SizedBox(width: 8),
                  Text('Bluetooth выключен',
                      style: SeeUTypography.caption.copyWith(
                          fontWeight: FontWeight.w600, color: c.ink)),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Центр радара — фото профиля в стеклянном кольце + мягкий glow.
  /// Нет фото → фолбэк-лого «глаз» (никакой буквы «Я»).
  Widget _buildCenterAvatar(String? url, double size) {
    final hasPhoto = url != null && url.isNotEmpty;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: SeeUColors.surface,
        border: Border.all(
            color: Colors.white.withValues(alpha: 0.75), width: 2.5),
        boxShadow: [
          BoxShadow(
            color: SeeUColors.accent.withValues(alpha: 0.35),
            blurRadius: 28,
            spreadRadius: 2,
          ),
        ],
      ),
      child: ClipOval(
        child: hasPhoto
            ? CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => _centerFallback(size),
              )
            : _centerFallback(size),
      ),
    );
  }

  Widget _centerFallback(double size) {
    return Container(
      color: SeeUColors.accentSoft,
      alignment: Alignment.center,
      child: Icon(PhosphorIconsFill.user,
          size: size * 0.42, color: SeeUColors.accent),
    );
  }

  /// Единственный контрол скана в режиме радара: «Пуск» на паузе, «Пауза» во
  /// время поиска. Дублирующей верхней кнопки в этом состоянии нет.
  Widget _buildScanControlBig(bool paused) {
    final filled = paused; // «Пуск» — акцентная заливка; «Пауза» — outline.
    return Tappable.scaled(
      onTap: _bluetoothOn ? _toggleScan : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
        decoration: BoxDecoration(
          color: filled ? SeeUColors.accent : context.seeuColors.surface,
          borderRadius: BorderRadius.circular(SeeURadii.pill),
          border: filled
              ? null
              : Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.5), width: 1.2),
          boxShadow: filled
              ? [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.4),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ]
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              paused ? PhosphorIconsBold.play : PhosphorIconsBold.pause,
              color: filled ? Colors.white : SeeUColors.accent,
              size: 20,
            ),
            const SizedBox(width: 6),
            Text(
              paused ? 'Пуск' : 'Пауза',
              style: SeeUTypography.subtitle.copyWith(
                  color: filled ? Colors.white : SeeUColors.accent,
                  fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }

  // ── UI Components ──────────────────────────────────────────────────────────

  Widget _buildMyBraceletPill(SeeUThemeColors c) {
    final user = ref.watch(authProvider).user;
    final scanEnabled = user?.scanEnabled ?? true;
    final hasDevice = (user?.devicePublicId ?? '').isNotEmpty;

    return GestureDetector(
      onTap: () {
        HapticFeedback.lightImpact();
        _showMyBraceletSheet();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: (scanEnabled && hasDevice) ? c.accentSoft : c.surface2,
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
                color: (scanEnabled && hasDevice)
                    ? SeeUColors.accent
                    : c.ink3,
                boxShadow: (scanEnabled && hasDevice)
                    ? [BoxShadow(color: SeeUColors.accent, blurRadius: 8)]
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              hasDevice
                  ? (scanEnabled ? 'браслет вкл' : 'браслет выкл')
                  : 'нет браслета',
              style: SeeUTypography.caption.copyWith(
                  fontWeight: FontWeight.w600,
                  color: (scanEnabled && hasDevice)
                      ? SeeUColors.accent
                      : c.ink3),
            ),
          ],
        ),
      ),
    );
  }

  void _showMyBraceletSheet() {
    showSeeUBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) =>
          MyBraceletSheet(devicesMap: Map.unmodifiable(_devicesMap)),
    );
  }

}
