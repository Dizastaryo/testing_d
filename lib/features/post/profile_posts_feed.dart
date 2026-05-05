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
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.bg,
        elevation: 0,
        scrolledUnderElevation: 0,
        title: Text('Публикации', style: SeeUTypography.subtitle),
        leading: IconButton(
          icon: Icon(PhosphorIcons.arrowLeft(), size: 22, color: c.ink),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: widget.posts.length,
        itemBuilder: (context, index) {
          return PostCard(post: widget.posts[index]);
        },
      ),
    );
  }
}
