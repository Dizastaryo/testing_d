import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../core/design/design.dart';

class ServicesScreen extends StatelessWidget {
  const ServicesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'Сервисы',
                style: SeeUTypography.title.copyWith(
                  fontSize: 28,
                  color: c.ink,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Выберите, что хотите делать',
                style: SeeUTypography.body.copyWith(
                  color: c.ink2,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 32),
              Expanded(
                child: GridView.count(
                  crossAxisCount: 2,
                  mainAxisSpacing: 16,
                  crossAxisSpacing: 16,
                  childAspectRatio: 1.0,
                  children: [
                    _ServiceCard(
                      icon: Icons.music_note_rounded,
                      title: 'Музыка',
                      subtitle: 'Слушайте треки',
                      gradient: const [Color(0xFFFF6B6B), Color(0xFFFF8E53)],
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showComingSoon(context, 'Музыка');
                      },
                    ),
                    _ServiceCard(
                      icon: Icons.play_circle_fill_rounded,
                      title: 'Видео',
                      subtitle: 'Блоги и кино',
                      gradient: const [Color(0xFF667EEA), Color(0xFF764BA2)],
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showComingSoon(context, 'Видео');
                      },
                    ),
                    _ServiceCard(
                      icon: Icons.menu_book_rounded,
                      title: 'Библиотека',
                      subtitle: 'Книги и файлы',
                      gradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
                      onTap: () {
                        HapticFeedback.lightImpact();
                        _showComingSoon(context, 'Библиотека');
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showComingSoon(BuildContext context, String service) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('$service — скоро будет доступно'),
        backgroundColor: SeeUColors.accent,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 2),
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: gradient,
          ),
          boxShadow: [
            BoxShadow(
              color: gradient[0].withValues(alpha: 0.3),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.white, size: 28),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.8),
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
