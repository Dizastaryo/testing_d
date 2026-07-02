import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:lottie/lottie.dart';

import '../../core/design/design.dart';
import '../../core/providers/spark_provider.dart';

/// Шит отправки Spark 🔥 (Фаза 3). Заменяет старый CoinGrantSheet.
/// Spark — единый сигнал тепла, без категорий. Отправляется по BLE-близости:
/// нужен [proofDeviceHash] — хэш браслета получателя, видимый в эфире.
class SparkSendSheet extends ConsumerStatefulWidget {
  final String receiverId;
  final String receiverName;
  final String? avatarUrl;
  final String proofDeviceHash;

  const SparkSendSheet({
    super.key,
    required this.receiverId,
    required this.receiverName,
    required this.proofDeviceHash,
    this.avatarUrl,
  });

  static Future<void> show(
    BuildContext context,
    WidgetRef ref, {
    required String receiverId,
    required String receiverName,
    required String proofDeviceHash,
    String? avatarUrl,
  }) {
    return showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => SparkSendSheet(
        receiverId: receiverId,
        receiverName: receiverName,
        proofDeviceHash: proofDeviceHash,
        avatarUrl: avatarUrl,
      ),
    );
  }

  @override
  ConsumerState<SparkSendSheet> createState() => _SparkSendSheetState();
}

class _SparkSendSheetState extends ConsumerState<SparkSendSheet> {
  bool _sending = false;
  bool _sent = false;
  String? _error;

  Future<void> _send() async {
    if (_sending || _sent) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await sendSpark(
        ref,
        receiverId: widget.receiverId,
        proofDeviceHash: widget.proofDeviceHash,
      );
      HapticFeedback.mediumImpact();
      if (mounted) setState(() => _sent = true);
    } on SparkError catch (e) {
      if (mounted) setState(() => _error = e.message);
    } catch (_) {
      if (mounted) setState(() => _error = 'Не удалось отправить Spark');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.seeuColors;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(24),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: colors.line,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            CircleAvatar(
              radius: 32,
              backgroundColor: colors.surface2,
              backgroundImage: (widget.avatarUrl?.isNotEmpty ?? false)
                  ? CachedNetworkImageProvider(widget.avatarUrl!)
                  : null,
              child: (widget.avatarUrl?.isEmpty ?? true)
                  ? Text(
                      widget.receiverName.isNotEmpty
                          ? widget.receiverName[0].toUpperCase()
                          : '?',
                      style: TextStyle(
                          color: colors.ink3, fontWeight: FontWeight.w600),
                    )
                  : null,
            ),
            const SizedBox(height: 12),
            Text(
              widget.receiverName,
              style: SeeUTypography.subtitle
                  .copyWith(color: colors.ink, fontWeight: FontWeight.w600),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 96,
              child: Lottie.asset(
                'assets/small flame.json',
                repeat: true,
                fit: BoxFit.contain,
              ),
            ),
            const SizedBox(height: 8),
            if (_sent) ...[
              Text(
                'Spark отправлен!',
                style: SeeUTypography.subtitle.copyWith(
                    color: SeeUColors.accent, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 20),
              _PrimaryButton(
                label: 'Готово',
                onTap: () => Navigator.of(context).pop(),
              ),
            ] else ...[
              Text(
                'Отправь Spark — тёплый сигнал тому, кто рядом.',
                textAlign: TextAlign.center,
                style: SeeUTypography.caption.copyWith(color: colors.ink3),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  textAlign: TextAlign.center,
                  style: SeeUTypography.caption.copyWith(color: SeeUColors.error),
                ),
              ],
              const SizedBox(height: 20),
              _PrimaryButton(
                label: _sending ? 'Отправка...' : 'Отправить Spark',
                onTap: _sending ? null : _send,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  const _PrimaryButton({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: enabled ? SeeUColors.accent : SeeUColors.accent.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Center(
          child: Text(
            label,
            style: const TextStyle(
                color: Colors.white, fontWeight: FontWeight.w600, fontSize: 15),
          ),
        ),
      ),
    );
  }
}
