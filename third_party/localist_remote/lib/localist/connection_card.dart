import 'package:flutter/material.dart';
import 'connection_info.dart';

/// Shared identity presentation for the host app and embedded engine.
class LocalistConnectionCard extends StatefulWidget {
  const LocalistConnectionCard(
      {super.key,
      required this.id,
      required this.password,
      required this.onCopyId,
      required this.onCopyPassword,
      required this.onCopyConnection});

  final String id;
  final String password;
  final VoidCallback? onCopyId;
  final VoidCallback? onCopyPassword;
  final VoidCallback? onCopyConnection;

  @override
  State<LocalistConnectionCard> createState() => _LocalistConnectionCardState();
}

class _LocalistConnectionCardState extends State<LocalistConnectionCard> {
  bool _reveal = false;

  @override
  Widget build(BuildContext context) {
    final fa = Localizations.localeOf(context).languageCode == 'fa';
    String t(String f, String e) => fa ? f : e;
    final colors = Theme.of(context).colorScheme;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(children: [
        Icon(Icons.devices_rounded, color: colors.primary),
        const SizedBox(width: 10),
        Expanded(
            child: Text(t('این دستگاه', 'This device'),
                style: Theme.of(context).textTheme.titleMedium)),
      ]),
      const SizedBox(height: 16),
      Text(t('شناسهٔ شما', 'Your ID')),
      const SizedBox(height: 6),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
            color: colors.primaryContainer,
            borderRadius: BorderRadius.circular(16)),
        child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerLeft,
            child: SelectableText(
                widget.id.isEmpty
                    ? '—'
                    : RemoteConnectionInfo.displayId(widget.id),
                textDirection: TextDirection.ltr,
                style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: colors.onPrimaryContainer))),
      ),
      Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
              onPressed: widget.onCopyId,
              icon: const Icon(Icons.content_copy_rounded, size: 18),
              label: Text(t('کپی شناسه', 'Copy ID')))),
      const SizedBox(height: 4),
      Text(t('رمز یک‌بارمصرف', 'One-time password')),
      Row(children: [
        Expanded(
            child: Text(
                widget.password.isEmpty
                    ? '—'
                    : _reveal
                        ? widget.password
                        : '•' * widget.password.length,
                textDirection: TextDirection.ltr,
                style: Theme.of(context).textTheme.titleLarge)),
        IconButton(
            onPressed: widget.password.isEmpty
                ? null
                : () => setState(() => _reveal = !_reveal),
            tooltip: _reveal
                ? t('پنهان کردن رمز', 'Hide password')
                : t('نمایش رمز', 'Show password'),
            icon: Icon(_reveal
                ? Icons.visibility_off_outlined
                : Icons.visibility_outlined)),
      ]),
      Align(
          alignment: AlignmentDirectional.centerStart,
          child: TextButton.icon(
              onPressed: widget.onCopyPassword,
              icon: const Icon(Icons.content_copy_rounded, size: 18),
              label: Text(t('کپی رمز', 'Copy password')))),
      const SizedBox(height: 8),
      FilledButton.icon(
          onPressed: widget.onCopyConnection,
          icon: const Icon(Icons.copy_all_rounded),
          label: Text(t('کپی اطلاعات اتصال', 'Copy connection'),
              textAlign: TextAlign.center)),
      const SizedBox(height: 8),
      Text(
          widget.password.isEmpty
              ? t('برای دریافت رمز، میزبانی را فعال کنید. در حالت تأیید دستی یا رمز دائمی، رمز یک‌بارمصرف نمایش داده نمی‌شود.',
                  'Start hosting to get a password. Approval-only and permanent-password modes do not expose a one-time password.')
              : t('در دستگاه مقصد «چسباندن و اتصال» را بزنید تا شناسه و رمز با هم وارد شوند.',
                  'On the other device, choose Paste & connect to use the ID and password together.'),
          style: Theme.of(context).textTheme.bodySmall),
    ]);
  }
}
