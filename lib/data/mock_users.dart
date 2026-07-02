class MockUser {
  final String id;
  final String name;
  final String publicIdHex;
  final String privateIdHex;
  final String avatarEmoji;
  final String bio;
  final List<String> friendIds;

  const MockUser({
    required this.id,
    required this.name,
    required this.publicIdHex,
    required this.privateIdHex,
    required this.avatarEmoji,
    required this.bio,
    this.friendIds = const [],
  });
}

const MockUser user001 = MockUser(
  id: 'user_001',
  name: 'Айдана',
  publicIdHex: '5C08544172E6C4FE',
  privateIdHex: 'FB28BABA02025BBC',
  avatarEmoji: '\u{1F469}\u{1F3FB}',
  bio: 'Дизайнер интерфейсов из Алматы',
  friendIds: ['user_005'],
);

const MockUser user002 = MockUser(
  id: 'user_002',
  name: 'Бекзат',
  publicIdHex: '1C1B401D592F2C1A',
  privateIdHex: '0F072FCD09D44009',
  avatarEmoji: '\u{1F9D4}\u{1F3FD}',
  bio: 'Фотограф, путешественник',
  friendIds: [],
);

const MockUser user005 = MockUser(
  id: 'user_005',
  name: 'Дана',
  publicIdHex: 'B902FE74A05E1683',
  privateIdHex: '32F778D7ED6B06E7',
  avatarEmoji: '\u{1F469}\u{1F3FD}',
  bio: 'Демо-аккаунт, без чипа',
  friendIds: ['user_001'],
);

const List<MockUser> allUsers = [user001, user002, user005];

MockUser? findByPublicId(String hex) {
  final upper = hex.toUpperCase();
  for (final u in allUsers) {
    if (u.publicIdHex == upper) return u;
  }
  return null;
}

MockUser? findByPrivateId(String hex, {required List<String> allowedIds}) {
  final upper = hex.toUpperCase();
  for (final u in allUsers) {
    if (allowedIds.contains(u.id) && u.privateIdHex == upper) return u;
  }
  return null;
}
