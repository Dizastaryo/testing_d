import 'package:cached_network_image/cached_network_image.dart';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/sbor.dart';

// ─── Provider ────────────────────────────────────────────────────

final _requestsProvider =
    FutureProvider.autoDispose.family<List<SborJoinRequest>, String>((ref, sborId) async {
  final api = ref.read(apiClientProvider);
  final r = await api.get(ApiEndpoints.sborRequests(sborId));
  final raw = r.data is Map && r.data.containsKey('data') ? r.data['data'] : r.data;
  final list = raw as List<dynamic>? ?? [];
  return list
      .map((e) => SborJoinRequest.fromJson(e as Map<String, dynamic>))
      .toList();
});

// ─── Screen ──────────────────────────────────────────────────────

class SborRequestsScreen extends ConsumerStatefulWidget {
  final String sborId;
  const SborRequestsScreen({super.key, required this.sborId});

  @override
  ConsumerState<SborRequestsScreen> createState() => _SborRequestsScreenState();
}

class _SborRequestsScreenState extends ConsumerState<SborRequestsScreen> {
  List<SborJoinRequest>? _requests;
  final Set<String> _loading = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final async = ref.read(_requestsProvider(widget.sborId));
      if (async.hasValue) setState(() => _requests = async.value!);
    });
  }

  Future<void> _refresh() async {
    final fresh = await ref.refresh(_requestsProvider(widget.sborId).future);
    if (mounted) setState(() => _requests = fresh);
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final async = ref.watch(_requestsProvider(widget.sborId));

    // Sync provider data into local list on first load.
    if (_requests == null && async.hasValue) {
      _requests = async.value!;
    }

    final count = _requests?.length;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            // ── Custom header ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 14),
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => context.pop(),
                    child: Container(
                      width: 36, height: 36,
                      decoration: BoxDecoration(
                        color: c.surface,
                        shape: BoxShape.circle,
                        boxShadow: SeeUShadows.sm,
                      ),
                      child: Icon(
                        PhosphorIcons.caretLeft(PhosphorIconsStyle.bold),
                        size: 16, color: c.ink,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          count != null ? 'Заявки ($count)' : 'Заявки',
                          style: TextStyle(
                            fontFamily: 'Fraunces',
                            fontSize: 22, fontWeight: FontWeight.w500,
                            letterSpacing: -0.2, height: 1.1, color: c.ink,
                          ),
                        ),
                        Text(
                          'запросы на вступление',
                          style: TextStyle(fontSize: 12, color: c.ink3),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            // ── Body ───────────────────────────────────────────────
            Expanded(
              child: _requests == null
                  ? async.when(
                      loading: () => const SeeURequestListSkeleton(),
                      error: (e, _) => Center(
                        child: Text('Ошибка: $e', style: TextStyle(color: c.ink2)),
                      ),
                      data: (_) => const SeeURequestListSkeleton(),
                    )
                  : _buildList(c, _requests!),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildList(SeeUThemeColors c, List<SborJoinRequest> requests) {
    if (requests.isEmpty) {
      return RefreshIndicator(
        onRefresh: _refresh,
        color: SeeUColors.accent,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: 400,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72, height: 72,
                    decoration: BoxDecoration(
                      color: c.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(PhosphorIcons.usersThree(), size: 34, color: c.ink4),
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Нет новых заявок',
                    style: TextStyle(
                      fontSize: 16, fontWeight: FontWeight.w600, color: c.ink,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Как только кто-то попросится — увидишь здесь',
                    style: TextStyle(fontSize: 13, color: c.ink3),
                    textAlign: TextAlign.center,
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _refresh,
      color: SeeUColors.accent,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 4, 16, 32),
        itemCount: requests.length,
        separatorBuilder: (_, __) => const SizedBox(height: 12),
        itemBuilder: (context, i) => _RequestCard(
          request: requests[i],
          isLoading: _loading.contains(requests[i].id),
          onApprove: () => _approve(requests[i]),
          onReject: () => _reject(requests[i]),
        ),
      ),
    );
  }

  Future<void> _approve(SborJoinRequest req) async {
    if (_loading.contains(req.id)) return;
    // Optimistic: remove immediately.
    setState(() {
      _loading.add(req.id);
      _requests = _requests?.where((r) => r.id != req.id).toList();
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.approveSborRequest(widget.sborId, req.id));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${req.fullName} принят')),
      );
    } on DioException catch (e) {
      // Roll back.
      if (!mounted) return;
      setState(() => _requests = [req, ...?_requests]);
      final msg = e.response?.data?['error'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Не удалось принять заявку')),
      );
    } finally {
      if (mounted) setState(() => _loading.remove(req.id));
    }
  }

  Future<void> _reject(SborJoinRequest req) async {
    if (_loading.contains(req.id)) return;
    // Optimistic: remove immediately.
    setState(() {
      _loading.add(req.id);
      _requests = _requests?.where((r) => r.id != req.id).toList();
    });
    try {
      final api = ref.read(apiClientProvider);
      await api.post(ApiEndpoints.rejectSborRequest(widget.sborId, req.id));
    } on DioException catch (e) {
      // Roll back.
      if (!mounted) return;
      setState(() => _requests = [req, ...?_requests]);
      final msg = e.response?.data?['error'] as String?;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg ?? 'Не удалось отклонить заявку')),
      );
    } finally {
      if (mounted) setState(() => _loading.remove(req.id));
    }
  }
}

