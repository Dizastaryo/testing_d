import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:timeago/timeago.dart' as timeago;

import 'core/theme/app_theme.dart';
import 'core/providers/auth_provider.dart';
import 'core/providers/theme_provider.dart';
import 'widgets/main_scaffold.dart';
import 'features/auth/login_screen.dart';
import 'features/auth/register_screen.dart';
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
import 'features/chat/chat_list_screen.dart';
import 'features/chat/chat_screen.dart';
import 'features/settings/settings_screen.dart';
import 'features/onboarding/onboarding_screen.dart';
import 'features/notifications/notifications_screen.dart';
import 'features/reels/reels_screen.dart';
import 'features/videos/watch_screen.dart';
import 'features/library/library_screen.dart';
import 'features/services/services_screen.dart';

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
  late final GoRouter _router;

  @override
  void initState() {
    super.initState();
    _router = GoRouter(
      initialLocation: '/login',
      redirect: (context, state) {
        final authState = ref.read(authProvider);
        // While initial token check is in progress, don't redirect
        if (authState.isLoading) return null;
        final isAuth = authState.isAuthenticated;
        final loc = state.matchedLocation;
        // /register redirects to /login (phone auth handles registration)
        if (loc == '/register') return '/login';
        final isAuthRoute = loc == '/login';
        if (!isAuth && !isAuthRoute) return '/login';
        if (isAuth && isAuthRoute) return '/feed';
        return null;
      },
      routes: [
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
              path: '/chat',
              pageBuilder: (_, __) => const CupertinoPage(
                child: ChatListScreen(),
              ),
              routes: [
                GoRoute(
                  path: ':chatId',
                  pageBuilder: (context, state) => CupertinoPage(
                    child: ChatScreen(
                      chatId: state.pathParameters['chatId']!,
                    ),
                  ),
                ),
              ],
            ),
            GoRoute(
              path: '/scanner',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ScannerScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/reels',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ReelsScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/services',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const ServicesScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/watch',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const WatchScreen(),
                transitionsBuilder: _fadeTransition,
              ),
            ),
            GoRoute(
              path: '/files',
              pageBuilder: (_, __) => CustomTransitionPage(
                child: const LibraryScreen(),
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
                ),
              ),
              routes: [
                GoRoute(
                  path: 'comments',
                  pageBuilder: (context, state) => CupertinoPage(
                    child: CommentsScreen(
                      postId: state.pathParameters['id']!,
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
              path: '/settings',
              pageBuilder: (_, __) => const CupertinoPage(
                child: SettingsScreen(),
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

  static Widget _fadeTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return FadeTransition(opacity: animation, child: child);
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
    );
  }
}
