import 'dart:async';
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
import '../core/services/logger.dart';
import '../models/ble_device_model.dart';
import '../services/account_session.dart';
import '../services/user_resolver.dart';
import 'widgets/my_bracelet_sheet.dart';
import '../features/spark/spark_send_sheet.dart';
import '../features/card/card_style.dart';
import '../features/card/card_portrait.dart';
import '../features/card/card_detail_sheet.dart';

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

/// Намерение пользователя: должен ли идти скан. Живёт ВНЕ State намеренно —
/// экран пересоздаётся при каждом заходе на /scanner, и состояние внутри State
/// не переживает уход на другую вкладку. По умолчанию true: первый заход в
/// Сканер сразу ищет людей рядом; дальше уважается последний выбор.
bool _scanEnabledByUser = true;

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
  // Negative-cache: хэши без карточки, чтобы не долбить сервер бесконечно на
  // каждом срабатывании дебаунса. TTL — сбрасывается при рестарте скана.
  final Set<String> _noCardHashes = {};
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
    // Уважаем прошлый выбор: экран пересоздаётся при каждом заходе на
    // /scanner, и безусловный _startScan() включал скан заново, даже если его
    // выключили перед уходом (кнопка «Остановить» появлялась сама).
    if (_scanEnabledByUser) _startScan();
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
      // Останавливаем непрерывный BLE-скан в фоне — иначе он сажает батарею
      // (и на iOS всё равно деградирует системой).
      FlutterBluePlus.stopScan();
    } else if (state == AppLifecycleState.resumed) {
      _resumeAnimations();
      // Возобновляем скан при возврате — но только если пользователь его не
      // выключал сам.
      if (mounted &&
          _scanEnabledByUser &&
          _bluetoothOn &&
          !FlutterBluePlus.isScanningNow) {
        _startScan();
      }
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
    // Real signed-in user's device ids (NOT the legacy AccountSession mock
    // that _resolver.resolve() below still compares against) — used to make
    // sure our own bracelet never lists itself as "someone nearby".
    final me = ref.read(authProvider).user;
    final myPublicId = me?.devicePublicId?.toUpperCase() ?? '';
    final myPrivateId = me?.devicePrivateId?.toUpperCase() ?? '';
    for (final d in _devicesMap.values) {
      final resolved = _resolver.resolve(d);
      final packetId = d.seeuPacket?.idHex.toUpperCase() ?? '';
      final isMine = packetId.isNotEmpty &&
          ((myPublicId.isNotEmpty && packetId == myPublicId) ||
              (myPrivateId.isNotEmpty && packetId == myPrivateId));
      if (isMine) continue;
      if (resolved.relationship == Relationship.unknown &&
          resolved.hasValidPacket &&
          resolved.mode == 0xFF) {
        continue;
      }
      if (!resolved.hasValidPacket) continue;
      final profile = d.seeuPacket != null
          ? _scanProfiles[d.seeuPacket!.idHex]
          : null;
      // Показываем только заполненные карточки (у карточки есть фото — оно
      // обязательно). Незаполненная карточка не показывается рядом.
      if (profile == null || !profile.isFilled) continue;
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
    // adapterState.first может эмитить после ухода с экрана (iOS init CBCentral
    // unknown→poweredOn) — без guard'а setState падал после dispose.
    if (!mounted) return;
    _devicesMap.clear();
    _scanProfiles.clear(); // не тащим карточки прошлого скана
    _noCardHashes.clear();
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
        // Пропускаем уже резолвнутые И те, что сервер уже пометил «без
        // карточки» (negative cache) — иначе устройство без карточки
        // перезапрашивалось на каждом тике таймера бесконечно.
        if (hex != null &&
            hex.isNotEmpty &&
            !_scanProfiles.containsKey(hex) &&
            !_noCardHashes.contains(hex)) {
          hashes.add(hex);
        }
      }
      if (hashes.isEmpty) return;
      try {
        final api = ref.read(apiClientProvider);
        final resolved = await resolveScanProfiles(api, hashes);
        if (!mounted) return;
        setState(() {
          _scanProfiles.addAll(resolved);
          // Хэши, которые сервер НЕ вернул → без карточки, в negative-cache.
          for (final h in hashes) {
            if (!resolved.containsKey(h)) _noCardHashes.add(h);
          }
          _devicesMapVersion++;
        });
      } catch (e, st) {
        // Раньше ошибка резолва проглатывалась молча — отладка в поле была
        // невозможна (пользователь видел «ищем» с нулём карточек).
        appLog.error('[scanner] resolve failed', e, st);
      }
    });
  }

  Future<void> _stopScan() async {
    await FlutterBluePlus.stopScan();
  }

  void _toggleScan() {
    HapticFeedback.lightImpact();
    if (_isScanning) {
      // Явное намерение пользователя — запоминаем, чтобы возврат на экран
      // не включил скан заново.
      _scanEnabledByUser = false;
      _stopScan();
    } else {
      _scanEnabledByUser = true;
      _startScan();
    }
  }

  // ── Actions ────────────────────────────────────────────────────────────────

  void _sendSpark(ScanProfile p) {
    HapticFeedback.mediumImpact();
    SparkSendSheet.show(
      context,
      ref,
      receiverId: p.ownerId,
      receiverName: p.displayName,
      proofDeviceHash: p.deviceHash,
      avatarUrl: p.photoUrl,
    );
  }

  void _openBraceletPage() {
    HapticFeedback.lightImpact();
    // Отдельная полноэкранная страница браслета. Передаём карту BLE-устройств —
    // GATT-режим требует живого скана рядом.
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => BraceletScreen(devicesMap: Map.unmodifiable(_devicesMap)),
    ));
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final entries = _sortedDevices;
    final user = ref.watch(authProvider).user;
    final hasPeople = entries.isNotEmpty;

    // Фото «я» в центре радара — фото карточки, иначе аватар профиля.
    final mePhoto = (user?.scanPhotoUrl.isNotEmpty ?? false)
        ? user!.scanPhotoUrl
        : (user?.avatarUrl ?? '');

    return Scaffold(
      backgroundColor: c.bg,
      body: Stack(
        children: [
          // Верхнее коралловое свечение (radial 50% 60% at 50% 0).
          Positioned(
            top: -60,
            left: 0,
            right: 0,
            height: 300,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment.topCenter,
                    radius: 0.95,
                    colors: [
                      c.accentSoft,
                      c.accentSoft.withValues(alpha: 0),
                    ],
                    stops: const [0.0, 0.72],
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            bottom: false,
            child: Column(
              children: [
                _buildTopBar(c, hasPeople, entries.length),
                Expanded(
                  // Bluetooth выключен — отдельное состояние с явным текстом,
                  // а не молчаливо-задизейбленная кнопка (тупик без объяснения).
                  child: !_bluetoothOn
                      ? _buildBluetoothOff(c)
                      : hasPeople
                          ? _buildFeed(entries)
                          : (_isScanning
                              ? _buildSearching(c, mePhoto)
                              : _buildPaused(c, mePhoto)),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar(SeeUThemeColors c, bool hasPeople, int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 6, 20, 8),
      child: Row(
        children: [
          // Бренд-wordmark «SeeU» слева — как в шапках Ленты и Интересного.
          const SeeUWordmark(),
          if (hasPeople) ...[
            const SizedBox(width: 10),
            _nearbyPill(c, count),
          ],
          const Spacer(),
          _roundIconButton(
            c,
            PhosphorIcons.identificationCard(),
            () {
              HapticFeedback.lightImpact();
              context.push('/settings/card'); // студия «Моя карточка»
            },
          ),
          const SizedBox(width: 9),
          _roundIconButton(
            c,
            PhosphorIcons.usersThree(),
            () {
              HapticFeedback.lightImpact();
              context.push('/settings/card/audience'); // кто рядом смотрел
            },
          ),
          const SizedBox(width: 9),
          _roundIconButton(c, PhosphorIcons.broadcast(), _openBraceletPage),
        ],
      ),
    );
  }

  /// Пилюля «N рядом» с дышащей коралловой точкой.
  Widget _nearbyPill(SeeUThemeColors c, int count) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF161310).withValues(alpha: 0.10),
            blurRadius: 18,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const _BreathingDot(),
          const SizedBox(width: 6),
          Text(
            '$count рядом',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: c.ink,
            ),
          ),
        ],
      ),
    );
  }

  /// Круглая белая кнопка 44px с коралловой иконкой.
  Widget _roundIconButton(SeeUThemeColors c, IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: c.surface,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF161310).withValues(alpha: 0.10),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        alignment: Alignment.center,
        child: Icon(icon, size: 20, color: SeeUColors.accent),
      ),
    );
  }

  // ── Лента карточек ─────────────────────────────────────────────────────────

  Widget _buildFeed(List<ScannerResolvedEntry> entries) {
    return ListView.builder(
      padding: EdgeInsets.fromLTRB(18, 4, 18, 28 + context.bottomBarInset),
      itemCount: entries.length,
      itemBuilder: (_, i) => Padding(
        padding: const EdgeInsets.only(bottom: 14),
        child: _personCard(entries[i], i),
      ),
    );
  }

  /// Карточка человека рядом. Тап открывает CardDetailSheet (это фиксирует
  /// просмотр — view-event, симметрия видимости; раньше тап не делал ничего,
  /// и ни один просмотр не регистрировался). Spark — по кнопке справа.
  Widget _personCard(ScannerResolvedEntry entry, int index) {
    final p = entry.scanProfile!;
    final t = templateFromStyle(p.style);

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
        onTap: () => CardDetailSheet.show(context, ref, p),
        behavior: HitTestBehavior.opaque,
        child: CardPortrait(
          template: t,
          photoUrl: p.photoUrl,
          nickname: p.displayName,
          text: p.text,
          trailing: SparkHaloButton(onTap: () => _sendSpark(p)),
        ),
      ),
    );
  }

  // ── Состояние: идёт поиск ──────────────────────────────────────────────────

  Widget _buildSearching(SeeUThemeColors c, String mePhoto) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      child: Column(
        children: [
          SizedBox(
            width: 280,
            height: 280,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Мягкое свечение под кольцами.
                Container(
                  width: 230,
                  height: 230,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        SeeUColors.accent.withValues(alpha: 0.12),
                        SeeUColors.accent.withValues(alpha: 0),
                      ],
                      stops: const [0.0, 0.68],
                    ),
                  ),
                ),
                const _PulseRings(),
                _radarCenterPhoto(c, mePhoto, searching: true),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Ищем, кто рядом',
            style: SeeUTypography.displayS.copyWith(fontSize: 24, color: c.ink),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: 280,
            child: Text(
              'Держи Bluetooth включённым и будь среди людей — их карточки появятся здесь сами.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink3),
            ),
          ),
          const SizedBox(height: 28),
          // Кнопка-обводка «Остановить поиск».
          GestureDetector(
            onTap: _bluetoothOn ? _toggleScan : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: SeeUColors.accent.withValues(alpha: 0.5),
                  width: 1.2,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIconsBold.stop, size: 19, color: SeeUColors.accent),
                  const SizedBox(width: 7),
                  const Text(
                    'Остановить поиск',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: SeeUColors.accent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Состояние: поиск остановлен ────────────────────────────────────────────

  /// Состояние «Bluetooth выключен» — с явным объяснением, что делать.
  Widget _buildBluetoothOff(SeeUThemeColors c) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(PhosphorIcons.bluetoothSlash(), size: 56, color: c.ink3),
            const SizedBox(height: 20),
            Text('Bluetooth выключен',
                style: SeeUTypography.displayS
                    .copyWith(fontSize: 22, color: c.ink)),
            const SizedBox(height: 10),
            Text(
              'Сканер находит людей рядом по Bluetooth. Включите Bluetooth '
              '(и разрешите геолокацию на Android), чтобы искать.',
              textAlign: TextAlign.center,
              style: SeeUTypography.body.copyWith(color: c.ink3, height: 1.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPaused(SeeUThemeColors c, String mePhoto) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 40, 24, 32),
      child: Column(
        children: [
          Opacity(
            opacity: 0.5,
            child: SizedBox(
              width: 280,
              height: 280,
              child: Stack(
                alignment: Alignment.center,
                children: [
                  _staticRing(130, c.ink3.withValues(alpha: 0.4)),
                  _staticRing(200, c.ink3.withValues(alpha: 0.25)),
                  _radarCenterPhoto(c, mePhoto, searching: false),
                ],
              ),
            ),
          ),
          const SizedBox(height: 26),
          Text(
            'Поиск остановлен',
            style: SeeUTypography.displayS.copyWith(fontSize: 24, color: c.ink),
          ),
          const SizedBox(height: 9),
          SizedBox(
            width: 290,
            child: Text(
              'Ты сейчас не сканируешь окружение. Включи снова, когда будешь среди людей.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 13.5, height: 1.5, color: c.ink3),
            ),
          ),
          const SizedBox(height: 28),
          // Коралловая кнопка «Искать рядом».
          GestureDetector(
            onTap: _bluetoothOn ? _toggleScan : null,
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 15),
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                borderRadius: BorderRadius.circular(999),
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.4),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(PhosphorIconsBold.magnifyingGlass,
                      size: 19, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Искать рядом',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _staticRing(double size, Color color) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: color, width: 2),
      ),
    );
  }

  /// Фото «я» в центре радара: белое кольцо 3px + свечение.
  Widget _radarCenterPhoto(SeeUThemeColors c, String url,
      {required bool searching}) {
    const size = 112.0;
    final photo = Container(
      width: size,
      height: size,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: c.surface,
        boxShadow: [
          searching
              ? BoxShadow(
                  color: SeeUColors.accent.withValues(alpha: 0.4),
                  blurRadius: 34,
                )
              : BoxShadow(
                  color: const Color(0xFF161310).withValues(alpha: 0.12),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
        ],
      ),
      child: ClipOval(
        child: Container(
          color: searching ? c.accentSoft : c.surface2,
          child: url.isNotEmpty
              ? CachedNetworkImage(
                  imageUrl: url,
                  fit: BoxFit.cover,
                  errorWidget: (_, __, ___) =>
                      Icon(PhosphorIcons.user(), size: 40, color: c.ink3),
                )
              : Icon(PhosphorIcons.user(), size: 40, color: c.ink3),
        ),
      ),
    );

    // На паузе фото приглушено (grayscale в дизайне).
    if (searching) return photo;
    return ColorFiltered(
      colorFilter: const ColorFilter.matrix(<double>[
        0.46, 0.35, 0.09, 0, 0, //
        0.16, 0.65, 0.09, 0, 0, //
        0.16, 0.35, 0.39, 0, 0, //
        0, 0, 0, 1, 0, //
      ]),
      child: photo,
    );
  }
}

