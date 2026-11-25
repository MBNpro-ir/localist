import 'package:flutter/material.dart';

class CaptureMicrophoneMode extends StatelessWidget {
  const CaptureMicrophoneMode({
    super.key,
    required this.available,
    required this.selected,
    required this.onChanged,
  });

  final List<String> available;
  final String selected;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String text(String persian, String english) => fa ? persian : english;
    final modes = {
      'default': text('پیش‌فرض اندروید', 'Android default'),
      'mic': text('میکروفون', 'Microphone'),
      'raw': text('خام، بدون پردازش اندروید', 'Raw Android input'),
      'communication': text('مکالمه', 'Voice communication'),
      'performance': text('اجرای زنده و کم‌تأخیر', 'Voice performance'),
      'recognition': text('تشخیص گفتار', 'Voice recognition'),
      'camcorder': text('فیلم‌برداری', 'Camcorder'),
    };
    final visible = available.where(modes.containsKey).toList();
    if (visible.isEmpty) return const SizedBox.shrink();
    final value = visible.contains(selected) ? selected : visible.first;
    return DropdownButtonFormField<String>(
      key: ValueKey('microphone-mode-$value'),
      isExpanded: true,
      initialValue: value,
      decoration: InputDecoration(
        labelText: text('حالت ضبط میکروفون', 'Microphone mode'),
      ),
      items: [
        for (final mode in visible)
          DropdownMenuItem(
            value: mode,
            child: Text(modes[mode]!, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: onChanged == null
          ? null
          : (mode) {
              if (mode != null) onChanged!(mode);
            },
    );
  }
}
