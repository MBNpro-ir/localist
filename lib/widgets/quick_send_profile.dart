import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../l10n/app_localizations.dart';
import '../models/quick_send_settings.dart';
import '../services/quick_send_service.dart';
import 'onboarding_flow.dart';

const quickSendAvatarPresets = <String>[
  'person',
  'face',
  'pets',
  'rocket',
  'gaming',
  'spark',
];

IconData quickSendAvatarIcon(String preset) {
  return switch (preset) {
    'face' => Icons.face_6_rounded,
    'pets' => Icons.pets_rounded,
    'rocket' => Icons.rocket_launch_rounded,
    'gaming' => Icons.sports_esports_rounded,
    'spark' => Icons.auto_awesome_rounded,
    _ => Icons.person_rounded,
  };
}

class QuickSendAvatar extends StatelessWidget {
  const QuickSendAvatar({
    super.key,
    required this.preset,
    required this.colorValue,
    this.imagePath = '',
    this.imageBase64 = '',
    this.size = 56,
  });

  final String preset;
  final int colorValue;
  final String imagePath;
  final String imageBase64;
  final double size;

  @override
  Widget build(BuildContext context) {
    final background = Color(colorValue);
    final foreground =
        ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : Colors.black87;
    final image = imagePath.trim().isEmpty ? null : File(imagePath);
    final hasImage = image?.existsSync() == true;
    final memoryImage = hasImage ? null : _decodeAvatarImage(imageBase64);
    return Semantics(
      image: true,
      label: context.l10n.isPersian ? 'آواتار دستگاه' : 'Device avatar',
      child: AnimatedContainer(
        duration: _motionDuration(context, 420),
        curve: Curves.easeInOutCubicEmphasized,
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: background,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(
              context,
            ).colorScheme.outlineVariant.withValues(alpha: .7),
          ),
          boxShadow: [
            BoxShadow(
              color: background.withValues(alpha: .24),
              blurRadius: 18,
              offset: const Offset(0, 7),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: hasImage
            ? Image.file(
                image!,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  quickSendAvatarIcon(preset),
                  color: foreground,
                  size: size * .48,
                ),
              )
            : memoryImage != null
            ? Image.memory(
                memoryImage,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => Icon(
                  quickSendAvatarIcon(preset),
                  color: foreground,
                  size: size * .48,
                ),
              )
            : Icon(
                quickSendAvatarIcon(preset),
                color: foreground,
                size: size * .48,
              ),
      ),
    );
  }
}

class QuickSendProfileEditor extends StatelessWidget {
  const QuickSendProfileEditor({
    super.key,
    required this.nameController,
    required this.avatarPreset,
    required this.avatarColorValue,
    required this.profileImagePath,
    required this.onNameChanged,
    required this.onPresetChanged,
    required this.onColorChanged,
    required this.onImageChanged,
    this.nameError,
    this.showHeading = true,
  });

