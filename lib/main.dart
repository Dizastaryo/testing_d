import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/design/tokens.dart';
import 'core/theme/app_theme.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'widgets/main_scaffold.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
import 'features/auth/splash_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/explore/explore_screen.dart';
import 'features/post/post_detail_screen.dart';
import 'features/post/create_post_screen.dart';
import 'features/post/comments_screen.dart';
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
import 'features/settings/follow_requests_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'core/providers/reels_provider.dart';
import 'features/explore/publication_viewer.dart';
import 'features/videos/video_detail_screen.dart';
import 'features/videos/video_upload_screen.dart';
import 'features/videos/watch_screen.dart';
import 'features/library/file_detail_screen.dart';
import 'features/library/library_screen.dart';
import 'features/music/music_screen.dart';
import 'features/music/playlist_detail_screen.dart';
import 'features/services/services_screen.dart';
import 'features/stories/text_story_compose_screen.dart';
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
  timeago.setLocaleMessages('ru', timeago.RuMessages());
  timeago.setDefaultLocale('ru');
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
  ));
  runApp(const ProviderScope(child: SeeUApp()));
}

class _StoryCreateCameraWrapper extends StatelessWidget {
  const _StoryCreateCameraWrapper();
  @override
  Widget build(BuildContext context) {
    return CameraScreen(
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
  // Ключ передаётся в GoRouter и в CallListener, чтобы тот мог пушить
  // полноэкранные маршруты без Navigator.of(context) — CallListener
  // находится в MaterialApp.builder выше навигатора, поэтому context
  // не имеет NavigatorState-предка и стандартный подход падает тихо.
  final _navigatorKey = GlobalKey<NavigatorState>();
  late final GoRouter _router;

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
        // While initial token check is in progress, don't redirect
        if (authState.isLoading) return null;
        final isAuth = authState.isAuthenticated;
        final loc = state.matchedLocation;
        // splash сама себя перенаправит когда отыграет cinematic-анимацию
        if (loc == '/splash') return null;
        // /register redirects to /login (phone auth handles registration)
        if (loc == '/register') return '/login';
        final isAuthRoute = loc == '/login';
        if (!isAuth && !isAuthRoute) return '/login';
        if (isAuth && isAuthRoute) return '/feed';
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
        GoRoute(
          path: '/watch',
          pageBuilder: (_, __) => const CupertinoPage(child: WatchScreen()),
        ),
        GoRoute(
          path: '/music',
          pageBuilder: (_, __) => const CupertinoPage(child: MusicScreen()),
        ),
        GoRoute(
          path: '/playlist/:id',
          pageBuilder: (_, state) => CupertinoPage(
            child: PlaylistDetailScreen(playlistId: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/videos/upload',
          pageBuilder: (_, __) => const CupertinoPage(child: VideoUploadScreen()),
        ),
        GoRoute(
          path: '/videos/:id',
          pageBuilder: (_, state) => CupertinoPage(
            child: VideoDetailScreen(id: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/files',
          pageBuilder: (_, __) => const CupertinoPage(child: LibraryScreen()),
        ),
        GoRoute(
          path: '/files/:id',
          pageBuilder: (_, state) => CupertinoPage(
            child: FileDetailScreen(id: state.pathParameters['id']!),
          ),
        ),
        GoRoute(
          path: '/sbory',
          pageBuilder: (_, __) => const CupertinoPage(child: SboryScreen()),
        ),
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
        // ── ShellRoute with bottom nav ──
        ShellRoute(
          builder: (context, state, child) => MainScaffold(child: child),
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
            GoRoute(
              path: '/scanner',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ScannerScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            // Vertical-swipe viewer for any publication. Replaces the old
            // /reels route — every post (photo, photo collection, video) is
            // a «рилс» in this product, so one viewer covers all of them.
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
            GoRoute(
              path: '/post/create',
              pageBuilder: (_, __) => const CupertinoPage(
                child: CreatePostScreen(),
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
              path: '/story/create',
              pageBuilder: (_, __) => const CupertinoPage(
                child: _StoryCreateCameraWrapper(),
              ),
            ),
            GoRoute(
              path: '/story/create-text',
              pageBuilder: (_, __) => const CupertinoPage(
                child: TextStoryComposeScreen(),
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
              pageBuilder: (_, __) => const CupertinoPage(
                child: ChipSetupScreen(),
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
          ],
        ),
      ],
    );
  }

  /// Shared-axis transition (horizontal): входящий экран лёгко сдвигается
  /// справа + fade-in, исходящий — слева + fade-out. Замена тупого
  /// FadeTransition'а — даёт ощущение «единого потока» между bottom-nav
  /// сценами и стандартный «push»-feel при `context.push`. Easing —
  /// easeInOutCubic для согласованности с `SeeUMotion.smooth`.
  /// Shared-axis style transition между route'ами bottom-nav'а. Слайд + fade
  /// одновременно — feels как «слой улетает влево, новый приходит справа».
  /// Offset 0.10 = ~10% ширины экрана, чуть больше прежних 6% для более
  /// заметного motion. Curve — `SeeUMotion.smooth` (Curves.easeOutCubic),
  /// унифицировано с tokens.dart.
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
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider, (previous, next) {
      if (previous?.isAuthenticated != next.isAuthenticated) {
        _router.refresh();
      }
    });

    final themeMode = ref.watch(themeProvider);

    return MaterialApp.router(
      title: 'SeeU',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      routerConfig: _router,
      // CallListener должен сидеть выше навигатора, чтобы при incoming WS-event'е
      // открывать полноэкранный CallScreen поверх любого роута.
      builder: (context, child) => CallListener(
        navigatorKey: _navigatorKey,
        child: child ?? const SizedBox(),
      ),
    );
  }
}
