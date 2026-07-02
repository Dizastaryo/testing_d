import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import '../../core/design/design.dart';
import '../../core/models/post.dart';
import '../feed/widgets/post_card.dart';

/// A scrollable feed of posts (like main feed), opened from profile grid.
/// Scrolls to [initialIndex] on open.
class ProfilePostsFeed extends ConsumerStatefulWidget {
  final List<Post> posts;
  final int initialIndex;

  const ProfilePostsFeed({
    super.key,
    required this.posts,
    required this.initialIndex,
  });

  @override
  ConsumerState<ProfilePostsFeed> createState() => _ProfilePostsFeedState();
}

class _ProfilePostsFeedState extends ConsumerState<ProfilePostsFeed> {
  late ScrollController _scrollController;

  @override
  void initState() {
    super.initState();
    _scrollController = ScrollController();
    // Scroll to the tapped post after frame renders
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToIndex(widget.initialIndex);
    });
  }

  void _scrollToIndex(int index) {
    // Approximate: each PostCard is ~500px tall. Jump close, then user scrolls.
    final offset = index * 520.0;
    if (_scrollController.hasClients) {
      _scrollController.jumpTo(
        offset.clamp(0.0, _scrollController.position.maxScrollExtent),
      );
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    // Матовая шапка плавает над лентой (blur), контент скроллит под ней —
    // верхний отступ = высота статус-бара + бар.
    final topInset = MediaQuery.of(context).padding.top + 56;
    return Scaffold(
      backgroundColor: c.bg,
      extendBodyBehindAppBar: true,
      body: Stack(
        children: [
          ListView.builder(
            controller: _scrollController,
            padding: EdgeInsets.only(top: topInset, bottom: 100),
            itemCount: widget.posts.length,
            itemBuilder: (context, index) {
              return PostCard(post: widget.posts[index]);
            },
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: SeeUGlassBar(
              kicker: 'Профиль',
              titleText: 'Публикации',
              leading: Tappable(
                onTap: () => Navigator.of(context).pop(),
                child: SizedBox(
                  width: 44,
                  height: 44,
                  child: Icon(PhosphorIconsRegular.arrowLeft,
                      size: 20, color: c.ink),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