  final TextEditingController nameController;
  final String avatarPreset;
  final int avatarColorValue;
  final String profileImagePath;
  final ValueChanged<String> onNameChanged;
  final ValueChanged<String> onPresetChanged;
  final ValueChanged<int> onColorChanged;
  final ValueChanged<String> onImageChanged;
  final String? nameError;
  final bool showHeading;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = <Color>[
      scheme.primary,
      scheme.tertiary,
      const Color(0xFF006A6A),
      const Color(0xFF6750A4),
      const Color(0xFF9C4146),
      const Color(0xFF386A20),
      const Color(0xFF825500),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (showHeading) ...[
          Text(
            _t(context, 'پروفایل Quick Send', 'Quick Send profile'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 4),
          Text(
            _t(
              context,
              'نام و تصویری که این دستگاه در Quick Send استفاده می‌کند.',
              'Choose the name and avatar used by this device in Quick Send.',
            ),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            QuickSendAvatar(
              preset: avatarPreset,
              colorValue: avatarColorValue,
              imagePath: profileImagePath,
              size: 72,
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  FilledButton.tonalIcon(
                    onPressed: () => _pickImage(context),
                    icon: const Icon(Icons.add_photo_alternate_outlined),
                    label: Text(_t(context, 'انتخاب تصویر', 'Choose photo')),
                  ),
                  if (profileImagePath.isNotEmpty)
                    TextButton.icon(
                      onPressed: () => onImageChanged(''),
                      icon: const Icon(Icons.hide_image_outlined),
                      label: Text(_t(context, 'حذف تصویر', 'Remove photo')),
                    ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 18),
        TextField(
          controller: nameController,
          textInputAction: TextInputAction.done,
          maxLines: 1,
          inputFormatters: [
            FilteringTextInputFormatter.deny(RegExp(r'[\x00-\x1F\x7F]')),
            LengthLimitingTextInputFormatter(
              QuickSendSettings.maxAliasCharacters,
            ),
          ],
          decoration: InputDecoration(
            labelText: _t(context, 'نام دستگاه', 'Device name'),
            prefixIcon: const Icon(Icons.badge_outlined),
            helperText: _t(
              context,
              'حداکثر ${QuickSendSettings.maxAliasCharacters} کاراکتر؛ ایموجی مجاز است.',
              'Up to ${QuickSendSettings.maxAliasCharacters} characters; emoji is supported.',
            ),
            errorText: nameError,
          ),
          onChanged: onNameChanged,
        ),
        const SizedBox(height: 18),
        Text(
          _t(context, 'آواتار', 'Avatar'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final preset in quickSendAvatarPresets)
              _AvatarPresetButton(
                preset: preset,
                selected: preset == avatarPreset,
                colorValue: avatarColorValue,
                onPressed: () {
                  onImageChanged('');
                  onPresetChanged(preset);
                },
              ),
          ],
        ),
        const SizedBox(height: 18),
        Text(
          _t(context, 'رنگ آواتار', 'Avatar color'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final color in colors)
              _AvatarColorButton(
                color: color,
                selected: color.toARGB32() == avatarColorValue,
                onPressed: () => onColorChanged(color.toARGB32()),
              ),
          ],
        ),
      ],
    );
  }

  Future<void> _pickImage(BuildContext context) async {
    try {
      final result = await FilePicker.pickFile(type: FileType.image);
      final sourcePath = result?.path;
      if (sourcePath == null || sourcePath.trim().isEmpty) {
        return;
      }
      final source = File(sourcePath);
      if (!await source.exists()) {
        return;
      }
      final support = await getApplicationSupportDirectory();
      final directory = Directory(p.join(support.path, 'quick-send-profile'));
      await directory.create(recursive: true);
      final codec = await ui.instantiateImageCodec(
        await source.readAsBytes(),
        targetWidth: 64,
        targetHeight: 64,
      );
      final frame = await codec.getNextFrame();
      final data = await frame.image.toByteData(format: ui.ImageByteFormat.png);
      frame.image.dispose();
      codec.dispose();
      if (data == null) {
        throw const FormatException('The selected image could not be decoded.');
      }
      final destination = File(p.join(directory.path, 'avatar.png'));
      await destination.writeAsBytes(data.buffer.asUint8List(), flush: true);
      if (!context.mounted) {
        return;
      }
      onImageChanged(destination.path);
    } catch (error) {
      if (!context.mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _t(
              context,
              'انتخاب تصویر انجام نشد: $error',
              'The profile photo could not be selected: $error',
            ),
          ),
        ),
      );
    }
  }
}

class QuickSendProfileGate extends StatefulWidget {
  const QuickSendProfileGate({
    super.key,
    required this.child,
    required this.simple,
  });

  final Widget child;
  final bool simple;

  @override
  State<QuickSendProfileGate> createState() => _QuickSendProfileGateState();
}

