import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/api/api_client.dart' show networkOnlineProvider;
import 'core/audio/audio_handler.dart';
import 'core/config/server_config.dart';
import 'features/video/video_mini_player.dart';
import 'core/design/tokens.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'core/services/deep_link_service.dart';
import 'widgets/main_scaffold.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/post/post_detail_screen.dart';
import 'features/post/comments_screen.dart';
import 'features/post/wave_compose_screen.dart';
import 'features/camera/camera_screen.dart';
import 'features/profile/profile_screen.dart';
import 'features/profile/edit_profile_screen.dart';
import 'features/profile/followers_screen.dart';
import 'features/profile/following_screen.dart';
import 'screens/scanner_screen.dart';
import 'features/calls/call_listener.dart';
import 'features/calls/call_history_screen.dart';
import 'features/chat/chat_create_group_screen.dart';
import 'features/chat/chat_list_screen.dart';
import 'features/chat/chat_members_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/settings/blocked_users_screen.dart';
import 'features/settings/chip_setup_screen.dart';
import 'features/settings/scan_profile_screen.dart';
import 'features/card/card_editor_screen.dart';
import 'features/card/card_audience_screen.dart';
import 'features/access/access_list_screen.dart';
import 'features/access/contacts_match_screen.dart';
import 'features/nfc/nfc_scan_screen.dart';
import 'features/nfc/pair_prompts_screen.dart';
import 'features/settings/follow_requests_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/onboarding/complete_profile_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'core/providers/content_feed_provider.dart';
import 'features/explore/publication_viewer.dart';
import 'features/library/category_detail_screen.dart';
import 'features/library/collection_detail_screen.dart';
import 'features/library/discover_screen.dart';
import 'features/library/file_detail_screen.dart';
import 'features/library/library_profile_screen.dart';
import 'features/library/offline_library_screen.dart';
import 'features/library/reading_room_screen.dart';
import 'features/library/shelf_screen.dart';
import 'core/models/audio_track.dart' show AudioTrack;
import 'core/models/file_item.dart' show FileCategory;
import 'features/library/reading_leaderboard_screen.dart';
import 'features/music/music_screen.dart';
import 'features/music/player_screen.dart';
import 'features/music/music_upload_screen.dart';
import 'features/music/music_search_screen.dart';
import 'features/music/category_screen.dart';
import 'features/music/my_audio_screen.dart';
import 'features/music/playlist_detail_screen.dart';
import 'features/music/track_detail_screen.dart';
import 'features/services/services_screen.dart';
import 'features/post/publish_success_screen.dart';
import 'features/sbory/sbory_screen.dart';
import 'features/sbory/sbor_detail_screen.dart';
import 'features/sbory/sbor_create_screen.dart';
import 'features/sbory/sbor_edit_screen.dart';
import 'features/sbory/sbor_requests_screen.dart';
import 'features/sbory/sbor_chat_screen.dart';
import 'features/chat/room_screen.dart';
import 'features/chat/room_create_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await ServerConfig.init();
  timeago.setLocaleMessages('ru', timeago.RuMessages());
  timeago.setDefaultLocale('ru');
  await initializeDateFormatting('ru');
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  // Must run before ProviderScope so AudioService.handler is ready when
  // audioPlayerServiceProvider is first read. Never let an init failure abort
  // startup (it would crash main() before runApp → black screen on launch):
  // degrade gracefully so the app still renders without background audio.
  try {
    await initAudioHandler();
  } catch (e, st) {
    debugPrint('[main] initAudioHandler failed, continuing without it: $e\n$st');
  }
  runApp(const ProviderScope(child: SeeUApp()));
}

class _StoryCreateCameraWrapper extends StatelessWidget {
  const _StoryCreateCameraWrapper();
  @override
  Widget build(BuildContext context) {
    return CameraScreen(
      storyMode: true,
      onClose: () => context.pop(),
    );
  }
}

class _PostCreateCameraWrapper extends StatelessWidget {
  /// Звук, принесённый из Аудиотеки кнопкой «Взять в видео».
  final AudioTrack? initialTrack;

  const _PostCreateCameraWrapper({this.initialTrack});

  @override
  Widget build(BuildContext context) {
    return CameraScreen(
      storyMode: false,
      initialTrack: initialTrack,
      onClose: () => context.pop(),
    );
  }
}

