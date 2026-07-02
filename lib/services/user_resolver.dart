import '../data/mock_users.dart';
import '../models/ble_device_model.dart';
import 'account_session.dart';

enum Relationship { me, myChipOff, friend, knownPublic, strangerPrivate, unknown }

class ResolvedDevice {
  final MockUser? user;
  final Relationship relationship;
  final int? mode;
  final bool hasValidPacket;
  final bool isMyChip;

  const ResolvedDevice({
    this.user,
    required this.relationship,
    this.mode,
    required this.hasValidPacket,
    this.isMyChip = false,
  });
}

class UserResolver {
  final AccountSession session;

  UserResolver(this.session);

  ResolvedDevice resolve(BleDeviceModel device) {
    final packet = device.seeuPacket;
    final current = session.currentUser;
    final friends = session.friendIds;

    if (packet == null || !packet.crcValid) {
      return const ResolvedDevice(
        relationship: Relationship.unknown,
        hasValidPacket: false,
      );
    }

    // mode == 0xFF (off): чип в пакете всегда шлёт public_id
    if (packet.isOff) {
      final isMine = packet.idHex == current.publicIdHex;
      if (isMine) {
        return ResolvedDevice(
          user: current,
          relationship: Relationship.myChipOff,
          mode: packet.mode,
          hasValidPacket: true,
          isMyChip: true,
        );
      }
      // Чужой выключенный чип — unknown (будет скрыт в UI)
      return ResolvedDevice(
        relationship: Relationship.unknown,
        mode: packet.mode,
        hasValidPacket: true,
      );
    }

    // mode == 0x00 (public)
    if (packet.isPublic) {
      final isMine = packet.idHex == current.publicIdHex;
      final user = findByPublicId(packet.idHex);

      if (user == null) {
        return ResolvedDevice(
          relationship: Relationship.unknown,
          mode: packet.mode,
          hasValidPacket: true,
        );
      }
      if (user.id == current.id) {
        return ResolvedDevice(
          user: user,
          relationship: Relationship.me,
          mode: packet.mode,
          hasValidPacket: true,
          isMyChip: true,
        );
      }
      if (friends.contains(user.id)) {
        return ResolvedDevice(
          user: user,
          relationship: Relationship.friend,
          mode: packet.mode,
          hasValidPacket: true,
          isMyChip: isMine,
        );
      }
      return ResolvedDevice(
        user: user,
        relationship: Relationship.knownPublic,
        mode: packet.mode,
        hasValidPacket: true,
        isMyChip: isMine,
      );
    }

    // mode == 0x01 (private)
    // Сначала проверяем — не свой ли это чип
    if (packet.idHex == current.privateIdHex) {
      return ResolvedDevice(
        user: current,
        relationship: Relationship.me,
        mode: packet.mode,
        hasValidPacket: true,
        isMyChip: true,
      );
    }

    final user = findByPrivateId(
      packet.idHex,
      allowedIds: friends,
    );
    if (user != null) {
      return ResolvedDevice(
        user: user,
        relationship: Relationship.friend,
        mode: packet.mode,
        hasValidPacket: true,
      );
    }

    return ResolvedDevice(
      relationship: Relationship.strangerPrivate,
      mode: packet.mode,
      hasValidPacket: true,
    );
  }

  /// Сортировка: me/myChipOff=0, friend=1, knownPublic=2, strangerPrivate=3, unknown=4
  int sortOrder(Relationship r) {
    switch (r) {
      case Relationship.me:
        return 0;
      case Relationship.myChipOff:
        return 0;
      case Relationship.friend:
        return 1;
      case Relationship.knownPublic:
        return 2;
      case Relationship.strangerPrivate:
        return 3;
      case Relationship.unknown:
        return 4;
    }
  }
}