class _QuickSendProfileGateState extends State<QuickSendProfileGate> {
  final _service = QuickSendService.instance;
  final _nameController = TextEditingController();
  bool _loading = true;
  bool _complete = false;
  bool _saving = false;
  bool _validate = false;
  String _avatarPreset = 'person';
  int _avatarColorValue = 0xFF006A6A;
  String _profileImagePath = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _service.initialize();
    final settings = _service.settings;
    if (!mounted || settings == null) {
      return;
    }
    _nameController.text = settings.alias;
    setState(() {
      _avatarPreset = settings.avatarPreset;
      _avatarColorValue = settings.avatarColorValue;
      _profileImagePath = settings.profileImagePath;
      _complete = settings.profileSetupCompleted;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    if (_complete) {
      return widget.child;
    }
    final isAndroid = Platform.isAndroid;
    final steps = isAndroid
        ? [
            _t(context, 'زبان', 'Language'),
            _t(context, 'دسترسی‌ها', 'Permissions'),
            _t(context, 'پروفایل', 'Profile'),
            _t(context, 'برنامه', 'Localist'),
          ]
        : [
            _t(context, 'زبان', 'Language'),
            _t(context, 'پروفایل', 'Profile'),
            _t(context, 'برنامه', 'Localist'),
          ];
    return OnboardingFrame(
      simple: widget.simple,
      steps: steps,
      currentStep: isAndroid ? 2 : 1,
      icon: Icons.account_circle_outlined,
      title: _t(context, 'دستگاه خود را معرفی کنید', 'Set up this device'),
      subtitle: _t(
        context,
        'این نام و آواتار در Quick Send نمایش داده می‌شود و بعداً از تنظیمات قابل تغییر است.',
        'This name and avatar identify the device in Quick Send and can be changed later in Settings.',
      ),
      children: [
        QuickSendProfileEditor(
          nameController: _nameController,
          avatarPreset: _avatarPreset,
          avatarColorValue: _avatarColorValue,
          profileImagePath: _profileImagePath,
          nameError: _validate ? _nameError : null,
          showHeading: false,
          onNameChanged: (_) {
            if (_validate) {
              setState(() {});
            }
          },
          onPresetChanged: (value) => setState(() => _avatarPreset = value),
          onColorChanged: (value) => setState(() => _avatarColorValue = value),
          onImageChanged: (value) => setState(() => _profileImagePath = value),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.arrow_forward_rounded),
            label: Text(_t(context, 'ورود به Localist', 'Enter Localist')),
          ),
        ),
      ],
    );
  }

  String? get _nameError {
    return switch (QuickSendSettings.validateAlias(_nameController.text)) {
      'empty' => _t(
        context,
        'نام دستگاه را وارد کنید.',
        'Enter a device name.',
      ),
      'tooLong' => _t(
        context,
        'نام دستگاه بیش از حد طولانی است.',
        'The device name is too long.',
      ),
      'controlCharacter' => _t(
        context,
        'نام دستگاه کاراکتر نامعتبر دارد.',
        'The device name contains unsupported characters.',
      ),
      _ => null,
    };
  }

  Future<void> _save() async {
    setState(() => _validate = true);
    if (_nameError != null) {
      return;
    }
    final current = _service.settings;
    if (current == null) {
      return;
    }
    setState(() => _saving = true);
    try {
      await _service.updateSettings(
        current.copyWith(
          alias: _nameController.text.trim(),
          avatarPreset: _avatarPreset,
          avatarColorValue: _avatarColorValue,
          profileImagePath: _profileImagePath,
          profileSetupCompleted: true,
        ),
      );
      if (mounted) {
        setState(() => _complete = true);
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _AvatarPresetButton extends StatelessWidget {
  const _AvatarPresetButton({
    required this.preset,
    required this.selected,
    required this.colorValue,
    required this.onPressed,
  });

  final String preset;
  final bool selected;
  final int colorValue;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Semantics(
      button: true,
      selected: selected,
      label: preset,
      child: Material(
        color: selected ? scheme.primaryContainer : scheme.surfaceContainerHigh,
        shape: CircleBorder(
          side: BorderSide(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Padding(
            padding: const EdgeInsets.all(7),
            child: QuickSendAvatar(
              preset: preset,
              colorValue: colorValue,
              size: 42,
            ),
          ),
        ),
      ),
    );
  }
}

class _AvatarColorButton extends StatelessWidget {
  const _AvatarColorButton({
    required this.color,
    required this.selected,
    required this.onPressed,
  });

  final Color color;
  final bool selected;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: color.toARGB32().toRadixString(16),
      child: InkResponse(
        onTap: onPressed,
        radius: 25,
        child: AnimatedContainer(
          duration: _motionDuration(context, 320),
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected
                  ? Theme.of(context).colorScheme.onSurface
                  : Theme.of(context).colorScheme.outlineVariant,
              width: selected ? 3 : 1,
            ),
          ),
          child: selected
              ? Icon(
                  Icons.check_rounded,
                  color:
                      ThemeData.estimateBrightnessForColor(color) ==
                          Brightness.dark
                      ? Colors.white
                      : Colors.black,
                )
              : null,
        ),
      ),
    );
  }
}

Duration _motionDuration(BuildContext context, int milliseconds) {
  return MediaQuery.disableAnimationsOf(context)
      ? Duration.zero
      : Duration(milliseconds: milliseconds);
}

String _t(BuildContext context, String fa, String en) {
  return context.l10n.isPersian ? fa : en;
}

Uint8List? _decodeAvatarImage(String value) {
  if (value.isEmpty || value.length > 32 * 1024) {
    return null;
  }
  try {
    return base64Decode(value);
  } catch (_) {
    return null;
  }
}
