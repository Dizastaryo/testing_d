import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/providers/spark_provider.dart';

/// Список людей, отправивших тебе Spark 🔥 (виден только владельцу профиля).
class SparkSendersSheet extends ConsumerWidget {
  const SparkSendersSheet({super.key});

  static Future<void> show(BuildContext context) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const SparkSendersSheet(),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final c = context.seeuColors;
    final async = ref.watch(sparkSendersProvider);

    return Container(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.7,
      ),
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(0, 12, 0, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
              color: c.line,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Кто отправил Spark',
            style: SeeUTypography.displayXS.copyWith(color: c.ink),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: async.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(40),
                child: CircularProgressIndicator(),
              ),
              error: (e, _) => Padding(
                padding: const EdgeInsets.all(40),
                child: Text('Не удалось загрузить',
                    style: SeeUTypography.body.copyWith(color: c.ink3)),
              ),
              data: (senders) {
                if (senders.isEmpty) {
                  return Padding(
                    padding: const EdgeInsets.all(40),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(PhosphorIcons.fire(), size: 48, color: c.ink4),
                        const SizedBox(height: 12),
                        Text('Пока никто не отправил Spark',
                            textAlign: TextAlign.center,
                            style:
                                SeeUTypography.body.copyWith(color: c.ink3)),
                      ],
                    ),
                  );
                }
                return ListView.builder(
                  shrinkWrap: true,
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  itemCount: senders.length,
                  itemBuilder: (ctx, i) {
                    final s = senders[i];
                    return ListTile(
                      onTap: () {
                        Navigator.of(context).pop();
                        context.push('/profile/${s.username}');
                      },
                      leading: CircleAvatar(
                        radius: 22,
                        backgroundColor: c.surface2,
                        backgroundImage: s.avatarUrl.isNotEmpty
                            ? CachedNetworkImageProvider(s.avatarUrl)
                            : null,
                        child: s.avatarUrl.isEmpty
                            ? Text(
                                s.username.isNotEmpty
                                    ? s.username[0].toUpperCase()
                                    : '?',
                                style: TextStyle(
                                    color: c.ink3,
                                    fontWeight: FontWeight.w600),
                              )
                            : null,
                      ),
                      title: Text(
                        s.fullName.isNotEmpty ? s.fullName : s.username,
                        style: SeeUTypography.body.copyWith(
                            color: c.ink, fontWeight: FontWeight.w600),
                      ),
                      subtitle: Text('@${s.username}',
                          style:
                              SeeUTypography.caption.copyWith(color: c.ink3)),
                    );
                  },
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
