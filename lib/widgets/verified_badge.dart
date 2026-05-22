import 'package:flutter/material.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

/// PROFILE-5: голубая verified-галочка для подтверждённых аккаунтов.
/// Renders inline (вписывается в row с username). Размер настраивается через
/// `size`, дефолт 14 — для compact-контекстов (chat-tile, comment-row).
/// Для profile-header передавайте 18-20.
class VerifiedBadge extends StatelessWidget {
  final double size;
  const VerifiedBadge({super.key, this.size = 14});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Container(
        width: size,
        height: size,
        decoration: const BoxDecoration(
          color: Color(0xFF1DA1F2),
          shape: BoxShape.circle,
        ),
        child: Icon(
          PhosphorIcons.check(PhosphorIconsStyle.bold),
          size: size * 0.7,
          color: Colors.white,
        ),
      ),
    );
  }
}
