import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';
import 'package:phosphor_flutter/phosphor_flutter.dart';

import '../../core/api/api_client.dart';
import '../../core/api/api_endpoints.dart';
import '../../core/design/design.dart';
import '../../core/models/room.dart';
import '../../core/providers/room_provider.dart';
import '../../core/utils/format.dart';

/// Создание комнаты — один шаг: обложка, название, описание.
/// Приглашений больше нет: после создания участники входят по КОДУ комнаты
/// (код виден в экране участников, им можно поделиться).
class RoomCreateScreen extends ConsumerStatefulWidget {
  const RoomCreateScreen({super.key});

  @override
  ConsumerState<RoomCreateScreen> createState() => _RoomCreateScreenState();
}

class _RoomCreateScreenState extends ConsumerState<RoomCreateScreen> {
  final _nameCtrl = TextEditingController();
  final _descCtrl = TextEditingController();

  XFile? _coverImage;
  bool _creating = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl.addListener(_onNameChanged);
  }

  void _onNameChanged() => setState(() {});

  @override
  void dispose() {
    _nameCtrl.removeListener(_onNameChanged);
    _nameCtrl.dispose();
    _descCtrl.dispose();
    super.dispose();
  }

  bool get _canCreate => _nameCtrl.text.trim().isNotEmpty && !_creating;

  Future<void> _pickCoverImage() async {
    HapticFeedback.selectionClick();
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 1080,
      maxHeight: 1080,
      imageQuality: 85,
    );
    if (file != null && mounted) setState(() => _coverImage = file);
  }

  Future<void> _create() async {
    if (!_canCreate) return;
    HapticFeedback.mediumImpact();
    setState(() => _creating = true);
    try {
      final api = ref.read(apiClientProvider);

      String coverUrl = '';
      if (_coverImage != null) {
        final formData = FormData.fromMap({
          'file': await MultipartFile.fromFile(
            _coverImage!.path,
            filename: _coverImage!.name,
          ),
        });
        final up = await api.post(ApiEndpoints.mediaUpload, data: formData);
        final upData = up.data is Map ? up.data : {};
        coverUrl = (upData['data']?['url'] ?? upData['url'] ?? '') as String;
      }

      final resp = await api.post(ApiEndpoints.rooms, data: {
        'name': _nameCtrl.text.trim(),
        'description': _descCtrl.text.trim(),
        if (coverUrl.isNotEmpty) 'cover_url': coverUrl,
      });
      final data = resp.data is Map && resp.data.containsKey('data')
          ? resp.data['data'] as Map<String, dynamic>
          : resp.data as Map<String, dynamic>;
      final room = Room.fromJson(data);
      ref.read(roomListProvider.notifier).addRoom(room);

      if (!mounted) return;
      context.replace('/room/${room.id}');
    } catch (e) {
      if (!mounted) return;
      setState(() => _creating = false);
      showSeeUSnackBar(context, friendlyError(e), tone: SeeUTone.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        child: Column(
          children: [
            SeeUGlassBar(
              kicker: 'НОВАЯ КОМНАТА',
              titleText: 'Настройка',
              leading: Tappable.faded(
                onTap: () => Navigator.of(context).pop(),
                child: Padding(
                  padding: const EdgeInsets.all(8),
                  child: Icon(PhosphorIcons.x(PhosphorIconsStyle.bold),
                      size: 20, color: c.ink),
                ),
              ),
            ),
            Expanded(child: _buildInfoPage(c)),
            _buildBottomBar(c),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoPage(SeeUThemeColors c) {
    return ListView(
      children: [
        _buildCoverHero(c),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 24, 18, 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _SectionLabel('НАЗВАНИЕ'),
              const SizedBox(height: 8),
              _InputField(
                controller: _nameCtrl,
                hintText: 'Например, «Flutter Казахстан»',
                maxLength: 40,
                autofocus: true,
                c: c,
                showCounter: true,
              ),
              const SizedBox(height: 16),
              _SectionLabel('ОПИСАНИЕ'),
              const SizedBox(height: 8),
              _InputField(
                controller: _descCtrl,
                hintText: 'О чём эта комната? (необязательно)',
                maxLength: 500,
                maxLines: 4,
                fieldHeight: 88,
                c: c,
              ),
              const SizedBox(height: 26),
              _buildInfoCard(c),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildCoverHero(SeeUThemeColors c) {
    return GestureDetector(
      onTap: _coverImage == null ? _pickCoverImage : null,
      child: SizedBox(
        height: 210,
        width: double.infinity,
        child: _coverImage != null
            ? Stack(
                fit: StackFit.expand,
                children: [
                  Image.file(File(_coverImage!.path), fit: BoxFit.cover),
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x80000000)],
                        stops: [0.4, 1.0],
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    right: 14,
                    child: GestureDetector(
                      onTap: _pickCoverImage,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 13, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          borderRadius: BorderRadius.circular(SeeURadii.pill),
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(PhosphorIconsRegular.camera,
                                size: 13, color: Colors.white),
                            const SizedBox(width: 5),
                            const Text('Изменить',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.white,
                                    fontWeight: FontWeight.w600)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Positioned(
                    bottom: 14,
                    left: 14,
                    child: GestureDetector(
                      onTap: () => setState(() => _coverImage = null),
                      child: Container(
                        width: 32,
                        height: 32,
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.52),
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: Colors.white.withValues(alpha: 0.2),
                              width: 0.5),
                        ),
                        child: Icon(PhosphorIconsBold.x,
                            size: 13, color: Colors.white),
                      ),
                    ),
                  ),
                ],
              )
            : Container(
                decoration: BoxDecoration(gradient: SeeUGradients.heroOrange),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        PhosphorIconsRegular.camera,
                        size: 25,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 13),
                    Text(
                      'Добавить обложку',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: Colors.white.withValues(alpha: 0.92),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Необязательно',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.white.withValues(alpha: 0.55),
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }

  Widget _buildInfoCard(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SeeUColors.accent.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(SeeURadii.medium),
        border: Border.all(color: SeeUColors.accent.withValues(alpha: 0.18)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: SeeUColors.accent.withValues(alpha: 0.13),
              shape: BoxShape.circle,
            ),
            child: Icon(PhosphorIconsRegular.info,
                size: 15, color: SeeUColors.accent),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: RichText(
              text: TextSpan(
                style: TextStyle(fontSize: 12.5, color: c.ink2, height: 1.55),
                children: [
                  const TextSpan(text: 'Внутри сразу появятся '),
                  TextSpan(
                    text: 'текстовый чат',
                    style:
                        TextStyle(color: c.ink, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(text: ' и '),
                  TextSpan(
                    text: 'голосовой канал',
                    style:
                        TextStyle(color: c.ink, fontWeight: FontWeight.w700),
                  ),
                  const TextSpan(
                      text:
                          '. После создания поделись кодом комнаты — по нему заходят другие.'),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomBar(SeeUThemeColors c) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 20),
      decoration: BoxDecoration(
        color: c.bg,
        border: Border(top: BorderSide(color: c.line, width: 0.5)),
      ),
      child: GestureDetector(
        onTap: _canCreate ? _create : null,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          height: 52,
          decoration: BoxDecoration(
            gradient: _canCreate ? SeeUGradients.heroOrange : null,
            color: _canCreate ? null : c.surface2,
            borderRadius: BorderRadius.circular(SeeURadii.small),
            boxShadow: _canCreate
                ? [
                    BoxShadow(
                      color: SeeUColors.accent.withValues(alpha: 0.34),
                      offset: const Offset(0, 6),
                      blurRadius: 18,
                    )
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: _creating
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5),
                )
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      PhosphorIcons.usersThree(PhosphorIconsStyle.bold),
                      size: 18,
                      color: _canCreate ? Colors.white : c.ink3,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Создать комнату',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                        color: _canCreate ? Colors.white : c.ink3,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ─── Sub-widgets ──────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  final String text;
  const _SectionLabel(this.text);

  @override
  Widget build(BuildContext context) {
    final c = context.seeuColors;
    return Text(
      text,
      style: TextStyle(
        fontSize: 10,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: c.ink3,
      ),
    );
  }
}

class _InputField extends StatelessWidget {
  final TextEditingController controller;
  final String hintText;
  final int maxLength;
  final int maxLines;
  final bool autofocus;
  final bool showCounter;
  final double? fieldHeight;
  final SeeUThemeColors c;

  const _InputField({
    required this.controller,
    required this.hintText,
    required this.maxLength,
    this.maxLines = 1,
    this.autofocus = false,
    this.showCounter = false,
    this.fieldHeight,
    required this.c,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: fieldHeight,
      decoration: BoxDecoration(
        color: c.surface2,
        borderRadius: BorderRadius.circular(SeeURadii.small),
        border: Border.all(color: c.line, width: 0.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              autofocus: autofocus,
              maxLength: maxLength,
              maxLines: maxLines,
              style: TextStyle(fontSize: 15, color: c.ink),
              decoration: InputDecoration(
                hintText: hintText,
                hintStyle: TextStyle(fontSize: 15, color: c.ink3),
                border: InputBorder.none,
                contentPadding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                counterText: '',
              ),
            ),
          ),
          if (showCounter)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Text(
                '${controller.text.length}/$maxLength',
                style: TextStyle(fontSize: 12, color: c.ink3),
              ),
            ),
        ],
      ),
    );
  }
}