class SeeUApp extends ConsumerStatefulWidget {
  const SeeUApp({super.key});

  @override
  ConsumerState<SeeUApp> createState() => _SeeUAppState();
}

class _SeeUAppState extends ConsumerState<SeeUApp> {
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter _router;
  late final DeepLinkService _deepLinks;

  /// Готовы ли открывать пришедшую ссылку: пользователь вошёл и уже заполнил
  /// профиль. Иначе redirect всё равно увёл бы его на /login или
  /// /complete-profile, а ссылка потерялась бы.
  bool _canNavigate() {
    final auth = ref.read(authProvider);
    return auth.isAuthenticated &&
        (auth.user?.fullName.trim().isNotEmpty ?? false);
  }

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      navigatorKey: _navigatorKey,
      initialLocation: '/splash',
      errorBuilder: (context, state) => Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.warning(), size: 56, color: Colors.grey),
              const SizedBox(height: 16),
              const Text('Страница не найдена',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Text(state.uri.toString(),
                  style: const TextStyle(fontSize: 13, color: Colors.grey)),
              const SizedBox(height: 24),
              TextButton(
                onPressed: () => context.go('/feed'),
                child: const Text('На главную'),
              ),
            ],
          ),
        ),
      ),
      redirect: (context, state) {
        final authState = ref.read(authProvider);
        if (authState.isLoading) return null;
        final isAuth = authState.isAuthenticated;
        final loc = state.matchedLocation;
        if (loc == '/splash') return null;
        if (loc == '/register') return '/login';
        final isAuthRoute = loc == '/login';
        if (!isAuth && !isAuthRoute) return '/login';
        if (isAuth && isAuthRoute) return '/feed';
        // New accounts get an auto-generated username and empty full_name
        // (see AuthService.VerifyOTP) — force profile completion before
        // anything else. fullName-empty is durable (re-checked from
        // /users/me on every launch), unlike the one-shot isNewUser flag
        // from the verify-otp response.
        final needsProfile =
            isAuth && (authState.user?.fullName.trim().isEmpty ?? false);
        if (needsProfile && loc != '/complete-profile') return '/complete-profile';
        if (!needsProfile && loc == '/complete-profile') return '/feed';
        return null;
      },
      routes: [
        GoRoute(
          path: '/splash',
          pageBuilder: (_, __) => CustomTransitionPage(
            child: const SplashScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/onboarding',
          pageBuilder: (_, __) => CustomTransitionPage(
            child: const OnboardingScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/complete-profile',
          pageBuilder: (_, __) => CustomTransitionPage(
            child: const CompleteProfileScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/login',
          pageBuilder: (_, __) => CustomTransitionPage(
            child: const LoginScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        GoRoute(
          path: '/register',
          pageBuilder: (_, __) => CustomTransitionPage(
            child: const RegisterScreen(),
            transitionsBuilder: _fadeTransition,
          ),
        ),
        // ── Top-level fullscreen routes (no bottom nav) ──
        GoRoute(
          path: '/chat',
          pageBuilder: (_, __) => const CupertinoPage(child: ChatListScreen()),
          routes: [
            GoRoute(
              path: 'new-group',
              pageBuilder: (_, __) => const CupertinoPage(child: ChatCreateGroupScreen()),
            ),
            GoRoute(
              path: 'calls',
              pageBuilder: (_, __) => const CupertinoPage(child: CallHistoryScreen()),
            ),
            GoRoute(
              path: ':chatId',
              pageBuilder: (_, state) => CupertinoPage(
                child: ChatScreen(chatId: state.pathParameters['chatId']!),
              ),
              routes: [
                GoRoute(
                  path: 'members',
                  pageBuilder: (_, state) => CupertinoPage(
                    child: ChatMembersScreen(chatId: state.pathParameters['chatId']!),
                  ),
                ),
              ],
            ),
          ],
        ),
        GoRoute(
          path: '/room/create',
          pageBuilder: (_, __) => const CupertinoPage(child: RoomCreateScreen()),
        ),
        GoRoute(
          path: '/room/:roomId',
          pageBuilder: (_, state) => CupertinoPage(
            child: RoomScreen(roomId: state.pathParameters['roomId']!),
          ),
        ),
        // Библиотечные под-экраны (/files/:id, /collection/:id,
        // /library/offline, /library/category, /reading/leaderboard) ПЕРЕЕХАЛИ
        // внутрь ShellRoute — иначе при открытии книги/категории/скачанного
        // нижнее библиотечное меню исчезало (экраны были fullscreen). Теперь
        // они держат 4-таб меню Библиотеки (см. _isLibrary в main_scaffold).
        GoRoute(
          path: '/sbory/create',
          pageBuilder: (_, __) => const CupertinoPage(child: SborCreateScreen()),
        ),
        GoRoute(
          path: '/sbory/:id',
          pageBuilder: (_, state) => CupertinoPage(
            child: SborDetailScreen(sborId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/sbory/:id/edit',
          pageBuilder: (_, state) => CupertinoPage(
            child: SborEditScreen(sborId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/sbory/:id/requests',
          pageBuilder: (_, state) => CupertinoPage(
            child: SborRequestsScreen(sborId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/sbory/:id/chat',
          pageBuilder: (_, state) => CupertinoPage(
            child: SborChatScreen(
              chatId: state.uri.queryParameters['chatId'] ?? state.pathParameters['id']!,
              sborId: state.pathParameters['id']!,
              sborTitle: state.uri.queryParameters['title'] ?? 'Сбор',
              memberCount: int.tryParse(state.uri.queryParameters['members'] ?? '0') ?? 0,
            ),
          ),
        ),
        // ── Profile (other user) — fullscreen, no bottom nav ──
        GoRoute(
          path: '/profile/:username',
          pageBuilder: (context, state) => CupertinoPage(
            child: ProfileScreen(
              username: state.pathParameters['username'],
            ),
          ),
          routes: [
            GoRoute(
              path: 'followers',
              pageBuilder: (context, state) => CupertinoPage(
                child: FollowersScreen(
                  username: state.pathParameters['username']!,
                ),
              ),
            ),
            GoRoute(
              path: 'following',
              pageBuilder: (context, state) => CupertinoPage(
                child: FollowingScreen(
                  username: state.pathParameters['username']!,
                ),
              ),
            ),
          ],
        ),
        // ── ShellRoute with bottom nav ──
        ShellRoute(
          builder: (context, state, child) {
            final loc = state.matchedLocation;
            // Полноэкранные поверхности живут БЕЗ нижнего меню: плеер и
            // загрузка — свои контролы. Плейлист же — служебная подстраница
            // Аудиотеки и держит аудио-меню (см. _isAudio).
            //
            // Камера — тоже fullscreen, и это ГЕЙТИТСЯ ЗДЕСЬ, а не глобальным
            // bottomNavHiddenNotifier: раньше меню пряталось только на свайпе
            // из ленты (там камера — страница внутри /feed), а вход через
            // «плюсик» открывал /post/create|/story/create внутри Shell — и
            // меню оставалось видимым. Отсюда «через раз видно».
            final showTabs = !loc.startsWith('/music/player') &&
                !loc.startsWith('/music/upload') &&
                !loc.startsWith('/post/create') &&
                !loc.startsWith('/story/create');
            return MainScaffold(showTabs: showTabs, child: child);
          },
          routes: [
            GoRoute(
              path: '/feed',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const FeedScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/explore',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ExploreScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            // Поиск живёт ПРЯМО в «Интересном» одним полем — отдельного экрана
            // (и второго инпута) больше нет.
            // «Топ недели по лайкам» убит дизайном (§10) — маршрут
            // /leaderboard и его экран удалены совсем.
            GoRoute(
              path: '/scanner',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ScannerScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/view/:postId',
              pageBuilder: (_, state) {
                final typeParam = state.uri.queryParameters['type'] ?? 'all';
                final ct = typeParam == 'video' ? ContentType.video
                    : typeParam == 'photo' ? ContentType.photo
                    : ContentType.all;
                return CupertinoPage(
                  child: PublicationViewer(
                    initialPostId: state.pathParameters['postId']!,
                    contentType: ct,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/services',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ServicesScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            // ── Библиотека: 4 вкладки со своим нижним меню ──
            // Вход из «Сервисов» → Читальня; «Выйти» сверху справа возвращает
            // в «Сервисы» и вместе с ним обычное меню приложения.
            GoRoute(
              path: '/files',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ReadingRoomScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/library/discover',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const DiscoverScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/library/shelf',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ShelfScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/library/profile',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const LibraryProfileScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            // Библиотечные под-экраны — ВНУТРИ Shell, чтобы держать 4-таб меню
            // Библиотеки (книгу/категорию/скачанное открываешь — меню на месте).
            GoRoute(
              path: '/files/:id',
              pageBuilder: (_, state) => CupertinoPage(
                child: FileDetailScreen(id: state.pathParameters['id']!),
              ),
            ),
            // Подборка книг. Открывается и по ссылке от другого человека —
            // тогда она read-only и видна, только если владелец её открыл.
            GoRoute(
              path: '/collection/:id',
              pageBuilder: (_, state) => CupertinoPage(
                child: CollectionDetailScreen(
                  collectionId: state.pathParameters['id']!,
                ),
              ),
            ),
            GoRoute(
              path: '/library/offline',
              pageBuilder: (_, __) =>
                  const CupertinoPage(child: OfflineLibraryScreen()),
            ),
            GoRoute(
              path: '/library/category/:slug',
              pageBuilder: (_, state) {
                // Happy path: category passed via extra (in-app navigation).
                // Cold-start / deep-link: extra is null → CategoryDetailScreen
                // self-resolves from the :slug param via fileCategoriesProvider.
                final cat = state.extra as FileCategory?;
                final slug = state.pathParameters['slug'] ?? '';
                return CupertinoPage(
                  child: CategoryDetailScreen(category: cat, slug: slug),
                );
              },
            ),
            GoRoute(
              path: '/reading/leaderboard',
              pageBuilder: (_, __) =>
                  const CupertinoPage(child: ReadingLeaderboardScreen()),
            ),
            GoRoute(
              path: '/sbory',
              pageBuilder: (_, __) => const CupertinoPage(child: SboryScreen()),
            ),
            GoRoute(
              path: '/profile',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ProfileScreen(),
                transitionsBuilder: _fadeTransition,
              ),
              routes: [
                GoRoute(
                  path: 'edit',
                  pageBuilder: (_, __) => const CupertinoPage(
                    child: EditProfileScreen(),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/post/create',
              // extra: AudioTrack — «Взять в видео» из Аудиотеки.
              pageBuilder: (_, state) => CupertinoPage(
                child: _PostCreateCameraWrapper(
                  initialTrack: state.extra is AudioTrack
                      ? state.extra as AudioTrack
                      : null,
                ),
              ),
            ),
            GoRoute(
              path: '/post/:id',
              pageBuilder: (context, state) => CupertinoPage(
                child: PostDetailScreen(
                  postId: state.pathParameters['id']!,
                  focusedCommentId: state.uri.queryParameters['commentId'],
                ),
              ),
              routes: [
                GoRoute(
                  path: 'comments',
                  pageBuilder: (context, state) => CupertinoPage(
                    child: CommentsScreen(
                      postId: state.pathParameters['id']!,
                      focusedCommentId: state.uri.queryParameters['commentId'],
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/publish-success',
              pageBuilder: (_, state) {
                final extra = state.extra as Map<String, dynamic>? ?? {};
                return CupertinoPage(
                  child: PublishSuccessScreen(
                    thumbnailBytes: extra['thumbnailBytes'] as Uint8List?,
                    isStory: extra['isStory'] as bool? ?? false,
                    publishedId: extra['publishedId'] as String?,
                  ),
                );
              },
            ),
            GoRoute(
              path: '/story/create',
              pageBuilder: (_, __) => const CupertinoPage(
                child: _StoryCreateCameraWrapper(),
              ),
            ),
            GoRoute(
              path: '/wave/create',
              pageBuilder: (_, __) => const CupertinoPage(
                child: WaveComposeScreen(),
              ),
            ),
            GoRoute(
              path: '/settings',
              pageBuilder: (_, __) => const CupertinoPage(
                child: SettingsScreen(),
              ),
            ),
            GoRoute(
              path: '/settings/blocked',
              pageBuilder: (_, __) => const CupertinoPage(
                child: BlockedUsersScreen(),
              ),
            ),
            GoRoute(
              path: '/settings/chip',
              // ?serial=… приходит из ссылки seeu://bind/SEEU_xxxx (QR из
              // админки) — подставляется в поле, привязку подтверждает человек.
              pageBuilder: (_, state) => CupertinoPage(
                child: ChipSetupScreen(
                  initialSerial: state.uri.queryParameters['serial'],
                ),
              ),
            ),
            GoRoute(
              path: '/settings/scan-profile',
              pageBuilder: (_, __) => const CupertinoPage(
                child: ScanProfileScreen(),
              ),
            ),
            GoRoute(
              path: '/settings/card',
              pageBuilder: (_, __) => const CupertinoPage(
                child: CardEditorScreen(),
              ),
            ),
            GoRoute(
              path: '/settings/card/audience',
              pageBuilder: (_, __) => const CupertinoPage(
                child: CardAudienceScreen(),
              ),
            ),
            GoRoute(
              path: '/access/list',
              pageBuilder: (_, __) => const CupertinoPage(
                child: AccessListScreen(),
              ),
            ),
            GoRoute(
              path: '/access/contacts',
              pageBuilder: (_, __) => const CupertinoPage(
                child: ContactsMatchScreen(),
              ),
            ),
            GoRoute(
              path: '/nfc/scan',
              pageBuilder: (_, __) => const CupertinoPage(
                child: NfcScanScreen(),
              ),
            ),
            GoRoute(
              path: '/pairs/prompts',
              pageBuilder: (_, __) => const CupertinoPage(
                child: PairPromptsScreen(),
              ),
            ),
            GoRoute(
              path: '/settings/follow-requests',
              pageBuilder: (_, __) => const CupertinoPage(
                child: FollowRequestsScreen(),
              ),
            ),
            GoRoute(
              path: '/notifications',
              pageBuilder: (_, __) => const CupertinoPage(
                child: NotificationsScreen(),
              ),
            ),
            // ── Music routes — inside shell so mini-player persists ──
            GoRoute(
              path: '/music',
              pageBuilder: (_, __) => const CupertinoPage(child: MusicScreen()),
            ),
            // Плеер во весь экран — вкладки сервиса здесь только мешали бы.
            GoRoute(
              path: '/music/player',
              pageBuilder: (_, __) => const CupertinoPage(
                fullscreenDialog: true,
                child: PlayerScreen(),
              ),
            ),
            GoRoute(
              path: '/music/upload',
              // extra: AudioTrack — отклонённый трек отправляют повторно,
              // поля уже заполнены.
              pageBuilder: (_, state) => CupertinoPage(
                child: MusicUploadScreen(
                  editing: state.extra is AudioTrack
                      ? state.extra as AudioTrack
                      : null,
                ),
              ),
            ),
            GoRoute(
              path: '/music/mine',
              // ?tab=uploads — например, после отправки трека на модерацию.
              pageBuilder: (_, state) => CupertinoPage(
                child: MyAudioScreen(
                  initialTab: state.uri.queryParameters['tab'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/music/search',
              pageBuilder: (_, state) => CupertinoPage(
                child: MusicSearchScreen(
                  initialCategory:
                      state.uri.queryParameters['category'] ?? '',
                  initialQuery: state.uri.queryParameters['q'] ?? '',
                ),
              ),
            ),
            GoRoute(
              path: '/music/category/:category',
              pageBuilder: (_, state) => CupertinoPage(
                child: CategoryScreen(
                    categoryId: state.pathParameters['category'] ?? 'music'),
              ),
            ),
            GoRoute(
              path: '/music/track/:id',
              pageBuilder: (_, state) => CupertinoPage(
                child: TrackDetailScreen(trackId: state.pathParameters['id']!),
              ),
            ),
            GoRoute(
              path: '/playlist/:id',
              pageBuilder: (_, state) => CupertinoPage(
                child: PlaylistDetailScreen(playlistId: state.pathParameters['id']!),
              ),
            ),
          ],
        ),
      ],
    );

    // Слушаем seeu://-ссылки: и ту, которой приложение открыли с нуля, и те,
    // что приходят на уже запущенное.
    _deepLinks = DeepLinkService(
      router: _router,
      isAuthenticated: _canNavigate,
    );
    _deepLinks.start();
  }

  static Widget _fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    const curve = SeeUMotion.smooth;
    final inOffset = Tween<Offset>(
      begin: const Offset(0.10, 0),
      end: Offset.zero,
    ).chain(CurveTween(curve: curve)).animate(animation);
    final outOffset = Tween<Offset>(
      begin: Offset.zero,
      end: const Offset(-0.10, 0),
    ).chain(CurveTween(curve: curve)).animate(secondaryAnimation);
    final inOpacity = CurvedAnimation(parent: animation, curve: curve);
    return SlideTransition(
      position: outOffset,
      child: SlideTransition(
        position: inOffset,
        child: FadeTransition(opacity: inOpacity, child: child),
      ),
    );
  }

  @override
  void dispose() {
    _deepLinks.dispose();
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      final authChanged = previous?.isAuthenticated != next.isAuthenticated;
      // Profile completion also changes where `redirect` sends the user
      // (needsProfile flips false), even though isAuthenticated stays true —
      // without this, the app stays stuck on /complete-profile after saving.
      final profileCompleted =
          (previous?.user?.fullName.trim().isEmpty ?? false) &&
              !(next.user?.fullName.trim().isEmpty ?? false);
      if (authChanged || profileCompleted) {
        _router.refresh();
        // Ссылка, пришедшая до входа, ждала здесь — открываем её после того,
        // как redirect отработает и человек окажется на своём экране.
        if (_canNavigate()) {
          WidgetsBinding.instance.addPostFrameCallback(
            (_) => _deepLinks.flushPending(),
          );
        }
      }
    });

    final themeMode = ref.watch(themeProvider);
    final isOnline = ref.watch(networkOnlineProvider);

    // Set the static brightness bridge BEFORE MaterialApp builds so theme
    // toggles apply on the same frame (no 1-frame stale-color lag).
    // The MaterialApp.builder below re-confirms it from the fully-resolved Theme.
    SeeUColors.themeBrightness = switch (themeMode) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      ThemeMode.system =>
        WidgetsBinding.instance.platformDispatcher.platformBrightness,
    };

    return MaterialApp.router(
      title: 'SeeU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: _router,
      builder: (context, child) {
        // Bridge the resolved theme brightness to the static SeeUColors
        // accessors so all files reading SeeUColors.background / textPrimary
        // etc. directly render in the correct theme on every theme change.
        SeeUColors.themeBrightness = Theme.of(context).brightness;
        return CallListener(
          navigatorKey: _navigatorKey,
          child: VideoMiniPlayerOverlay(
            navigatorKey: _navigatorKey,
            child: _NetworkBanner(
              isOnline: isOnline,
              child: child ?? const SizedBox(),
            ),
          ),
        );
      },
    );
  }
}

class _NetworkBanner extends StatefulWidget {
  final bool isOnline;
  final Widget child;

  const _NetworkBanner({required this.isOnline, required this.child});

  @override
  State<_NetworkBanner> createState() => _NetworkBannerState();
}

class _NetworkBannerState extends State<_NetworkBanner> {
  bool _showRestored = false;
  Timer? _restoredTimer;

  @override
  void didUpdateWidget(_NetworkBanner old) {
    super.didUpdateWidget(old);
    if (!old.isOnline && widget.isOnline) {
      _restoredTimer?.cancel();
      setState(() => _showRestored = true);
      _restoredTimer = Timer(const Duration(milliseconds: 1800), () {
        if (mounted) setState(() => _showRestored = false);
      });
    }
  }

  @override
  void dispose() {
    _restoredTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final showOffline = !widget.isOnline;
    final showGreen = _showRestored && widget.isOnline;

    return Column(
      children: [
        AnimatedContainer(
          duration: const Duration(milliseconds: 300),
          height: (showOffline || showGreen) ? 28 : 0,
          color: showGreen ? const Color(0xFF34C759) : SeeUColors.error,
          child: OverflowBox(
            maxHeight: 28,
            child: (showOffline || showGreen)
                ? Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        showGreen
                            ? PhosphorIconsBold.wifiHigh
                            : PhosphorIconsBold.wifiSlash,
                        size: 12,
                        color: Colors.white,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        showGreen ? 'Соединение восстановлено' : 'Нет соединения',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  )
                : const SizedBox.shrink(),
          ),
        ),
        Expanded(child: widget.child),
      ],
    );
  }
}
