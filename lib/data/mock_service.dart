import 'dart:math';

import '../core/models/user.dart';
import '../core/models/post.dart';
import '../core/models/story.dart';
import '../core/models/comment.dart';
import '../core/models/notification.dart';
import '../core/models/highlight.dart';

// ---------------------------------------------------------------------------
// Chat models (inline)
// ---------------------------------------------------------------------------

class ChatMessage {
  final String id;
  final String chatId;
  final String senderId;
  final String text;
  final DateTime createdAt;
  final bool isRead;

  ChatMessage({
    required this.id,
    required this.chatId,
    required this.senderId,
    required this.text,
    required this.createdAt,
    this.isRead = false,
  });

  ChatMessage copyWith({bool? isRead}) {
    return ChatMessage(
      id: id,
      chatId: chatId,
      senderId: senderId,
      text: text,
      createdAt: createdAt,
      isRead: isRead ?? this.isRead,
    );
  }
}

class Chat {
  final String id;
  final User otherUser;
  final ChatMessage? lastMessage;
  final int unreadCount;
  final DateTime updatedAt;

  Chat({
    required this.id,
    required this.otherUser,
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
  });

  Chat copyWith({
    ChatMessage? lastMessage,
    int? unreadCount,
    DateTime? updatedAt,
  }) {
    return Chat(
      id: id,
      otherUser: otherUser,
      lastMessage: lastMessage ?? this.lastMessage,
      unreadCount: unreadCount ?? this.unreadCount,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}

// ---------------------------------------------------------------------------
// MockService
// ---------------------------------------------------------------------------

class MockService {
  // Singleton
  static final MockService instance = MockService._();
  MockService._() {
    _init();
  }

  final Random _rng = Random();

  // ---- State containers ----
  late User _currentUser;
  bool _isAuthenticated = false;

  final List<User> _users = [];
  final List<Post> _posts = [];
  final List<Story> _stories = [];
  final List<Comment> _comments = [];
  final List<AppNotification> _notifications = [];
  final List<Highlight> _highlights = [];
  final List<Chat> _chats = [];
  final List<ChatMessage> _chatMessages = [];

  // Saved post IDs by current user
  final Set<String> _savedPostIds = {};

  // Following set: username of users that current user follows
  final Set<String> _followingUsernames = {};

  int _nextId = 10000;
  String _genId() => '${_nextId++}';

  // ---- Simulated delay ----
  Future<void> _delay() =>
      Future.delayed(Duration(milliseconds: 200 + _rng.nextInt(300)));

  // =========================================================================
  // INIT - populate all mock data
  // =========================================================================

  void _init() {
    final now = DateTime.now();

    // ------ Users (current + 12 others) ------
    _currentUser = User(
      id: 'me',
      username: 'aidana_s',
      fullName: 'Айдана Серикова',
      bio: 'Фотограф | Алматы | Ловлю моменты и свет',
      website: 'https://aidana-photo.kz',
      avatarUrl: 'https://i.pravatar.cc/150?img=47',
      postsCount: 34,
      followersCount: 2890,
      followingCount: 512,
      isFollowing: false,
      isPrivate: false,
      isVerified: true,
      createdAt: DateTime(2022, 5, 18),
    );
    _isAuthenticated = true;

    final otherUsers = <User>[
      // u1 - index 0
      User(
        id: 'u1',
        username: 'bekzat_n',
        fullName: 'Бекзат Нурланов',
        bio: 'Flutter/Dart разработчик | Open Source | Астана',
        website: 'https://github.com/bekzat',
        avatarUrl: 'https://i.pravatar.cc/150?img=3',
        postsCount: 112,
        followersCount: 15800,
        followingCount: 340,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2021, 3, 10),
      ),
      // u2 - index 1
      User(
        id: 'u2',
        username: 'dana_k',
        fullName: 'Дана Касымова',
        bio: 'UI/UX дизайнер | Figma & Sketch | Минимализм',
        website: 'https://dana-design.kz',
        avatarUrl: 'https://i.pravatar.cc/150?img=5',
        postsCount: 189,
        followersCount: 28700,
        followingCount: 210,
        isFollowing: false,
        isPrivate: false,
        isVerified: true,
        createdAt: DateTime(2020, 8, 22),
      ),
      // u3 - index 2
      User(
        id: 'u3',
        username: 'arman_zh',
        fullName: 'Арман Жумабеков',
        bio: 'Музыкант | Гитара, домбра и вокал | Алматы',
        avatarUrl: 'https://i.pravatar.cc/150?img=8',
        postsCount: 67,
        followersCount: 5400,
        followingCount: 430,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2022, 1, 15),
      ),
      // u4 - index 3
      User(
        id: 'u4',
        username: 'kamila_a',
        fullName: 'Камила Ахметова',
        bio: 'Стилист | Fashion-блогер | Шоурум в Астане',
        website: 'https://kamila.style',
        avatarUrl: 'https://i.pravatar.cc/150?img=9',
        postsCount: 234,
        followersCount: 47200,
        followingCount: 180,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2020, 4, 5),
      ),
      // u5 - index 4
      User(
        id: 'u5',
        username: 'nursultan_e',
        fullName: 'Нурсултан Ержанов',
        bio: 'Спортсмен | MMA | Тренер | Никогда не сдавайся',
        avatarUrl: 'https://i.pravatar.cc/150?img=11',
        postsCount: 156,
        followersCount: 31000,
        followingCount: 290,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2021, 6, 1),
      ),
      // u6 - index 5
      User(
        id: 'u6',
        username: 'zhanna_t',
        fullName: 'Жанна Токтарова',
        bio: 'Путешественница | 52 страны | Блог о travel',
        website: 'https://zhanna-travel.com',
        avatarUrl: 'https://i.pravatar.cc/150?img=16',
        postsCount: 345,
        followersCount: 68000,
        followingCount: 150,
        isFollowing: false,
        isPrivate: false,
        isVerified: true,
        createdAt: DateTime(2019, 9, 20),
      ),
      // u7 - index 6
      User(
        id: 'u7',
        username: 'timur_b',
        fullName: 'Тимур Байжанов',
        bio: 'Фуд-блогер | Рецепты | Обзоры ресторанов Алматы',
        website: 'https://timur-food.kz',
        avatarUrl: 'https://i.pravatar.cc/150?img=12',
        postsCount: 198,
        followersCount: 23400,
        followingCount: 360,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2021, 2, 14),
      ),
      // u8 - index 7
      User(
        id: 'u8',
        username: 'aliya_s',
        fullName: 'Алия Сагынбаева',
        bio: 'Художница | Акварель, масло, digital | Выставки',
        website: 'https://aliya-art.kz',
        avatarUrl: 'https://i.pravatar.cc/150?img=20',
        postsCount: 87,
        followersCount: 9200,
        followingCount: 310,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2022, 7, 10),
      ),
      // u9 - index 8
      User(
        id: 'u9',
        username: 'madina_o',
        fullName: 'Мадина Оспанова',
        bio: 'Журналист | Медиа | Подкаст "Голос степи"',
        avatarUrl: 'https://i.pravatar.cc/150?img=25',
        postsCount: 78,
        followersCount: 12600,
        followingCount: 420,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2021, 11, 3),
      ),
      // u10 - index 9
      User(
        id: 'u10',
        username: 'ruslan_tech',
        fullName: 'Руслан Ибрагимов',
        bio: 'Tech reviewer | Гаджеты и новинки | YouTube',
        avatarUrl: 'https://i.pravatar.cc/150?img=14',
        postsCount: 93,
        followersCount: 18900,
        followingCount: 275,
        isFollowing: false,
        isPrivate: true,
        isVerified: false,
        createdAt: DateTime(2022, 4, 22),
      ),
      // u11 - index 10
      User(
        id: 'u11',
        username: 'asel_yoga',
        fullName: 'Асель Каримова',
        bio: 'Йога-инструктор | Медитация | Гармония',
        avatarUrl: 'https://i.pravatar.cc/150?img=32',
        postsCount: 134,
        followersCount: 8700,
        followingCount: 490,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2022, 3, 8),
      ),
      // u12 - index 11
      User(
        id: 'u12',
        username: 'dauren_arch',
        fullName: 'Даурен Мухтаров',
        bio: 'Архитектор | Урбанистика | Алматы и Астана',
        website: 'https://dauren-arch.kz',
        avatarUrl: 'https://i.pravatar.cc/150?img=33',
        postsCount: 56,
        followersCount: 4100,
        followingCount: 310,
        isFollowing: false,
        isPrivate: false,
        isVerified: false,
        createdAt: DateTime(2023, 1, 20),
      ),
    ];

    _users.clear();
    _users.add(_currentUser);
    _users.addAll(otherUsers);

    // Mark some as followed by current user
    _followingUsernames.addAll([
      'bekzat_n',
      'dana_k',
      'arman_zh',
      'zhanna_t',
      'timur_b',
      'aliya_s',
      'asel_yoga',
    ]);

    // Update isFollowing flags in the list
    for (var i = 0; i < _users.length; i++) {
      if (_followingUsernames.contains(_users[i].username)) {
        _users[i] = _users[i].copyWith(isFollowing: true);
      }
    }

    // ------ Posts (30) ------
    _posts.clear();

    User userByIdx(int idx) => otherUsers[idx % otherUsers.length];

    _posts.addAll([
      // p1 - dana_k (дизайн)
      Post(
        id: 'p1',
        author: userByIdx(1), // dana_k
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p1/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Новый дизайн-система для финтех-стартапа. 3 месяца работы, 200+ компонентов. Горжусь результатом! #design #ux #ui #figma',
        location: 'Алматы, Казахстан',
        likesCount: 3420,
        commentsCount: 134,
        isLiked: true,
        isSaved: false,
        likedByUsername: 'bekzat_n',
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      // p2 - bekzat_n (код)
      Post(
        id: 'p2',
        author: userByIdx(0), // bekzat_n
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p2/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
        ],
        caption: 'Выпустил новый пакет для Flutter - state management без бойлерплейта. Ссылка в био! #flutter #dart #opensource #dev',
        likesCount: 2150,
        commentsCount: 187,
        isLiked: false,
        isSaved: true,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      // wave1
      Post(
        id: 'w1',
        author: userByIdx(2), // arman_zh
        media: [],
        caption: 'Кто-нибудь ещё не спит? \u{1F319}',
        likesCount: 342,
        commentsCount: 28,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(hours: 2, minutes: 30)),
        isWave: true,
        waveColorValue: 0xFF6C5CE7,
      ),
      // p3 - nursultan_e (спорт)
      Post(
        id: 'p3',
        author: userByIdx(4), // nursultan_e
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p3/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Утренняя тренировка в 6:00. Дисциплина - это свобода. Кто со мной завтра? #mma #fitness #motivation #sport',
        location: 'Fight Club Almaty',
        likesCount: 1890,
        commentsCount: 76,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'asel_yoga',
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      // p4 - aliya_s (искусство, карусель)
      Post(
        id: 'p4',
        author: userByIdx(7), // aliya_s
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p4a/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p4b/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p4c/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Новая серия акварелей "Краски Тянь-Шаня". Вдохновение - горные пейзажи сентября. Листайте! #art #watercolor #mountains #kazakhstan',
        location: 'Алматы, Казахстан',
        likesCount: 2670,
        commentsCount: 98,
        isLiked: true,
        isSaved: true,
        createdAt: now.subtract(const Duration(hours: 4)),
      ),
      // wave2
      Post(
        id: 'w2',
        author: userByIdx(6), // timur_b
        media: [],
        caption: 'Лучший кофе в городе \u2014 спорим? \u2615',
        likesCount: 567,
        commentsCount: 89,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(hours: 4, minutes: 15)),
        isWave: true,
        waveColorValue: 0xFFFF5A3C,
      ),
      // p5 - zhanna_t (путешествия)
      Post(
        id: 'p5',
        author: userByIdx(5), // zhanna_t
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p5/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
        ],
        caption: 'Чарынский каньон на рассвете. Младший брат Гранд Каньона, но красота ничуть не меньше! #charyn #kazakhstan #travel #nature',
        location: 'Чарынский каньон',
        likesCount: 7890,
        commentsCount: 312,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'dana_k',
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      // p6 - timur_b (еда)
      Post(
        id: 'p6',
        author: userByIdx(6), // timur_b
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p6/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Бешбармак по бабушкиному рецепту. Настоящий, с казы и жая. Рецепт в карусели! #food #kazakh #beshbarmak #recipe',
        location: 'Астана, Казахстан',
        likesCount: 4560,
        commentsCount: 234,
        isLiked: true,
        isSaved: true,
        likedByUsername: 'kamila_a',
        createdAt: now.subtract(const Duration(hours: 6)),
      ),
      // wave3
      Post(
        id: 'w3',
        author: userByIdx(1), // dana_k
        media: [],
        caption: 'Сегодня отличный день для прогулки \u{1F324}',
        likesCount: 234,
        commentsCount: 12,
        isLiked: true,
        isSaved: false,
        createdAt: now.subtract(const Duration(hours: 7, minutes: 45)),
        isWave: true,
        waveColorValue: 0xFF00B894,
      ),
      // p7 - arman_zh (музыка)
      Post(
        id: 'p7',
        author: userByIdx(2), // arman_zh
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p7/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
        ],
        caption: 'Акустический вечер в Barley. Играли 3 часа без перерыва. Спасибо всем, кто пришел! #music #acoustic #live #almaty',
        location: 'Barley, Алматы',
        likesCount: 890,
        commentsCount: 45,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
      // p8 - kamila_a (мода, карусель)
      Post(
        id: 'p8',
        author: userByIdx(3), // kamila_a
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p8a/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p8b/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
        ],
        caption: 'Осенний лук: оверсайз пальто + ботинки челси. Как вам? Какой образ нравится больше - 1 или 2? #fashion #style #autumn #ootd',
        location: 'Астана, Казахстан',
        likesCount: 8910,
        commentsCount: 456,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'zhanna_t',
        createdAt: now.subtract(const Duration(hours: 10)),
      ),
      // wave4
      Post(
        id: 'w4',
        author: userByIdx(3), // kamila_a
        media: [],
        caption: 'Ищу компанию на концерт в пятницу \u{1F3B5}',
        likesCount: 178,
        commentsCount: 34,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(hours: 11)),
        isWave: true,
        waveColorValue: 0xFFE17055,
      ),
      // p9 - ruslan_tech (техника)
      Post(
        id: 'p9',
        author: userByIdx(9), // ruslan_tech
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p9/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Обзор нового MacBook Pro M4 Max. Стоит ли обновляться с M2? Полное видео на канале! #tech #apple #macbook #review',
        likesCount: 3890,
        commentsCount: 267,
        isLiked: true,
        isSaved: false,
        createdAt: now.subtract(const Duration(hours: 12)),
      ),
      // p10 - asel_yoga (йога)
      Post(
        id: 'p10',
        author: userByIdx(10), // asel_yoga
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p10/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
        ],
        caption: 'Утренняя практика на берегу Иссык-Куля. Начните день с благодарности и дыхания. #yoga #morning #mindfulness #issykkul',
        location: 'Иссык-Куль, Кыргызстан',
        likesCount: 1560,
        commentsCount: 67,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'nursultan_e',
        createdAt: now.subtract(const Duration(hours: 14)),
      ),
      // wave5
      Post(
        id: 'w5',
        author: userByIdx(4), // nursultan_e
        media: [],
        caption: 'Только что закончил марафон! \u{1F3C3}\u200D\u2642\uFE0F',
        likesCount: 891,
        commentsCount: 56,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(hours: 15)),
        isWave: true,
        waveColorValue: 0xFF0984E3,
      ),
      // p11 - current user (фото, карусель)
      Post(
        id: 'p11',
        author: _currentUser,
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p11a/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p11b/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p11c/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p11d/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Портретная серия "Лица города". Проект, над которым работала 3 месяца. Алматы глазами людей. #portrait #photography #almaty #faces',
        location: 'Алматы, Казахстан',
        likesCount: 5670,
        commentsCount: 234,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'dana_k',
        createdAt: now.subtract(const Duration(hours: 18)),
      ),
      // p12 - zhanna_t (путешествие, карусель)
      Post(
        id: 'p12',
        author: userByIdx(5), // zhanna_t
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p12a/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p12b/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p12c/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
        ],
        caption: 'Кольсайские озера - жемчужина Тянь-Шаня. Сентябрь, осенние краски, тишина. Место силы. #kolsai #nature #kazakhstan #mountains',
        location: 'Кольсайские озера',
        likesCount: 11200,
        commentsCount: 456,
        isLiked: false,
        isSaved: true,
        likedByUsername: 'timur_b',
        createdAt: now.subtract(const Duration(hours: 20)),
      ),
      // p13 - madina_o (журналистика)
      Post(
        id: 'p13',
        author: userByIdx(8), // madina_o
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p13/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Новый выпуск подкаста "Голос степи" уже доступен! Говорим о современном искусстве Казахстана с @aliya_s. Ссылка в био. #podcast #media #art',
        likesCount: 1230,
        commentsCount: 56,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      // p14 - dauren_arch (архитектура)
      Post(
        id: 'p14',
        author: userByIdx(11), // dauren_arch
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p14/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
        ],
        caption: 'Хан Шатыр - шедевр Нормана Фостера. Каждый раз удивляюсь масштабу. #architecture #astana #khanShatyr #urban',
        location: 'Астана, Казахстан',
        likesCount: 2340,
        commentsCount: 89,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'dana_k',
        createdAt: now.subtract(const Duration(days: 1, hours: 2)),
      ),
      // p15 - timur_b (еда, карусель)
      Post(
        id: 'p15',
        author: userByIdx(6), // timur_b
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p15a/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p15b/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Баурсаки и курт - вкус детства. Бабушкин рецепт, который передается из поколения в поколение. Сохраняйте! #kazakh #food #traditional #baursak',
        location: 'Шымкент, Казахстан',
        likesCount: 5670,
        commentsCount: 312,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'zhanna_t',
        createdAt: now.subtract(const Duration(days: 1, hours: 5)),
      ),
      // p16 - bekzat_n (конференция)
      Post(
        id: 'p16',
        author: userByIdx(0), // bekzat_n
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p16/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'DevFest Almaty 2025. Выступил с докладом про архитектуру мобильных приложений. Спасибо организаторам и аудитории! #devfest #flutter #tech #almaty',
        location: 'Алматы, Казахстан',
        likesCount: 1780,
        commentsCount: 78,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(days: 1, hours: 8)),
      ),
      // p17 - kamila_a (стиль)
      Post(
        id: 'p17',
        author: userByIdx(3), // kamila_a
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p17/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
        ],
        caption: 'Белое платье - классика, которая никогда не выйдет из моды. Согласны? #fashion #whitedress #classic #style #minimal',
        location: 'Астана, Казахстан',
        likesCount: 12300,
        commentsCount: 567,
        isLiked: true,
        isSaved: false,
        likedByUsername: 'aliya_s',
        createdAt: now.subtract(const Duration(days: 1, hours: 12)),
      ),
      // p18 - current user (фотография)
      Post(
        id: 'p18',
        author: _currentUser,
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p18/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Закат над Алматы с Кок-Тобе. Каждый вечер - как новая картина. Никогда не надоест. #sunset #almaty #photography #koktobe',
        location: 'Кок-Тобе, Алматы',
        likesCount: 890,
        commentsCount: 45,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'zhanna_t',
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      // p19 - nursultan_e (спорт)
      Post(
        id: 'p19',
        author: userByIdx(4), // nursultan_e
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p19/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Результат за 6 месяцев. Дисциплина, правильное питание и вера в себя. Каждый может! #beforeafter #fitness #progress #mma',
        likesCount: 4560,
        commentsCount: 189,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(days: 2, hours: 4)),
      ),
      // p20 - current user (дизайн, карусель)
      Post(
        id: 'p20',
        author: _currentUser,
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p20a/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p20b/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Фотопроект "Базары Алматы". Зеленый базар глазами камеры. Цвета, лица, эмоции. #almaty #bazaar #streetphotography #project',
        location: 'Зеленый базар, Алматы',
        likesCount: 1230,
        commentsCount: 67,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'bekzat_n',
        createdAt: now.subtract(const Duration(days: 2, hours: 8)),
      ),
      // p21 - aliya_s (масло)
      Post(
        id: 'p21',
        author: userByIdx(7), // aliya_s
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p21/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
        ],
        caption: 'Масло на холсте. "Осень в Алматы". 60x80 см. Продается! Пишите в DM. #art #oilpainting #almaty #autumn #forsale',
        location: 'Алматы, Казахстан',
        likesCount: 3450,
        commentsCount: 123,
        isLiked: false,
        isSaved: true,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      // p22 - arman_zh (музыка)
      Post(
        id: 'p22',
        author: userByIdx(2), // arman_zh
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p22/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Новая песня "Жулдыз" на всех площадках! Домбра + электроника = эксперимент. Оцените! Ссылка в био. #newmusic #kazakh #dombra #single',
        likesCount: 1560,
        commentsCount: 78,
        isLiked: true,
        isSaved: false,
        createdAt: now.subtract(const Duration(days: 3, hours: 6)),
      ),
      // p23 - zhanna_t (Бишкек, карусель)
      Post(
        id: 'p23',
        author: userByIdx(5), // zhanna_t
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p23a/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p23b/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p23c/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
        ],
        caption: 'Бишкек - город контрастов. Горы прямо за углом, базары, кофейни третьей волны. Центральная Азия удивляет! #bishkek #kyrgyzstan #centralasia #travel',
        location: 'Бишкек, Кыргызстан',
        likesCount: 6780,
        commentsCount: 289,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'bekzat_n',
        createdAt: now.subtract(const Duration(days: 3, hours: 10)),
      ),
      // p24 - dana_k (рабочее место)
      Post(
        id: 'p24',
        author: userByIdx(1), // dana_k
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p24/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Рабочее место мечты. Минимализм, свет, порядок. Как выглядит ваш рабочий стол? #workspace #design #minimal #setup',
        location: 'Алматы, Казахстан',
        likesCount: 4560,
        commentsCount: 198,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'ruslan_tech',
        createdAt: now.subtract(const Duration(days: 4)),
      ),
      // p25 - ruslan_tech (сравнение)
      Post(
        id: 'p25',
        author: userByIdx(9), // ruslan_tech
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p25/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Smart-часы 2025: Apple Watch Ultra 3 vs Galaxy Watch 7 vs Pixel Watch 3. Полное сравнение. Кто победил? #smartwatch #tech #comparison',
        likesCount: 5600,
        commentsCount: 345,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(days: 4, hours: 6)),
      ),
      // p26 - current user (кофе)
      Post(
        id: 'p26',
        author: _currentUser,
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p26/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Кофе, камера и вдохновение. Идеальное утро фотографа. #photography #coffee #morning #almaty',
        location: 'Алматы, Казахстан',
        likesCount: 456,
        commentsCount: 23,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(days: 5)),
      ),
      // p27 - madina_o (интервью)
      Post(
        id: 'p27',
        author: userByIdx(8), // madina_o
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p27/800/1000',
            type: MediaType.image,
            aspectRatio: 0.8,
          ),
        ],
        caption: 'Интервью с @bekzat_n о будущем IT в Казахстане. Полная версия на YouTube. Что думаете о развитии tech-индустрии? #interview #tech #kazakhstan',
        likesCount: 2340,
        commentsCount: 112,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'madina_o',
        createdAt: now.subtract(const Duration(days: 5, hours: 8)),
      ),
      // p28 - asel_yoga (медитация)
      Post(
        id: 'p28',
        author: userByIdx(10), // asel_yoga
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p28/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Поза дерева на фоне гор. Баланс начинается изнутри. 5 минут медитации утром меняют весь день. #yoga #balance #treepose #mountains',
        location: 'Бурабай, Казахстан',
        likesCount: 1890,
        commentsCount: 78,
        isLiked: false,
        isSaved: false,
        createdAt: now.subtract(const Duration(days: 6)),
      ),
      // p29 - timur_b (ресторан)
      Post(
        id: 'p29',
        author: userByIdx(6), // timur_b
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p29a/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p29b/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p29c/800/800',
            type: MediaType.image,
            aspectRatio: 1.0,
          ),
        ],
        caption: 'Топ-3 ресторана Алматы этого месяца. Листайте! Где были? Согласны с выбором? #food #almaty #restaurants #top3 #review',
        location: 'Алматы, Казахстан',
        likesCount: 7890,
        commentsCount: 456,
        isLiked: true,
        isSaved: true,
        likedByUsername: 'kamila_a',
        createdAt: now.subtract(const Duration(days: 6, hours: 6)),
      ),
      // p30 - dauren_arch (город)
      Post(
        id: 'p30',
        author: userByIdx(11), // dauren_arch
        media: [
          PostMedia(
            url: 'https://picsum.photos/seed/seeu_p30/800/600',
            type: MediaType.image,
            aspectRatio: 1.33,
          ),
        ],
        caption: 'Старый Алматы vs Новый Алматы. Контрасты архитектуры. Что нравится больше - уют деревянных домиков или стекло небоскребов? #almaty #architecture #urban #contrast',
        location: 'Алматы, Казахстан',
        likesCount: 3210,
        commentsCount: 145,
        isLiked: false,
        isSaved: false,
        likedByUsername: 'arman_zh',
        createdAt: now.subtract(const Duration(days: 7)),
      ),
    ]);

    // Populate _savedPostIds from initial isSaved flags
    for (final p in _posts) {
      if (p.isSaved) _savedPostIds.add(p.id);
    }

    // ------ Stories (7 groups, 2-3 stories each) ------
    _stories.clear();

    // Story group builders - explicit stories with text overlays
    final storyData = <Map<String, dynamic>>[
      // Current user - 2 stories
      {'author': _currentUser, 'seed': 'st_me_1', 'text': null, 'hoursAgo': 2},
      {'author': _currentUser, 'seed': 'st_me_2', 'text': 'Новый проект!', 'hoursAgo': 5},
      // bekzat_n - 3 stories
      {'author': otherUsers[0], 'seed': 'st_bek_1', 'text': null, 'hoursAgo': 1},
      {'author': otherUsers[0], 'seed': 'st_bek_2', 'text': 'Код в 3 часа ночи', 'hoursAgo': 3},
      {'author': otherUsers[0], 'seed': 'st_bek_3', 'text': null, 'hoursAgo': 6},
      // dana_k - 2 stories
      {'author': otherUsers[1], 'seed': 'st_dan_1', 'text': 'Вдохновение', 'hoursAgo': 2},
      {'author': otherUsers[1], 'seed': 'st_dan_2', 'text': null, 'hoursAgo': 8},
      // zhanna_t - 3 stories
      {'author': otherUsers[5], 'seed': 'st_zh_1', 'text': null, 'hoursAgo': 1},
      {'author': otherUsers[5], 'seed': 'st_zh_2', 'text': 'Привет из Бишкека!', 'hoursAgo': 4},
      {'author': otherUsers[5], 'seed': 'st_zh_3', 'text': null, 'hoursAgo': 10},
      // timur_b - 2 stories
      {'author': otherUsers[6], 'seed': 'st_tim_1', 'text': 'Обед готов!', 'hoursAgo': 3},
      {'author': otherUsers[6], 'seed': 'st_tim_2', 'text': null, 'hoursAgo': 7},
      // nursultan_e - 2 stories
      {'author': otherUsers[4], 'seed': 'st_nur_1', 'text': null, 'hoursAgo': 2},
      {'author': otherUsers[4], 'seed': 'st_nur_2', 'text': 'Тренировка дня', 'hoursAgo': 9},
      // kamila_a - 3 stories
      {'author': otherUsers[3], 'seed': 'st_kam_1', 'text': null, 'hoursAgo': 1},
      {'author': otherUsers[3], 'seed': 'st_kam_2', 'text': 'Шоурум открыт!', 'hoursAgo': 5},
      {'author': otherUsers[3], 'seed': 'st_kam_3', 'text': null, 'hoursAgo': 11},
    ];

    for (var i = 0; i < storyData.length; i++) {
      final d = storyData[i];
      final author = d['author'] as User;
      final seed = d['seed'] as String;
      final textOverlay = d['text'] as String?;
      final hoursAgo = d['hoursAgo'] as int;
      _stories.add(Story(
        id: 'story_${i + 1}',
        author: author,
        mediaUrl: 'https://picsum.photos/seed/$seed/600/1000',
        mediaType: StoryMediaType.image,
        textOverlay: textOverlay,
        isSeen: author.id == 'me' ? true : (i % 4 == 0),
        viewsCount: 80 + _rng.nextInt(600),
        createdAt: now.subtract(Duration(hours: hoursAgo)),
        expiresAt: now.subtract(Duration(hours: hoursAgo)).add(const Duration(hours: 24)),
      ));
    }

    // ------ Comments (3-8 per post) ------
    _comments.clear();
    int commentIdx = 0;
    final commentTexts = [
      'Вау, потрясающе!',
      'Очень красиво!',
      'Супер фото!',
      'Класс!',
      'Где это?',
      'Хочу туда!',
      'Круто выглядит!',
      'Вдохновляет!',
      'Какая красота!',
      'Отличная работа!',
      'Это шедевр!',
      'Сохраню себе!',
      'Нереально круто!',
      'Подписалась!',
      'Обожаю твои фото!',
      'Как ты это делаешь?',
      'Талант!',
      'Мечта!',
      'Лучший контент!',
      'Больше такого!',
      'Невероятно!',
      'Топ!',
      'Это огонь!',
      'Красота неописуемая!',
      'Респект!',
    ];

    final replyTexts = [
      'Спасибо!',
      'Рада, что нравится!',
      'Благодарю!',
      'Приятно слышать!',
      'Ты лучше!',
      'Да, это было здорово!',
      'Обязательно попробуй!',
      'Скоро будет еще!',
      'Это Алматы!',
      'Приезжай, покажу!',
    ];

    for (final post in _posts) {
      final count = 3 + _rng.nextInt(6); // 3-8 comments
      for (var i = 0; i < count; i++) {
        commentIdx++;
        final commentAuthor = otherUsers[_rng.nextInt(otherUsers.length)];
        final parentId = 'c_$commentIdx';
        final hoursAgo = 1 + _rng.nextInt(48);

        // Create 0-2 replies for this comment
        final replyCount = _rng.nextInt(3);
        final replies = <Comment>[];
        for (var r = 0; r < replyCount; r++) {
          commentIdx++;
          replies.add(Comment(
            id: 'c_$commentIdx',
            postId: post.id,
            author: otherUsers[_rng.nextInt(otherUsers.length)],
            text: replyTexts[_rng.nextInt(replyTexts.length)],
            likesCount: _rng.nextInt(20),
            isLiked: _rng.nextBool(),
            parentId: parentId,
            createdAt: now.subtract(Duration(hours: hoursAgo - 1, minutes: _rng.nextInt(60))),
          ));
        }

        _comments.add(Comment(
          id: parentId,
          postId: post.id,
          author: commentAuthor,
          text: commentTexts[_rng.nextInt(commentTexts.length)],
          likesCount: _rng.nextInt(50),
          isLiked: _rng.nextBool(),
          replies: replies,
          repliesCount: replies.length,
          createdAt: now.subtract(Duration(hours: hoursAgo)),
        ));
      }
    }

    // ------ Notifications (17) ------
    _notifications.clear();
    _notifications.addAll([
      AppNotification(
        id: 'n1',
        type: NotificationType.like,
        fromUser: otherUsers[0], // bekzat_n
        postId: 'p11',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p11a/100/100',
        isRead: false,
        createdAt: now.subtract(const Duration(minutes: 3)),
      ),
      AppNotification(
        id: 'n2',
        type: NotificationType.follow,
        fromUser: otherUsers[11], // dauren_arch
        isRead: false,
        createdAt: now.subtract(const Duration(minutes: 12)),
      ),
      AppNotification(
        id: 'n3',
        type: NotificationType.comment,
        fromUser: otherUsers[1], // dana_k
        postId: 'p20',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p20a/100/100',
        commentText: 'Потрясающий проект! Цвета невероятные',
        isRead: false,
        createdAt: now.subtract(const Duration(minutes: 25)),
      ),
      AppNotification(
        id: 'n4',
        type: NotificationType.like,
        fromUser: otherUsers[7], // aliya_s
        postId: 'p26',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p26/100/100',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 1)),
      ),
      AppNotification(
        id: 'n5',
        type: NotificationType.mention,
        fromUser: otherUsers[8], // madina_o
        postId: 'p13',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p13/100/100',
        commentText: 'Посмотрите работы @aidana_s',
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 2)),
      ),
      AppNotification(
        id: 'n6',
        type: NotificationType.follow,
        fromUser: otherUsers[9], // ruslan_tech
        isRead: false,
        createdAt: now.subtract(const Duration(hours: 3)),
      ),
      AppNotification(
        id: 'n7',
        type: NotificationType.reply,
        fromUser: otherUsers[4], // nursultan_e
        postId: 'p11',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p11a/100/100',
        commentText: 'Мощные портреты!',
        isRead: true,
        createdAt: now.subtract(const Duration(hours: 4)),
      ),
      AppNotification(
        id: 'n8',
        type: NotificationType.like,
        fromUser: otherUsers[3], // kamila_a
        postId: 'p20',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p20a/100/100',
        isRead: true,
        createdAt: now.subtract(const Duration(hours: 5)),
      ),
      AppNotification(
        id: 'n9',
        type: NotificationType.comment,
        fromUser: otherUsers[5], // zhanna_t
        postId: 'p26',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p26/100/100',
        commentText: 'Атмосферное фото! Люблю Алматы утром',
        isRead: true,
        createdAt: now.subtract(const Duration(hours: 8)),
      ),
      AppNotification(
        id: 'n10',
        type: NotificationType.postTag,
        fromUser: otherUsers[1], // dana_k
        postId: 'p1',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p1/100/100',
        isRead: true,
        createdAt: now.subtract(const Duration(hours: 12)),
      ),
      AppNotification(
        id: 'n11',
        type: NotificationType.like,
        fromUser: otherUsers[6], // timur_b
        postId: 'p11',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p11a/100/100',
        isRead: true,
        createdAt: now.subtract(const Duration(hours: 18)),
      ),
      AppNotification(
        id: 'n12',
        type: NotificationType.follow,
        fromUser: otherUsers[10], // asel_yoga
        isRead: true,
        createdAt: now.subtract(const Duration(days: 1)),
      ),
      AppNotification(
        id: 'n13',
        type: NotificationType.comment,
        fromUser: otherUsers[2], // arman_zh
        postId: 'p18',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p18/100/100',
        commentText: 'Крутой закат! Хочу такую камеру',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 1, hours: 6)),
      ),
      AppNotification(
        id: 'n14',
        type: NotificationType.like,
        fromUser: otherUsers[8], // madina_o
        postId: 'p20',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p20a/100/100',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 2)),
      ),
      AppNotification(
        id: 'n15',
        type: NotificationType.mention,
        fromUser: otherUsers[7], // aliya_s
        postId: 'p4',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p4a/100/100',
        commentText: '@aidana_s вдохновилась твоей палитрой',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 2, hours: 10)),
      ),
      AppNotification(
        id: 'n16',
        type: NotificationType.reply,
        fromUser: otherUsers[0], // bekzat_n
        postId: 'p20',
        postThumbnailUrl: 'https://picsum.photos/seed/seeu_p20a/100/100',
        commentText: 'Базар - это целый мир!',
        isRead: true,
        createdAt: now.subtract(const Duration(days: 3)),
      ),
      AppNotification(
        id: 'n17',
        type: NotificationType.follow,
        fromUser: otherUsers[5], // zhanna_t
        isRead: true,
        createdAt: now.subtract(const Duration(days: 4)),
      ),
    ]);

    // ------ Highlights ------
    _highlights.clear();
    _highlights.addAll([
      // Current user (aidana_s) highlights
      Highlight(
        id: 'hl1',
        author: _currentUser,
        title: 'Портреты',
        coverUrl: 'https://picsum.photos/seed/hl1/200/200',
        stories: [
          Story(id: 'hls1', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls1/600/1000', createdAt: now.subtract(const Duration(days: 30)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls2', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls2/600/1000', createdAt: now.subtract(const Duration(days: 28)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 6, 1),
      ),
      Highlight(
        id: 'hl2',
        author: _currentUser,
        title: 'Путешествия',
        coverUrl: 'https://picsum.photos/seed/hl2/200/200',
        stories: [
          Story(id: 'hls3', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls3/600/1000', createdAt: now.subtract(const Duration(days: 60)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls4', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls4/600/1000', createdAt: now.subtract(const Duration(days: 55)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls5', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls5/600/1000', createdAt: now.subtract(const Duration(days: 50)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 4, 15),
      ),
      Highlight(
        id: 'hl3',
        author: _currentUser,
        title: 'Базары',
        coverUrl: 'https://picsum.photos/seed/hl3/200/200',
        stories: [
          Story(id: 'hls6', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls6/600/1000', createdAt: now.subtract(const Duration(days: 20)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 8, 1),
      ),
      Highlight(
        id: 'hl4',
        author: _currentUser,
        title: 'Закаты',
        coverUrl: 'https://picsum.photos/seed/hl4/200/200',
        stories: [
          Story(id: 'hls7', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls7/600/1000', createdAt: now.subtract(const Duration(days: 10)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls8', author: _currentUser, mediaUrl: 'https://picsum.photos/seed/hls8/600/1000', createdAt: now.subtract(const Duration(days: 8)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 9, 1),
      ),
      // dana_k highlights
      Highlight(
        id: 'hl5',
        author: otherUsers[1],
        title: 'UI/UX',
        coverUrl: 'https://picsum.photos/seed/hl5/200/200',
        stories: [
          Story(id: 'hls9', author: otherUsers[1], mediaUrl: 'https://picsum.photos/seed/hls9/600/1000', createdAt: now.subtract(const Duration(days: 40)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls10', author: otherUsers[1], mediaUrl: 'https://picsum.photos/seed/hls10/600/1000', createdAt: now.subtract(const Duration(days: 35)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 3, 1),
      ),
      Highlight(
        id: 'hl6',
        author: otherUsers[1],
        title: 'Workspace',
        coverUrl: 'https://picsum.photos/seed/hl6/200/200',
        stories: [
          Story(id: 'hls11', author: otherUsers[1], mediaUrl: 'https://picsum.photos/seed/hls11/600/1000', createdAt: now.subtract(const Duration(days: 25)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 5, 1),
      ),
      Highlight(
        id: 'hl7',
        author: otherUsers[1],
        title: 'Конференции',
        coverUrl: 'https://picsum.photos/seed/hl7/200/200',
        stories: [
          Story(id: 'hls12', author: otherUsers[1], mediaUrl: 'https://picsum.photos/seed/hls12/600/1000', createdAt: now.subtract(const Duration(days: 15)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls13', author: otherUsers[1], mediaUrl: 'https://picsum.photos/seed/hls13/600/1000', createdAt: now.subtract(const Duration(days: 12)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 7, 1),
      ),
      // zhanna_t highlights
      Highlight(
        id: 'hl8',
        author: otherUsers[5],
        title: 'Казахстан',
        coverUrl: 'https://picsum.photos/seed/hl8/200/200',
        stories: [
          Story(id: 'hls14', author: otherUsers[5], mediaUrl: 'https://picsum.photos/seed/hls14/600/1000', createdAt: now.subtract(const Duration(days: 90)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls15', author: otherUsers[5], mediaUrl: 'https://picsum.photos/seed/hls15/600/1000', createdAt: now.subtract(const Duration(days: 85)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls16', author: otherUsers[5], mediaUrl: 'https://picsum.photos/seed/hls16/600/1000', createdAt: now.subtract(const Duration(days: 80)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 1, 1),
      ),
      Highlight(
        id: 'hl9',
        author: otherUsers[5],
        title: 'Европа',
        coverUrl: 'https://picsum.photos/seed/hl9/200/200',
        stories: [
          Story(id: 'hls17', author: otherUsers[5], mediaUrl: 'https://picsum.photos/seed/hls17/600/1000', createdAt: now.subtract(const Duration(days: 120)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2023, 11, 1),
      ),
      Highlight(
        id: 'hl10',
        author: otherUsers[5],
        title: 'Азия',
        coverUrl: 'https://picsum.photos/seed/hl10/200/200',
        stories: [
          Story(id: 'hls18', author: otherUsers[5], mediaUrl: 'https://picsum.photos/seed/hls18/600/1000', createdAt: now.subtract(const Duration(days: 150)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls19', author: otherUsers[5], mediaUrl: 'https://picsum.photos/seed/hls19/600/1000', createdAt: now.subtract(const Duration(days: 145)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2023, 8, 1),
      ),
      // kamila_a highlights
      Highlight(
        id: 'hl11',
        author: otherUsers[3],
        title: 'OOTD',
        coverUrl: 'https://picsum.photos/seed/hl11/200/200',
        stories: [
          Story(id: 'hls20', author: otherUsers[3], mediaUrl: 'https://picsum.photos/seed/hls20/600/1000', createdAt: now.subtract(const Duration(days: 5)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 10, 1),
      ),
      Highlight(
        id: 'hl12',
        author: otherUsers[3],
        title: 'Шоурум',
        coverUrl: 'https://picsum.photos/seed/hl12/200/200',
        stories: [
          Story(id: 'hls21', author: otherUsers[3], mediaUrl: 'https://picsum.photos/seed/hls21/600/1000', createdAt: now.subtract(const Duration(days: 18)), expiresAt: now.add(const Duration(days: 365))),
          Story(id: 'hls22', author: otherUsers[3], mediaUrl: 'https://picsum.photos/seed/hls22/600/1000', createdAt: now.subtract(const Duration(days: 16)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 9, 15),
      ),
      Highlight(
        id: 'hl13',
        author: otherUsers[3],
        title: 'Beauty',
        coverUrl: 'https://picsum.photos/seed/hl13/200/200',
        stories: [
          Story(id: 'hls23', author: otherUsers[3], mediaUrl: 'https://picsum.photos/seed/hls23/600/1000', createdAt: now.subtract(const Duration(days: 22)), expiresAt: now.add(const Duration(days: 365))),
        ],
        createdAt: DateTime(2024, 8, 20),
      ),
    ]);

    // ------ Chats & Messages (7 conversations) ------
    _chats.clear();
    _chatMessages.clear();

    final chatPeers = [
      otherUsers[0],  // bekzat_n
      otherUsers[1],  // dana_k
      otherUsers[5],  // zhanna_t
      otherUsers[6],  // timur_b
      otherUsers[3],  // kamila_a
      otherUsers[7],  // aliya_s
      otherUsers[8],  // madina_o
    ];
    final chatConversations = <List<_MsgTemplate>>[
      // Chat 1: bekzat_n (разработка)
      [
        _MsgTemplate('me', 'Привет! Видела твой доклад на DevFest. Очень круто!', 48),
        _MsgTemplate('u1', 'Спасибо! Рад, что понравилось', 47),
        _MsgTemplate('me', 'Можешь скинуть слайды? Хочу коллегам показать', 46),
        _MsgTemplate('u1', 'Да, конечно! Сейчас найду и скину', 45),
        _MsgTemplate('u1', 'Вот ссылка: slides.dev/bekzat-devfest', 44),
        _MsgTemplate('me', 'Супер, спасибо!', 43),
        _MsgTemplate('u1', 'Если будут вопросы по архитектуре - пиши', 42),
        _MsgTemplate('me', 'Кстати, ты используешь Riverpod или Bloc?', 20),
        _MsgTemplate('u1', 'Riverpod в последних проектах. Проще и чище', 19),
        _MsgTemplate('me', 'Согласна, мне тоже нравится', 18),
      ],
      // Chat 2: dana_k (коллаборация)
      [
        _MsgTemplate('u2', 'Айдана, привет! Хочу предложить коллаборацию', 72),
        _MsgTemplate('me', 'Привет! Интересно, расскажи подробнее', 71),
        _MsgTemplate('u2', 'Делаю серию дизайнов для выставки, нужны фото', 70),
        _MsgTemplate('me', 'О, звучит здорово! Когда выставка?', 69),
        _MsgTemplate('u2', 'В конце мая. Успеем?', 68),
        _MsgTemplate('me', 'Да, вполне. Давай встретимся и обсудим детали', 67),
        _MsgTemplate('u2', 'Завтра в 15:00 удобно?', 24),
        _MsgTemplate('me', 'Да, идеально!', 23),
        _MsgTemplate('u2', 'Отлично, тогда в кофейне на Абая', 22),
        _MsgTemplate('me', 'Договорились!', 21),
        _MsgTemplate('u2', 'До встречи!', 3),
      ],
      // Chat 3: zhanna_t (путешествия)
      [
        _MsgTemplate('me', 'Жанна, потрясающие фото Кольсая!', 96),
        _MsgTemplate('u6', 'Спасибо! Это одно из моих любимых мест', 95),
        _MsgTemplate('me', 'Когда лучше ехать? Хочу поснимать осенью', 94),
        _MsgTemplate('u6', 'Сентябрь - идеально. Осенние краски невероятные', 93),
        _MsgTemplate('u6', 'Могу дать контакт проводника, он знает лучшие точки', 92),
        _MsgTemplate('me', 'Было бы супер! Мне именно для фото нужно', 91),
        _MsgTemplate('u6', '+7 707 123 4567, Ерлан. Скажи что от меня', 90),
        _MsgTemplate('me', 'Спасибо большое! Обязательно поеду', 89),
      ],
      // Chat 4: timur_b (еда)
      [
        _MsgTemplate('u7', 'Привет! Спасибо за лайк на рецепте бешбармака', 36),
        _MsgTemplate('me', 'Привет! Бешбармак выглядел невероятно', 35),
        _MsgTemplate('u7', 'Попробуй приготовить! Рецепт в посте', 34),
        _MsgTemplate('me', 'Обязательно попробую на выходных', 33),
        _MsgTemplate('u7', 'Если что, пиши - подскажу нюансы теста', 32),
        _MsgTemplate('me', 'Спасибо! А курт где лучше купить?', 10),
        _MsgTemplate('u7', 'На Зеленом базаре, второй ряд слева. Там самый вкусный', 9),
        _MsgTemplate('me', 'Записала, спасибо! Кстати, можно тебя сфоткать для проекта?', 8),
        _MsgTemplate('u7', 'О, конечно! Давай на базаре и снимем', 6),
      ],
      // Chat 5: kamila_a (стиль)
      [
        _MsgTemplate('u4', 'Айдана, обожаю твои портреты!', 120),
        _MsgTemplate('me', 'Камила, спасибо! Я фанатка твоего стиля', 119),
        _MsgTemplate('u4', 'Можешь сделать фотосессию для шоурума?', 118),
        _MsgTemplate('me', 'Конечно! Давай обсудим что нужно', 117),
        _MsgTemplate('u4', 'Нужны фото новой коллекции, 20-25 образов', 116),
        _MsgTemplate('me', 'Поняла. Скину портфолио и примеры завтра', 115),
        _MsgTemplate('u4', 'Жду!', 114),
        _MsgTemplate('me', 'Отправила на почту. Посмотри когда будет время', 50),
        _MsgTemplate('u4', 'Посмотрела! Все нравится, давай начинать', 49),
        _MsgTemplate('me', 'Отлично! Предлагаю в субботу', 48),
        _MsgTemplate('u4', 'Когда будут готовы фото?', 5),
        _MsgTemplate('me', 'Через неделю первые отберу и обработаю', 4),
        _MsgTemplate('u4', 'Супер, жду с нетерпением!', 2),
      ],
      // Chat 6: aliya_s (искусство)
      [
        _MsgTemplate('me', 'Алия, привет! Та картина маслом еще продается?', 30),
        _MsgTemplate('u8', 'Привет! Да, "Осень в Алматы" еще в наличии', 29),
        _MsgTemplate('me', 'Какой размер?', 28),
        _MsgTemplate('u8', '60x80 см, холст, масло', 27),
        _MsgTemplate('me', 'Красота! А можно к тебе в мастерскую вживую посмотреть?', 26),
        _MsgTemplate('u8', 'Конечно! Приходи в пятницу после 14:00', 25),
        _MsgTemplate('me', 'Договорились! Адрес скинешь?', 12),
        _MsgTemplate('u8', 'ул. Тулебаева 50, 3 этаж, студия 12', 11),
      ],
      // Chat 7: madina_o (подкаст)
      [
        _MsgTemplate('u9', 'Айдана, привет! Приглашаю тебя на подкаст', 60),
        _MsgTemplate('me', 'О, привет! Интересно, о чем поговорим?', 59),
        _MsgTemplate('u9', 'О фотографии, о проекте "Лица города"', 58),
        _MsgTemplate('me', 'Звучит здорово! Когда планируешь запись?', 57),
        _MsgTemplate('u9', 'В следующую среду, часов в 11 утра', 56),
        _MsgTemplate('me', 'Подходит! А где записываемся?', 40),
        _MsgTemplate('u9', 'У нас студия на Достык, скину локацию', 39),
        _MsgTemplate('me', 'Жду!', 38),
        _MsgTemplate('u9', 'Кстати, можно пару твоих фото показать в видеоверсии?', 15),
        _MsgTemplate('me', 'Да, конечно! Отберу лучшие и скину', 14),
      ],
    ];

    for (var chatIdx = 0; chatIdx < chatPeers.length; chatIdx++) {
      final chatId = 'chat_${chatIdx + 1}';
      final templates = chatConversations[chatIdx];
      ChatMessage? lastMsg;

      for (var msgIdx = 0; msgIdx < templates.length; msgIdx++) {
        final t = templates[msgIdx];
        final msg = ChatMessage(
          id: 'msg_${chatIdx + 1}_${msgIdx + 1}',
          chatId: chatId,
          senderId: t.senderId,
          text: t.text,
          createdAt: now.subtract(Duration(hours: t.hoursAgo)),
          isRead: msgIdx < templates.length - 1 || t.senderId == 'me',
        );
        _chatMessages.add(msg);
        if (lastMsg == null || msg.createdAt.isAfter(lastMsg.createdAt)) {
          lastMsg = msg;
        }
      }

      // Count unread (messages from other user that are not read)
      final unread = _chatMessages
          .where((m) => m.chatId == chatId && m.senderId != 'me' && !m.isRead)
          .length;

      _chats.add(Chat(
        id: chatId,
        otherUser: chatPeers[chatIdx],
        lastMessage: lastMsg,
        unreadCount: unread,
        updatedAt: lastMsg?.createdAt ?? now,
      ));
    }
  }

  // =========================================================================
  // AUTH
  // =========================================================================

  User get currentUser => _currentUser;
  bool get isAuthenticated => _isAuthenticated;

  Future<User> login(String email, String password) async {
    await _delay();
    _isAuthenticated = true;
    return _currentUser;
  }

  Future<User> register({
    required String username,
    required String email,
    required String password,
    required String fullName,
  }) async {
    await _delay();
    _currentUser = User(
      id: 'me',
      username: username,
      fullName: fullName,
      avatarUrl: 'https://i.pravatar.cc/150?img=47',
      createdAt: DateTime.now(),
    );
    _isAuthenticated = true;
    return _currentUser;
  }

  Future<void> logout() async {
    await _delay();
    _isAuthenticated = false;
  }

  Future<bool> checkUsername(String username) async {
    await _delay();
    return !_users.any((u) => u.username.toLowerCase() == username.toLowerCase());
  }

  // =========================================================================
  // FEED
  // =========================================================================

  Future<List<Post>> getFeed({int page = 0, int limit = 10}) async {
    await _delay();
    final start = page * limit;
    if (start >= _posts.length) return [];
    final end = (start + limit).clamp(0, _posts.length);
    return _posts.sublist(start, end);
  }

  Future<Post> getPost(String id) async {
    await _delay();
    return _posts.firstWhere((p) => p.id == id);
  }

  Future<void> toggleLike(String postId) async {
    await _delay();
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final post = _posts[idx];
    final newIsLiked = !post.isLiked;
    _posts[idx] = post.copyWith(
      isLiked: newIsLiked,
      likesCount: newIsLiked ? post.likesCount + 1 : post.likesCount - 1,
    );
  }

  Future<void> toggleSave(String postId) async {
    await _delay();
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final post = _posts[idx];
    final newIsSaved = !post.isSaved;
    _posts[idx] = post.copyWith(isSaved: newIsSaved);
    if (newIsSaved) {
      _savedPostIds.add(postId);
    } else {
      _savedPostIds.remove(postId);
    }
  }

  Future<Post> createPost({
    required String imageUrl,
    String? caption,
    String? location,
  }) async {
    await _delay();
    final post = Post(
      id: _genId(),
      author: _currentUser,
      media: [
        PostMedia(url: imageUrl, type: MediaType.image, aspectRatio: 1.0),
      ],
      caption: caption,
      location: location,
      createdAt: DateTime.now(),
    );
    _posts.insert(0, post);

    // Update current user post count
    _currentUser = _currentUser.copyWith(postsCount: _currentUser.postsCount + 1);
    _updateUserInList(_currentUser);

    return post;
  }

  Future<Post> createWave({
    required String caption,
    required int waveColorValue,
  }) async {
    await _delay();
    final wave = Post(
      id: _genId(),
      author: _currentUser,
      media: [],
      caption: caption,
      createdAt: DateTime.now(),
      isWave: true,
      waveColorValue: waveColorValue,
    );
    _posts.insert(0, wave);

    _currentUser = _currentUser.copyWith(postsCount: _currentUser.postsCount + 1);
    _updateUserInList(_currentUser);

    return wave;
  }

  Future<void> removePost(String postId) async {
    await _delay();
    final idx = _posts.indexWhere((p) => p.id == postId);
    if (idx == -1) return;
    final post = _posts[idx];
    _posts.removeAt(idx);
    _savedPostIds.remove(postId);
    _comments.removeWhere((c) => c.postId == postId);

    if (post.author.id == _currentUser.id) {
      _currentUser = _currentUser.copyWith(postsCount: (_currentUser.postsCount - 1).clamp(0, 999999));
      _updateUserInList(_currentUser);
    }
  }

  Future<void> deletePost(String postId) async {
    await removePost(postId);
  }

  // =========================================================================
  // STORIES
  // =========================================================================

  Future<List<StoryGroup>> getStories() async {
    await _delay();
    final grouped = <String, List<Story>>{};
    for (final s in _stories) {
      if (!s.isExpired) {
        grouped.putIfAbsent(s.author.id, () => []).add(s);
      }
    }
    final groups = <StoryGroup>[];
    for (final entry in grouped.entries) {
      final stories = entry.value..sort((a, b) => a.createdAt.compareTo(b.createdAt));
      groups.add(StoryGroup(
        author: stories.first.author,
        stories: stories,
        allSeen: stories.every((s) => s.isSeen),
      ));
    }
    // Current user first, then unseen first
    groups.sort((a, b) {
      if (a.author.id == 'me') return -1;
      if (b.author.id == 'me') return 1;
      if (a.allSeen != b.allSeen) return a.allSeen ? 1 : -1;
      return b.stories.last.createdAt.compareTo(a.stories.last.createdAt);
    });
    return groups;
  }

  Future<void> markStorySeen(String storyId) async {
    await _delay();
    final idx = _stories.indexWhere((s) => s.id == storyId);
    if (idx == -1) return;
    _stories[idx] = _stories[idx].copyWith(isSeen: true);
  }

  Future<void> createStory({required String mediaUrl, String? textOverlay}) async {
    await _delay();
    final story = Story(
      id: _genId(),
      author: _currentUser,
      mediaUrl: mediaUrl,
      textOverlay: textOverlay,
      isSeen: true,
      createdAt: DateTime.now(),
      expiresAt: DateTime.now().add(const Duration(hours: 24)),
    );
    _stories.add(story);
  }

  // =========================================================================
  // COMMENTS
  // =========================================================================

  Future<List<Comment>> getComments(String postId) async {
    await _delay();
    return _comments.where((c) => c.postId == postId && c.parentId == null).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<Comment> addComment(String postId, String text, {String? parentId}) async {
    await _delay();
    final comment = Comment(
      id: _genId(),
      postId: postId,
      author: _currentUser,
      text: text,
      parentId: parentId,
      createdAt: DateTime.now(),
    );

    if (parentId != null) {
      // Add as reply to parent
      final parentIdx = _comments.indexWhere((c) => c.id == parentId);
      if (parentIdx != -1) {
        final parent = _comments[parentIdx];
        _comments[parentIdx] = parent.copyWith(
          replies: [...parent.replies, comment],
          repliesCount: parent.repliesCount + 1,
        );
      }
    } else {
      _comments.add(comment);
    }

    // Update post comment count
    final postIdx = _posts.indexWhere((p) => p.id == postId);
    if (postIdx != -1) {
      final post = _posts[postIdx];
      _posts[postIdx] = post.copyWith(commentsCount: post.commentsCount + 1);
    }

    return comment;
  }

  Future<void> toggleCommentLike(String commentId) async {
    await _delay();
    // Check top-level comments
    final idx = _comments.indexWhere((c) => c.id == commentId);
    if (idx != -1) {
      final c = _comments[idx];
      final newIsLiked = !c.isLiked;
      _comments[idx] = c.copyWith(
        isLiked: newIsLiked,
        likesCount: newIsLiked ? c.likesCount + 1 : c.likesCount - 1,
      );
      return;
    }
    // Check replies
    for (var i = 0; i < _comments.length; i++) {
      final parent = _comments[i];
      final rIdx = parent.replies.indexWhere((r) => r.id == commentId);
      if (rIdx != -1) {
        final r = parent.replies[rIdx];
        final newIsLiked = !r.isLiked;
        final updatedReplies = List<Comment>.from(parent.replies);
        updatedReplies[rIdx] = r.copyWith(
          isLiked: newIsLiked,
          likesCount: newIsLiked ? r.likesCount + 1 : r.likesCount - 1,
        );
        _comments[i] = parent.copyWith(replies: updatedReplies);
        return;
      }
    }
  }

  // =========================================================================
  // USERS / PROFILES
  // =========================================================================

  Future<User> getProfile(String username) async {
    await _delay();
    return _users.firstWhere(
      (u) => u.username == username,
      orElse: () => _currentUser,
    );
  }

  Future<List<Post>> getUserPosts(String username) async {
    await _delay();
    return _posts.where((p) => p.author.username == username).toList()
      ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<List<Post>> getUserSavedPosts() async {
    await _delay();
    return _posts.where((p) => _savedPostIds.contains(p.id)).toList();
  }

  Future<List<Post>> getUserTaggedPosts(String username) async {
    await _delay();
    // Simulate some tagged posts (return a subset of posts from other users)
    return _posts
        .where((p) => p.author.username != username && p.caption != null && p.caption!.contains('@'))
        .take(5)
        .toList();
  }

  Future<List<Highlight>> getUserHighlights(String username) async {
    await _delay();
    return _highlights.where((h) => h.author.username == username).toList();
  }

  Future<void> toggleFollow(String username) async {
    await _delay();
    final idx = _users.indexWhere((u) => u.username == username);
    if (idx == -1) return;

    final user = _users[idx];
    final nowFollowing = !_followingUsernames.contains(username);

    if (nowFollowing) {
      _followingUsernames.add(username);
    } else {
      _followingUsernames.remove(username);
    }

    // Update target user
    _users[idx] = user.copyWith(
      isFollowing: nowFollowing,
      followersCount: nowFollowing ? user.followersCount + 1 : (user.followersCount - 1).clamp(0, 999999),
    );

    // Update current user's following count
    _currentUser = _currentUser.copyWith(
      followingCount: nowFollowing ? _currentUser.followingCount + 1 : (_currentUser.followingCount - 1).clamp(0, 999999),
    );
    _updateUserInList(_currentUser);

    // Update author in posts
    _updateAuthorInPosts(username, _users[idx]);
  }

  Future<List<User>> getFollowers(String username) async {
    await _delay();
    // Return a realistic subset of users as followers
    final target = _users.firstWhere((u) => u.username == username, orElse: () => _currentUser);
    final others = _users.where((u) => u.id != target.id).toList()..shuffle(_rng);
    return others.take((others.length * 0.6).ceil()).toList();
  }

  Future<List<User>> getFollowing(String username) async {
    await _delay();
    if (username == _currentUser.username) {
      return _users.where((u) => _followingUsernames.contains(u.username)).toList();
    }
    final others = _users.where((u) => u.username != username).toList()..shuffle(_rng);
    return others.take((others.length * 0.5).ceil()).toList();
  }

  Future<User> updateProfile({
    String? fullName,
    String? username,
    String? bio,
    String? website,
    String? avatarUrl,
  }) async {
    await _delay();
    _currentUser = _currentUser.copyWith(
      fullName: fullName ?? _currentUser.fullName,
      username: username ?? _currentUser.username,
      bio: bio ?? _currentUser.bio,
      website: website ?? _currentUser.website,
      avatarUrl: avatarUrl ?? _currentUser.avatarUrl,
    );
    _updateUserInList(_currentUser);
    return _currentUser;
  }

  // =========================================================================
  // SEARCH
  // =========================================================================

  Future<List<User>> searchUsers(String query) async {
    await _delay();
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    return _users.where((u) =>
        u.username.toLowerCase().contains(q) ||
        u.fullName.toLowerCase().contains(q)).toList();
  }

  Future<List<Post>> searchPosts(String query) async {
    await _delay();
    if (query.isEmpty) return [];
    final q = query.toLowerCase();
    return _posts.where((p) =>
        (p.caption?.toLowerCase().contains(q) ?? false) ||
        (p.location?.toLowerCase().contains(q) ?? false)).toList();
  }

  Future<List<Post>> getExplorePosts() async {
    await _delay();
    final shuffled = List<Post>.from(_posts)..shuffle(_rng);
    return shuffled;
  }

  // =========================================================================
  // NOTIFICATIONS
  // =========================================================================

  Future<List<AppNotification>> getNotifications() async {
    await _delay();
    return List.from(_notifications)..sort((a, b) => b.createdAt.compareTo(a.createdAt));
  }

  Future<void> markNotificationRead(String id) async {
    await _delay();
    final idx = _notifications.indexWhere((n) => n.id == id);
    if (idx == -1) return;
    _notifications[idx] = _notifications[idx].copyWith(isRead: true);
  }

  Future<void> markAllNotificationsRead() async {
    await _delay();
    for (var i = 0; i < _notifications.length; i++) {
      if (!_notifications[i].isRead) {
        _notifications[i] = _notifications[i].copyWith(isRead: true);
      }
    }
  }

  int get unreadNotificationCount =>
      _notifications.where((n) => !n.isRead).length;

  // =========================================================================
  // CHAT
  // =========================================================================

  Future<List<Chat>> getChats() async {
    await _delay();
    return List.from(_chats)..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  }

  Future<List<ChatMessage>> getChatMessages(String chatId) async {
    await _delay();
    // Mark all messages from other user as read
    for (var i = 0; i < _chatMessages.length; i++) {
      final m = _chatMessages[i];
      if (m.chatId == chatId && m.senderId != 'me' && !m.isRead) {
        _chatMessages[i] = m.copyWith(isRead: true);
      }
    }
    // Reset unread count on the chat
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx != -1) {
      _chats[chatIdx] = _chats[chatIdx].copyWith(unreadCount: 0);
    }

    return _chatMessages.where((m) => m.chatId == chatId).toList()
      ..sort((a, b) => a.createdAt.compareTo(b.createdAt));
  }

  Future<ChatMessage> sendMessage(String chatId, String text) async {
    await _delay();
    final msg = ChatMessage(
      id: _genId(),
      chatId: chatId,
      senderId: 'me',
      text: text,
      createdAt: DateTime.now(),
      isRead: true,
    );
    _chatMessages.add(msg);

    // Update chat's last message
    final chatIdx = _chats.indexWhere((c) => c.id == chatId);
    if (chatIdx != -1) {
      _chats[chatIdx] = _chats[chatIdx].copyWith(
        lastMessage: msg,
        updatedAt: msg.createdAt,
      );
    }

    return msg;
  }

  Future<Chat> startChat(String userId) async {
    await _delay();
    // Check if chat already exists
    final existing = _chats.where((c) => c.otherUser.id == userId);
    if (existing.isNotEmpty) return existing.first;

    final otherUser = _users.firstWhere(
      (u) => u.id == userId,
      orElse: () => _users[1],
    );

    final chat = Chat(
      id: _genId(),
      otherUser: otherUser,
      updatedAt: DateTime.now(),
    );
    _chats.add(chat);
    return chat;
  }

  // =========================================================================
  // HELPERS (private)
  // =========================================================================

  void _updateUserInList(User user) {
    final idx = _users.indexWhere((u) => u.id == user.id);
    if (idx != -1) {
      _users[idx] = user;
    }
  }

  void _updateAuthorInPosts(String username, User updatedUser) {
    for (var i = 0; i < _posts.length; i++) {
      if (_posts[i].author.username == username) {
        _posts[i] = _posts[i].copyWith(author: updatedUser);
      }
    }
  }
}

// Helper class for building chat messages during init
class _MsgTemplate {
  final String senderId;
  final String text;
  final int hoursAgo;
  const _MsgTemplate(this.senderId, this.text, this.hoursAgo);
}
