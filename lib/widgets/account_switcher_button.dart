import 'package:flutter/material.dart';
import '../core/design/design.dart';
import '../data/mock_users.dart';
import '../services/account_session.dart';

class AccountSwitcherButton extends StatelessWidget {
  const AccountSwitcherButton({super.key});

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AccountSession.instance,
      builder: (context, _) {
        final user = AccountSession.instance.currentUser;
        return GestureDetector(
          onTap: () => _showSwitcher(context),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: SeeUColors.surfaceElevated,
              borderRadius: BorderRadius.circular(SeeURadii.pill),
              boxShadow: SeeUShadows.sm,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(user.avatarEmoji, style: const TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  user.name,
                  style: TextStyle(
                    fontFamily: 'Segoe UI',
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: SeeUColors.textPrimary,
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _showSwitcher(BuildContext context) {
    showSeeUBottomSheet(
      context: context,
      builder: (ctx) {
        final current = AccountSession.instance.currentUser;
        return Padding(
          padding: const EdgeInsets.only(left: 24, right: 24, bottom: 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 8),
              Text(
                'Переключить аккаунт',
                style: SeeUTypography.title,
              ),
              const SizedBox(height: 16),
              for (final user in allUsers) ...[
                _AccountTile(
                  user: user,
                  isSelected: user.id == current.id,
                  onTap: () {
                    AccountSession.instance.switchTo(user);
                    Navigator.pop(ctx);
                  },
                ),
                if (user != allUsers.last) const SizedBox(height: 8),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _AccountTile extends StatelessWidget {
  final MockUser user;
  final bool isSelected;
  final VoidCallback onTap;

  const _AccountTile({
    required this.user,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: isSelected
              ? SeeUColors.accent.withValues(alpha: 0.08)
              : SeeUColors.surfaceElevated,
          borderRadius: BorderRadius.circular(SeeURadii.small),
          border: Border.all(
            color: isSelected ? SeeUColors.accent : SeeUColors.borderSubtle,
          ),
        ),
        child: Row(
          children: [
            Text(user.avatarEmoji, style: const TextStyle(fontSize: 26)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    user.name,
                    style: SeeUTypography.subtitle.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    user.bio,
                    style: SeeUTypography.caption.copyWith(
                      color: SeeUColors.textTertiary,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            if (isSelected)
              const Icon(
                Icons.check_circle_rounded,
                color: SeeUColors.accent,
                size: 20,
              ),
          ],
        ),
      ),
    );
  }
}
