import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/providers/auth_provider.dart';

/// Привязка браслета SeeU к аккаунту.
/// Юзер вводит серийный номер с коробки браслета (напр. «SEEU_000001»)
/// или сканирует QR-код (seeu://bind/SEEU_XXXXXX).
/// POST /users/me/device { serial_number }
class ChipSetupScreen extends ConsumerStatefulWidget {
  /// Серийник из ссылки `seeu://bind/SEEU_xxxx` (QR из админки). Подставляется
  /// в поле, но привязку всё равно подтверждает человек — сканирование чужого
  /// QR не должно молча привязывать браслет.
  final String? initialSerial;

  const ChipSetupScreen({super.key, this.initialSerial});

  @override
  ConsumerState<ChipSetupScreen> createState() => _ChipSetupScreenState();
}

class _ChipSetupScreenState extends ConsumerState<ChipSetupScreen> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialSerial != null) _ctrl.text = widget.initialSerial!;
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _bindSerial(String serial) async {
    if (serial.isEmpty || _busy) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.myDevice, data: {'serial_number': serial});
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      showSeeUSnackBar(context, 'Браслет «$serial» привязан',
          tone: SeeUTone.success);
      context.pop();
    } on DioException catch (e) {
      if (!mounted) return;
      final code = e.response?.statusCode;
      showSeeUSnackBar(
        context,
        code == 409
            ? 'Этот браслет уже привязан к другому аккаунту'
            : code == 404
                ? 'Браслет не найден — проверьте серийный номер'
                : 'Не удалось привязать: ${apiErrorMessage(e)}',
        tone: SeeUTone.danger,
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _bind() {
    _bindSerial(_ctrl.text.trim());
  }

  Future<void> _unbind() async {
    if (_busy) return;
    final ok = await showSeeUConfirm(
      context,
      title: 'Отвязать браслет?',
      message: 'Сканер перестанет показывать вас другим. '
          'Сможете привязать его снова в любой момент.',
      confirmLabel: 'Отвязать',
      destructive: true,
      icon: PhosphorIcons.linkBreak(),
    );
    if (!ok || !mounted) return;
    setState(() => _busy = true);
    try {
      final api = ref.read(apiClientProvider);
      await api.delete(ApiEndpoints.myDevice);
      await ref.read(authProvider.notifier).reloadMe();
      if (!mounted) return;
      showSeeUSnackBar(context, 'Браслет отвязан', tone: SeeUTone.success);
    } on DioException catch (e) {
      if (!mounted) return;
      showSeeUSnackBar(context, 'Ошибка: ${apiErrorMessage(e)}',
          tone: SeeUTone.danger);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _openQRScanner() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => _QRScanPage(onSerial: (serial) {
          Navigator.of(context).pop();
          _bindSerial(serial);
        }),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final user = ref.watch(authProvider).user;
    final currentSerial = user?.devicePublicId ?? '';
    final hasChip = currentSerial.isNotEmpty;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: Column(
        children: [
          SeeUGlassBar(
            titleText: 'Браслет SeeU',
            kicker: 'ЧИП',
            leading: Tappable.scaled(
              onTap: () => context.pop(),
              scaleFactor: 0.9,
              child: SizedBox(
                width: 40,
                height: 40,
                child:
                    Icon(PhosphorIcons.caretLeft(), size: 22, color: c.ink),
              ),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Текущий браслет
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(SeeURadii.medium),
                border: Border.all(color: c.line, width: 0.5),
              ),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: hasChip
                          ? SeeUColors.accent.withValues(alpha: 0.12)
                          : c.surface2,
                      borderRadius: BorderRadius.circular(SeeURadii.small),
                    ),
                    child: Icon(
                      PhosphorIcons.bluetoothConnected(),
                      color: hasChip ? SeeUColors.accent : c.ink3,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(hasChip ? 'ПРИВЯЗАН' : 'НЕ ПРИВЯЗАН',
                            style: SeeUTypography.kicker.copyWith(
                                color:
                                    hasChip ? SeeUColors.accent : c.ink3)),
                        const SizedBox(height: 2),
                        Text(
                          hasChip
                              ? currentSerial
                              : 'Отсканируйте QR или введите номер',
                          style: (hasChip
                                  ? SeeUTypography.mono
                                  : SeeUTypography.body)
                              .copyWith(
                            fontWeight: FontWeight.w600,
                            color: c.ink,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (hasChip)
                    Tappable.faded(
                      onTap: _busy ? null : _unbind,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 7),
                        decoration: BoxDecoration(
                          color: SeeUColors.error.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                        ),
                        child: Text(
                          'Отвязать',
                          style: SeeUTypography.caption.copyWith(
                            color: SeeUColors.error,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // QR сканер — главный CTA
            SeeUButton(
              label: 'Сканировать QR-код',
              icon: PhosphorIcons.qrCode(),
              onTap: _busy ? null : _openQRScanner,
            ),
            const SizedBox(height: 8),
            Center(
              child: Text('Наведите камеру на QR с коробки браслета',
                  style: SeeUTypography.caption.copyWith(color: c.ink3)),
            ),
            const SizedBox(height: 24),

            // Разделитель "или вручную"
            Row(
              children: [
                Expanded(child: Divider(color: c.line)),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Text('или вручную',
                      style: SeeUTypography.caption.copyWith(color: c.ink3)),
                ),
                Expanded(child: Divider(color: c.line)),
              ],
            ),
            const SizedBox(height: 16),

            Text(hasChip ? 'Сменить браслет' : 'Привязать браслет',
                style: SeeUTypography.subtitle
                    .copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(
              'Введите серийный номер с наклейки на коробке браслета.',
              style: SeeUTypography.caption.copyWith(color: c.ink2, height: 1.4),
            ),
            const SizedBox(height: 16),

            SeeUInput(
              controller: _ctrl,
              autocorrect: false,
              hintText: 'SEEU_000001',
              prefix: Icon(PhosphorIcons.hash(), color: c.ink3),
              onSubmitted: (_) => _bind(),
            ),
            const SizedBox(height: 12),
            SeeUButton(
              label: hasChip ? 'Привязать новый' : 'Привязать',
              isLoading: _busy,
              onTap: _busy ? null : _bind,
            ),

            const SizedBox(height: 32),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: c.surface2,
                borderRadius: BorderRadius.circular(SeeURadii.small),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(PhosphorIcons.info(), size: 18, color: c.ink3),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'После привязки сканер других пользователей увидит вас рядом. '
                      'К одному аккаунту — один браслет; при смене старый освобождается.',
                      style: SeeUTypography.caption
                          .copyWith(color: c.ink2, height: 1.4),
                    ),
                  ),
                ],
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
}

// ── QR Scanner Page ──────────────────────────────────────────────────────────

class _QRScanPage extends StatefulWidget {
  final void Function(String serial) onSerial;
  const _QRScanPage({required this.onSerial});

  @override
  State<_QRScanPage> createState() => _QRScanPageState();
}

class _QRScanPageState extends State<_QRScanPage> {
  final MobileScannerController _scannerCtrl = MobileScannerController(
    detectionSpeed: DetectionSpeed.normal,
    facing: CameraFacing.back,
  );
  bool _handled = false;

  @override
  void dispose() {
    _scannerCtrl.dispose();
    super.dispose();
  }

  void _onDetect(BarcodeCapture capture) {
    if (_handled) return;
    for (final barcode in capture.barcodes) {
      final raw = barcode.rawValue;
      if (raw == null) continue;

      // Expected format: seeu://bind/SEEU_XXXXXX — serial_number is generated
      // backend-side as SEEU_ + lowercase hex (uuid.New()), and the DB lookup
      // is case-sensitive, so this must be passed through unchanged.
      String? serial;
      if (raw.startsWith('seeu://bind/')) {
        serial = raw.substring('seeu://bind/'.length).trim();
      } else if (raw.toUpperCase().startsWith('SEEU_')) {
        // Fallback: plain serial number in QR
        serial = raw.trim();
      }

      if (serial != null && serial.isNotEmpty) {
        _handled = true;
        widget.onSerial(serial);
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          MobileScanner(
            controller: _scannerCtrl,
            onDetect: _onDetect,
          ),
          // Overlay with viewfinder
          Positioned.fill(
            child: CustomPaint(
              painter: _ViewfinderPainter(),
            ),
          ),
          // Top bar
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  children: [
                    SeeUGlassCircleButton(
                      icon: PhosphorIcon(PhosphorIcons.caretLeft(),
                          size: 20, color: Colors.white),
                      onTap: () => Navigator.pop(context),
                    ),
                    const Spacer(),
                    SeeUGlassCircleButton(
                      icon: PhosphorIcon(PhosphorIcons.lightning(),
                          size: 20, color: Colors.white),
                      onTap: () => _scannerCtrl.toggleTorch(),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // Bottom hint
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.only(bottom: 32),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(PhosphorIcons.qrCode(),
                        size: 28, color: Colors.white.withValues(alpha: 0.8)),
                    const SizedBox(height: 8),
                    Text(
                      'Наведите камеру на QR-код\nна коробке браслета',
                      textAlign: TextAlign.center,
                      style: SeeUTypography.body.copyWith(
                        color: Colors.white.withValues(alpha: 0.8),
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ViewfinderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final rect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 40),
      width: 260,
      height: 260,
    );

    // Dark overlay outside viewfinder
    final bgPaint = Paint()..color = Colors.black.withValues(alpha: 0.5);
    canvas.drawPath(
      Path.combine(
        PathOperation.difference,
        Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height)),
        Path()..addRRect(RRect.fromRectAndRadius(rect, const Radius.circular(16))),
      ),
      bgPaint,
    );

    // Corner brackets
    const cornerLen = 32.0;
    const cornerR = 16.0;
    final paint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.top + cornerLen)
        ..lineTo(rect.left, rect.top + cornerR)
        ..quadraticBezierTo(rect.left, rect.top, rect.left + cornerR, rect.top)
        ..lineTo(rect.left + cornerLen, rect.top),
      paint,
    );
    // Top-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - cornerLen, rect.top)
        ..lineTo(rect.right - cornerR, rect.top)
        ..quadraticBezierTo(rect.right, rect.top, rect.right, rect.top + cornerR)
        ..lineTo(rect.right, rect.top + cornerLen),
      paint,
    );
    // Bottom-left
    canvas.drawPath(
      Path()
        ..moveTo(rect.left, rect.bottom - cornerLen)
        ..lineTo(rect.left, rect.bottom - cornerR)
        ..quadraticBezierTo(rect.left, rect.bottom, rect.left + cornerR, rect.bottom)
        ..lineTo(rect.left + cornerLen, rect.bottom),
      paint,
    );
    // Bottom-right
    canvas.drawPath(
      Path()
        ..moveTo(rect.right - cornerLen, rect.bottom)
        ..lineTo(rect.right - cornerR, rect.bottom)
        ..quadraticBezierTo(rect.right, rect.bottom, rect.right, rect.bottom - cornerR)
        ..lineTo(rect.right, rect.bottom - cornerLen),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