class _RequestCard extends StatelessWidget {
  final SborJoinRequest request;
  final bool isLoading;
  final VoidCallback onApprove;
  final VoidCallback onReject;

  const _RequestCard({
    required this.request,
    required this.isLoading,
    required this.onApprove,
    required this.onReject,
  });

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    final name = request.fullName.isNotEmpty ? request.fullName : request.username;
    final initials = name.isNotEmpty ? name[0].toUpperCase() : '?';
    final seed = name.isNotEmpty ? (name.codeUnitAt(0) + name.length) % SeeUColors.avatarPalettes.length : 0;
    final pal = SeeUColors.avatarPalettes[seed];

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: Row(
        children: [
          // Avatar
          Container(
            width: 46, height: 46,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: request.avatarUrl.isEmpty
                  ? LinearGradient(colors: pal)
                  : null,
            ),
            child: request.avatarUrl.isNotEmpty
                ? ClipOval(
                    child: CachedNetworkImage(
                      imageUrl: request.avatarUrl,
                      fit: BoxFit.cover,
                      errorWidget: (_, __, ___) => _InitialsAvatar(initials: initials, pal: pal),
                    ),
                  )
                : Center(
                    child: Text(
                      initials,
                      style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                        fontSize: 18,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: 12),
          // Info
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  name,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600, color: c.ink,
                  ),
                ),
                if (request.username.isNotEmpty) ...[
                  const SizedBox(height: 1),
                  Text(
                    '@${request.username}',
                    style: TextStyle(fontSize: 12, color: c.ink3),
                  ),
                ],
                if (request.message.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    request.message,
                    style: TextStyle(fontSize: 13, color: c.ink2, height: 1.35),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(width: 10),
          // Actions
          if (isLoading)
            const SizedBox(
              width: 24, height: 24,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Reject
                GestureDetector(
                  onTap: onReject,
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: SeeUColors.error.withValues(alpha: 0.10),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.x(PhosphorIconsStyle.bold),
                      size: 16, color: SeeUColors.error,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                // Approve
                GestureDetector(
                  onTap: onApprove,
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      color: SeeUColors.success.withValues(alpha: 0.12),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      PhosphorIcons.check(PhosphorIconsStyle.bold),
                      size: 16, color: SeeUColors.success,
                    ),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _InitialsAvatar extends StatelessWidget {
  final String initials;
  final List<Color> pal;
  const _InitialsAvatar({required this.initials, required this.pal});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: pal),
        shape: BoxShape.circle,
      ),
      child: Center(
        child: Text(
          initials,
          style: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.w600, fontSize: 18,
          ),
        ),
      ),
    );
  }
}
