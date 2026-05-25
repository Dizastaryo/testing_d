import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/design/design.dart';
import '../../core/models/sbor.dart';
import 'sbory_widgets.dart';

// ─── Voice participant model ──────────────────────────────────────

enum VoiceMicState { on, muted, deaf }

class VoiceParticipant {
  final String name;
  final bool speaking;
  final VoiceMicState micState;
  final bool isYou;
  final String role;

  const VoiceParticipant({
    required this.name,
    this.speaking = false,
    this.micState = VoiceMicState.on,
    this.isYou = false,
    this.role = '',
  });
}

// ─── Sbor Chat Screen (3-tab: messages / voice / members) ─────────

class SborChatScreen extends ConsumerStatefulWidget {
  final String chatId;
  final String sborTitle;
  final SborCategory? category;
  final int memberCount;

  const SborChatScreen({
    super.key,
    required this.chatId,
    required this.sborTitle,
    this.category,
    this.memberCount = 0,
  });

  @override
  ConsumerState<SborChatScreen> createState() => _SborChatScreenState();
}

class _SborChatScreenState extends ConsumerState<SborChatScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabCtrl;

  // Voice state — in real app this comes from WebSocket
  bool _voiceLive = false;
  bool _youInVoice = false;
  bool _micOn = true;
  bool _speakerOn = true;

  // Mock voice participants (would come from WS in production)
  List<VoiceParticipant> _voiceParticipants = const [];

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _tabCtrl.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;

    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(c),
            _buildTabs(c),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  _MessagesTab(
                    chatId: widget.chatId,
                    voiceLive: _voiceLive,
                    voiceParticipants: _voiceParticipants,
                    onJoinVoice: () => _joinVoice(context),
                    c: c,
                  ),
                  _VoiceTab(
                    voiceLive: _voiceLive,
                    youIn: _youInVoice,
                    participants: _voiceParticipants,
                    micOn: _micOn,
                    speakerOn: _speakerOn,
                    onOpen: () => _joinVoice(context),
                    onLeave: _leaveVoice,
                    onToggleMic: () => setState(() => _micOn = !_micOn),
                    onToggleSpeaker: () => setState(() => _speakerOn = !_speakerOn),
                    c: c,
                  ),
                  _MembersTab(
                    voiceParticipants: _voiceParticipants,
                    c: c,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(SeeUThemeColors c) {
    final meta = widget.category != null
        ? kSborCategories[widget.category]
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 16, 0),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => context.pop(),
            child: SizedBox(
              width: 40, height: 40,
              child: Icon(
                PhosphorIcons.caretLeft(PhosphorIconsStyle.bold),
                size: 18, color: c.ink,
              ),
            ),
          ),
          const SizedBox(width: 4),
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: meta != null
                    ? [meta.color, SeeUColors.amber]
                    : [SeeUColors.accent, SeeUColors.amber],
              ),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(
              meta?.icon ?? PhosphorIcons.usersThree(),
              size: 18, color: Colors.white,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.sborTitle,
                  style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.w600,
                    color: c.ink, letterSpacing: -0.2, height: 1.15,
                  ),
                  maxLines: 1, overflow: TextOverflow.ellipsis,
                ),
                Text(
                  'чат сбора · ${widget.memberCount} участников',
                  style: TextStyle(fontSize: 11, color: c.ink3),
                ),
              ],
            ),
          ),
          GestureDetector(
            onTap: () {},
            child: Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: c.surface,
                shape: BoxShape.circle,
                border: Border.all(color: c.line, width: 0.5),
              ),
              child: Icon(PhosphorIcons.phone(PhosphorIconsStyle.fill), size: 15, color: c.ink),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabs(SeeUThemeColors c) {
    final tabs = [
      (0, 'Сообщения', PhosphorIcons.chatCircleDots()),
      (1, 'Голос', PhosphorIcons.waveform()),
      (2, 'Состав', PhosphorIcons.usersThree()),
    ];

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Container(
        height: 42,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          children: tabs.map((tab) {
            final (i, label, icon) = tab;
            final active = _tabCtrl.index == i;
            final isVoice = i == 1;

            return Expanded(
              child: GestureDetector(
                onTap: () => _tabCtrl.animateTo(i),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  height: 34,
                  decoration: BoxDecoration(
                    color: active ? c.surface : Colors.transparent,
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: active
                        ? [BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 2, offset: const Offset(0, 1))]
                        : null,
                  ),
                  child: Stack(
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(icon, size: 13, color: active ? c.ink : c.ink3),
                          const SizedBox(width: 5),
                          Text(
                            label,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                              color: active ? c.ink : c.ink3,
                            ),
                          ),
                        ],
                      ),
                      if (isVoice && _voiceLive)
                        Positioned(
                          top: 5, right: 8,
                          child: Container(
                            width: 6, height: 6,
                            decoration: BoxDecoration(
                              color: SeeUColors.success,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  void _joinVoice(BuildContext context) {
    HapticFeedback.mediumImpact();
    setState(() {
      _voiceLive = true;
      _youInVoice = true;
      _voiceParticipants = const [
        VoiceParticipant(name: 'Костя', speaking: true),
        VoiceParticipant(name: 'Маша', micState: VoiceMicState.muted),
        VoiceParticipant(name: 'Алекс'),
        VoiceParticipant(name: 'Ты', isYou: true),
      ];
    });
  }

  void _leaveVoice() {
    HapticFeedback.lightImpact();
    setState(() {
      _youInVoice = false;
      _voiceParticipants = const [
        VoiceParticipant(name: 'Костя', speaking: true),
        VoiceParticipant(name: 'Маша', micState: VoiceMicState.muted),
        VoiceParticipant(name: 'Алекс'),
      ];
    });
  }
}

// ─── Messages tab ────────────────────────────────────────────────

class _MessagesTab extends StatelessWidget {
  final String chatId;
  final bool voiceLive;
  final List<VoiceParticipant> voiceParticipants;
  final VoidCallback onJoinVoice;
  final SeeUThemeColors c;

  const _MessagesTab({
    required this.chatId,
    required this.voiceLive,
    required this.voiceParticipants,
    required this.onJoinVoice,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (voiceLive) _buildVoiceStrip(context),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
            children: const [
              // In production this would use the existing ChatScreen message builder
              // via the chat_provider. For Сбор chats, this tab is a wrapper.
              _DaySeparator(label: 'Сегодня'),
              SizedBox(height: 8),
            ],
          ),
        ),
        _buildInputBar(c),
      ],
    );
  }

  Widget _buildVoiceStrip(BuildContext context) {
    final names = voiceParticipants.map((p) => p.name).toList();

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
      child: GestureDetector(
        onTap: onJoinVoice,
        child: Container(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [SeeUColors.accentSoft, c.bg],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: SeeUColors.accentSoft, width: 0.5),
          ),
          child: Row(
            children: [
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  PhosphorIcons.waveform(PhosphorIconsStyle.fill),
                  size: 15, color: Colors.white,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'В голосе · ${_nameList(names)}',
                      style: TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600, color: c.ink,
                      ),
                    ),
                    Text(
                      '${voiceParticipants.length} чел. · обсуждают',
                      style: TextStyle(fontSize: 11, color: c.ink3),
                    ),
                  ],
                ),
              ),
              SboryAvatarStack(names: names.take(3).toList(), size: 22, ringColor: SeeUColors.accentSoft),
              const SizedBox(width: 8),
              Container(
                height: 28,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: SeeUColors.accent,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Center(
                  child: Text(
                    'Зайти',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInputBar(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: Row(
        children: [
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: c.surface,
              shape: BoxShape.circle,
              border: Border.all(color: c.line),
            ),
            child: Icon(
              PhosphorIcons.plus(PhosphorIconsStyle.bold),
              size: 16, color: c.ink2,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Container(
              height: 36,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line),
              ),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  'Написать в чат…',
                  style: TextStyle(fontSize: 14, color: c.ink4),
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          Container(
            width: 36, height: 36,
            decoration: BoxDecoration(
              color: SeeUColors.accent,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.mic, size: 18, color: Colors.white),
          ),
        ],
      ),
    );
  }

  String _nameList(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names.first;
    if (names.length == 2) return '${names[0]} и ${names[1]}';
    return '${names[0]}, ${names[1]} и ещё ${names.length - 2}';
  }
}

// ─── Voice tab ───────────────────────────────────────────────────

class _VoiceTab extends StatelessWidget {
  final bool voiceLive;
  final bool youIn;
  final List<VoiceParticipant> participants;
  final bool micOn;
  final bool speakerOn;
  final VoidCallback onOpen;
  final VoidCallback onLeave;
  final VoidCallback onToggleMic;
  final VoidCallback onToggleSpeaker;
  final SeeUThemeColors c;

  const _VoiceTab({
    required this.voiceLive,
    required this.youIn,
    required this.participants,
    required this.micOn,
    required this.speakerOn,
    required this.onOpen,
    required this.onLeave,
    required this.onToggleMic,
    required this.onToggleSpeaker,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    if (!voiceLive) return _buildEmpty(context);
    if (youIn) return _buildYouIn(context);
    return _buildOthersIn(context);
  }

  Widget _buildEmpty(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 140, height: 140,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: RadialGradient(
                colors: [SeeUColors.accentSoft, c.bg],
                stops: const [0.0, 0.7],
              ),
            ),
            child: Center(
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(
                  color: c.surface,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: SeeUColors.accent.withValues(alpha: 0.7),
                    width: 1.5,
                    style: BorderStyle.solid,
                  ),
                ),
                child: Icon(PhosphorIcons.waveform(), size: 32, color: SeeUColors.accent),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(
            'Голосовая комната тиха',
            style: const TextStyle(
              fontFamily: 'Fraunces',
              fontSize: 24, fontWeight: FontWeight.w500,
              letterSpacing: -0.3, height: 1.2,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 6),
          Text(
            'Зайди первым — остальные увидят, что ты в эфире, и подтянутся.',
            style: TextStyle(fontSize: 14, color: c.ink3, height: 1.4),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: onOpen,
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 22),
              decoration: BoxDecoration(
                color: SeeUColors.accent,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: SeeUColors.accent.withValues(alpha: 0.32),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(PhosphorIcons.microphone(PhosphorIconsStyle.fill), size: 17, color: Colors.white),
                  const SizedBox(width: 8),
                  const Text(
                    'Открыть канал',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(PhosphorIcons.info(), size: 13, color: c.ink4),
              const SizedBox(width: 6),
              Text(
                'Не звонок — комната всегда открыта',
                style: TextStyle(fontSize: 12, color: c.ink4),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildOthersIn(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [SeeUColors.accentSoft, c.bg],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                stops: const [0, 2.2],
              ),
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: SeeUColors.accentSoft, width: 0.5),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: SeeUColors.success,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'В ЭФИРЕ',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        letterSpacing: 1, color: SeeUColors.success,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                Text(
                  _nameList(participants.map((p) => p.name).toList()),
                  style: const TextStyle(
                    fontFamily: 'Fraunces',
                    fontSize: 20, fontWeight: FontWeight.w500,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    for (final p in participants.take(3))
                      Padding(
                        padding: const EdgeInsets.only(right: 14),
                        child: _VoiceTile(participant: p, size: 68, c: c),
                      ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: onOpen,
                        child: Container(
                          height: 46,
                          decoration: BoxDecoration(
                            color: SeeUColors.accent,
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(
                                color: SeeUColors.accent.withValues(alpha: 0.32),
                                blurRadius: 20,
                                offset: const Offset(0, 8),
                              ),
                            ],
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(PhosphorIcons.microphone(PhosphorIconsStyle.fill), size: 15, color: Colors.white),
                              const SizedBox(width: 8),
                              const Text(
                                'Зайти в канал',
                                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 46, height: 46,
                      decoration: BoxDecoration(
                        color: c.surface,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: c.line),
                      ),
                      child: Icon(PhosphorIcons.speakerHigh(), size: 18, color: c.ink),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildYouIn(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: c.ink,
              borderRadius: BorderRadius.circular(22),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 8, height: 8,
                      decoration: BoxDecoration(
                        color: SeeUColors.success,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: SeeUColors.success.withValues(alpha: 0.3),
                            blurRadius: 0, spreadRadius: 3,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'ТЫ В КАНАЛЕ',
                      style: TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        letterSpacing: 1, color: SeeUColors.success,
                      ),
                    ),
                    const Spacer(),
                    Text(
                      '${participants.length} чел.',
                      style: const TextStyle(fontSize: 12, color: Colors.white60),
                    ),
                  ],
                ),
                const SizedBox(height: 14),
                // Tiles grid
                GridView.count(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  crossAxisCount: 4,
                  crossAxisSpacing: 8,
                  mainAxisSpacing: 8,
                  children: participants.map((p) => _VoiceTile(participant: p, size: 64, c: c)).toList(),
                ),
                const SizedBox(height: 14),
                // Controls
                Row(
                  children: [
                    _CtrlBtn(
                      icon: micOn ? PhosphorIcons.microphone(PhosphorIconsStyle.fill) : PhosphorIcons.microphoneSlash(PhosphorIconsStyle.fill),
                      active: micOn,
                      onTap: onToggleMic,
                    ),
                    const SizedBox(width: 8),
                    _CtrlBtn(
                      icon: speakerOn ? PhosphorIcons.speakerHigh(PhosphorIconsStyle.fill) : PhosphorIcons.speakerSlash(PhosphorIconsStyle.fill),
                      active: speakerOn,
                      onTap: onToggleSpeaker,
                    ),
                    const SizedBox(width: 8),
                    _CtrlBtn(
                      icon: PhosphorIcons.arrowsOut(),
                      active: false,
                      onTap: () {},
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: GestureDetector(
                        onTap: onLeave,
                        child: Container(
                          height: 44,
                          decoration: BoxDecoration(
                            color: SeeUColors.like,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(PhosphorIcons.phoneDisconnect(PhosphorIconsStyle.fill), size: 14, color: Colors.white),
                              const SizedBox(width: 6),
                              const Text(
                                'Выйти',
                                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _nameList(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length == 1) return '${names.first} в канале';
    if (names.length == 2) return '${names[0]} и ${names[1]} в канале';
    return '${names[0]}, ${names[1]} и ещё ${names.length - 2} — в канале';
  }
}

// ─── Members tab ─────────────────────────────────────────────────

class _MembersTab extends StatelessWidget {
  final List<VoiceParticipant> voiceParticipants;
  final SeeUThemeColors c;

  const _MembersTab({required this.voiceParticipants, required this.c});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (voiceParticipants.isNotEmpty) ...[
            _SectionLabel(
              'В голосовом канале',
              right: '${voiceParticipants.length} в голосе',
              c: c,
            ),
            const SizedBox(height: 8),
            Container(
              decoration: BoxDecoration(
                color: c.surface,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: c.line, width: 0.5),
              ),
              child: Column(
                children: voiceParticipants.asMap().entries.map((e) {
                  final i = e.key;
                  final p = e.value;
                  return _VoiceMemberRow(
                    participant: p,
                    showBorder: i < voiceParticipants.length - 1,
                    c: c,
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 16),
          ],
          _SectionLabel('В чате · не в голосе', c: c),
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: c.ink4, style: BorderStyle.solid),
            ),
            child: Row(
              children: [
                Icon(PhosphorIcons.userPlus(), size: 16, color: SeeUColors.accent),
                const SizedBox(width: 10),
                Text(
                  'Пригласить ещё людей',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w500, color: c.ink2),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─── Shared voice widgets ─────────────────────────────────────────

class _VoiceTile extends StatelessWidget {
  final VoiceParticipant participant;
  final double size;
  final SeeUThemeColors c;

  const _VoiceTile({required this.participant, required this.size, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final seed = (p.name.codeUnitAt(0) + p.name.length) % SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];
    final avatarSize = size - 12;

    return Column(
      children: [
        SizedBox(
          width: size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                padding: const EdgeInsets.all(3),
                decoration: BoxDecoration(
                  color: p.speaking ? SeeUColors.success : Colors.transparent,
                  shape: BoxShape.circle,
                ),
                child: Container(
                  padding: const EdgeInsets.all(2),
                  decoration: BoxDecoration(
                    color: p.speaking ? c.bg : c.surface,
                    shape: BoxShape.circle,
                  ),
                  child: Container(
                    width: avatarSize, height: avatarSize,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(colors: pal),
                      shape: BoxShape.circle,
                    ),
                    child: Center(
                      child: Text(
                        p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                        style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w600,
                          fontSize: avatarSize * 0.42,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              if (p.micState == VoiceMicState.muted)
                Positioned(
                  bottom: -2, right: -2,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: SeeUColors.like,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c.surface, blurRadius: 0, spreadRadius: 2)],
                    ),
                    child: Icon(PhosphorIcons.microphoneSlash(PhosphorIconsStyle.fill), size: 11, color: Colors.white),
                  ),
                )
              else if (p.micState == VoiceMicState.deaf)
                Positioned(
                  bottom: -2, right: -2,
                  child: Container(
                    width: 22, height: 22,
                    decoration: BoxDecoration(
                      color: c.ink2,
                      shape: BoxShape.circle,
                      boxShadow: [BoxShadow(color: c.surface, blurRadius: 0, spreadRadius: 2)],
                    ),
                    child: Icon(PhosphorIcons.speakerSlash(PhosphorIconsStyle.fill), size: 11, color: Colors.white),
                  ),
                ),
            ],
          ),
        ),
        const SizedBox(height: 6),
        Text(
          p.isYou ? '${p.name} · ты' : p.name,
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            color: p.isYou ? Colors.white70 : Colors.white,
            letterSpacing: -0.1,
          ),
          textAlign: TextAlign.center,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ],
    );
  }
}

class _CtrlBtn extends StatelessWidget {
  final IconData icon;
  final bool active;
  final VoidCallback onTap;

  const _CtrlBtn({required this.icon, required this.active, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: active
              ? Colors.white.withValues(alpha: 0.14)
              : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Icon(icon, size: 17, color: Colors.white),
      ),
    );
  }
}

class _VoiceMemberRow extends StatelessWidget {
  final VoiceParticipant participant;
  final bool showBorder;
  final SeeUThemeColors c;

  const _VoiceMemberRow({required this.participant, required this.showBorder, required this.c});

  @override
  Widget build(BuildContext context) {
    final p = participant;
    final seed = (p.name.codeUnitAt(0) + p.name.length) % SeeUColors.avatarPalettes.length;
    final pal = SeeUColors.avatarPalettes[seed];

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
      decoration: BoxDecoration(
        border: showBorder ? Border(bottom: BorderSide(color: c.line, width: 0.5)) : null,
      ),
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: pal),
                  shape: BoxShape.circle,
                  boxShadow: p.speaking
                      ? [BoxShadow(color: SeeUColors.success, blurRadius: 0, spreadRadius: 3)]
                      : null,
                ),
                child: Center(
                  child: Text(
                    p.name.isNotEmpty ? p.name[0].toUpperCase() : '?',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              Positioned(
                bottom: -2, right: -2,
                child: Container(
                  width: 18, height: 18,
                  decoration: BoxDecoration(
                    color: p.micState == VoiceMicState.muted
                        ? SeeUColors.like
                        : SeeUColors.success,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: c.surface, blurRadius: 0, spreadRadius: 2)],
                  ),
                  child: Icon(
                    p.micState == VoiceMicState.muted
                        ? PhosphorIcons.microphoneSlash(PhosphorIconsStyle.fill)
                        : PhosphorIcons.microphone(PhosphorIconsStyle.fill),
                    size: 9, color: Colors.white,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  p.name,
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: c.ink),
                ),
                Text(
                  p.speaking
                      ? 'говорит сейчас'
                      : p.micState == VoiceMicState.muted
                          ? 'микрофон выключен'
                          : 'слушает',
                  style: TextStyle(
                    fontSize: 11,
                    color: p.speaking ? SeeUColors.success : c.ink3,
                  ),
                ),
              ],
            ),
          ),
          if (p.role.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: SeeUColors.accentSoft,
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                '★ ${p.role}',
                style: const TextStyle(
                  fontSize: 10, fontWeight: FontWeight.w600,
                  color: SeeUColors.accent, letterSpacing: 0.4,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _SectionLabel extends StatelessWidget {
  final String text;
  final String? right;
  final SeeUThemeColors c;

  const _SectionLabel(this.text, {this.right, required this.c});

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          text.toUpperCase(),
          style: TextStyle(
            fontSize: 11, fontWeight: FontWeight.w600,
            letterSpacing: 0.8, color: c.ink3,
          ),
        ),
        if (right != null) ...[
          const Spacer(),
          Text(
            right!,
            style: TextStyle(fontSize: 11, color: c.ink3),
          ),
        ],
      ],
    );
  }
}

class _DaySeparator extends StatelessWidget {
  final String label;
  const _DaySeparator({required this.label});

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Center(
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: c.surface2,
          borderRadius: BorderRadius.circular(999),
        ),
        child: Text(label, style: TextStyle(fontSize: 11, color: c.ink3, fontWeight: FontWeight.w500)),
      ),
    );
  }
}