// ─── Мелкие анимированные элементы ──────────────────────────────────────────

/// Дышащая коралловая точка в пилюле «N рядом».
class _BreathingDot extends StatefulWidget {
  const _BreathingDot();

  @override
  State<_BreathingDot> createState() => _BreathingDotState();
}

class _BreathingDotState extends State<_BreathingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        final t = Curves.easeInOut.transform(_c.value);
        return Transform.scale(
          scale: 1 + 0.05 * t,
          child: Opacity(
            opacity: 0.9 + 0.1 * t,
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: SeeUColors.accent,
                boxShadow: [
                  BoxShadow(color: SeeUColors.accent, blurRadius: 8),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// Три расходящихся кольца радара (поиск). Из дизайна: 130px, border 2px
/// rgba(255,90,60,.55), scale .35→1.75, затухание к 80%, 3.2s, сдвиг фазы 1/3.
class _PulseRings extends StatefulWidget {
  const _PulseRings();

  @override
  State<_PulseRings> createState() => _PulseRingsState();
}

class _PulseRingsState extends State<_PulseRings>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3200),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, __) {
        return Stack(
          alignment: Alignment.center,
          children: List.generate(3, (i) {
            final phase = (_c.value + i / 3) % 1.0;
            final scale = 0.35 + (1.75 - 0.35) * phase;
            // Затухание: к 80% прогресса кольцо полностью прозрачно.
            final opacity =
                (0.55 * (1 - (phase / 0.8))).clamp(0.0, 0.55).toDouble();
            return Transform.scale(
              scale: scale,
              child: Container(
                width: 130,
                height: 130,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SeeUColors.accent.withValues(alpha: opacity),
                    width: 2,
                  ),
                ),
              ),
            );
          }),
        );
      },
    );
  }
}
