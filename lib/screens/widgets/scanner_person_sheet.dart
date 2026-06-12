import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/api/api_client.dart';
import '../../core/design/design.dart';
import '../../core/providers/scanner_provider.dart';
import '../../models/ble_device_model.dart';
import '../../services/user_resolver.dart';

class ScannerResolvedEntry {
  final BleDeviceModel device;
  final ResolvedDevice resolved;
  const ScannerResolvedEntry({required this.device, required this.resolved});
}

class ScannerPersonSheet extends ConsumerStatefulWidget {
  final String emoji;
  final String alias;
  final String distance;
  final bool isOnline;
  final int rssi;
  /// publicIDHex браслета — используется для API лайка.
  final String deviceHash;
  final bool initialLiked;

  const ScannerPersonSheet({
    super.key,
    required this.emoji,
    required this.alias,
    required this.distance,
    required this.isOnline,
    required this.rssi,
    required this.deviceHash,
    this.initialLiked = false,
  });

  @override
  ConsumerState<ScannerPersonSheet> createState() => _ScannerPersonSheetState();
}

class _ScannerPersonSheetState extends ConsumerState<ScannerPersonSheet> {
  late bool _liked;
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _liked = widget.initialLiked;
  }

  Future<void> _toggleLike() async {
    if (_loading) return;
    HapticFeedback.mediumImpact();
    setState(() => _loading = true);
    final api = ref.read(apiClientProvider);
    final success = _liked
        ? await removeScannerLike(api, widget.deviceHash)
        : await postScannerLike(api, widget.deviceHash);
    if (mounted) {
      setState(() {
        if (success) _liked = !_liked;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36, height: 4,
            margin: const EdgeInsets.symmetric(vertical: 12),
            decoration: BoxDecoration(
              color: SeeUColors.textQuaternary, borderRadius: BorderRadius.circular(99)),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 32),
            child: Column(
              children: [
                Container(
                  width: 84, height: 84,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle, color: SeeUColors.surface2,
                    border: Border.all(color: SeeUColors.borderSubtle)),
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
                      TextSpan(text: 'рядом', style: TextStyle(
                        color: SeeUColors.accent, fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: SeeUColors.surface2,
                    borderRadius: BorderRadius.circular(SeeURadii.medium)),
                  child: Row(children: [
                    _stat('Дистанция', widget.distance),
                    _stat('Сигнал', '${widget.rssi} dBm'),
                    _stat('Статус', widget.isOnline ? 'онлайн' : 'офлайн'),
                  ]),
                ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: SeeUColors.accentSoft, borderRadius: BorderRadius.circular(14)),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(PhosphorIconsRegular.shield, size: 18, color: SeeUColors.accent),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'Это псевдоним. Настоящий аккаунт скрыт. Вы можете только лайкнуть — и если вам ответят взаимно, появится возможность написать.',
                          style: TextStyle(fontSize: 12, color: SeeUColors.textSecondary, height: 1.45),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                Row(children: [
                  Expanded(child: GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: SeeUColors.surface2, borderRadius: BorderRadius.circular(16)),
                      child: Center(child: Text('Закрыть',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: SeeUColors.textSecondary))),
                    ),
                  )),
                  const SizedBox(width: 10),
                  Expanded(flex: 2, child: GestureDetector(
                    onTap: _loading ? null : _toggleLike,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 52,
                      decoration: BoxDecoration(
                        color: _liked ? SeeUColors.like : SeeUColors.surface2,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: _liked ? [BoxShadow(
                          color: SeeUColors.like.withValues(alpha: 0.3), blurRadius: 16, offset: const Offset(0, 6))] : null,
                      ),
                      child: _loading
                          ? const Center(child: SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)))
                          : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                              Icon(_liked ? Icons.favorite_rounded : Icons.favorite_border_rounded,
                                size: 18, color: _liked ? Colors.white : SeeUColors.textSecondary),
                              const SizedBox(width: 8),
                              Text(_liked ? 'Лайк поставлен' : 'Поставить лайк',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600,
                                  color: _liked ? Colors.white : SeeUColors.textSecondary)),
                            ]),
                    ),
                  )),
                ]),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _stat(String label, String value) {
    return Expanded(child: Column(children: [
      Text(value, style: SeeUTypography.displayS),
      const SizedBox(height: 2),
      Text(label.toUpperCase(), style: SeeUTypography.monoLabel.copyWith(fontSize: 10)),
    ]));
  }
}
