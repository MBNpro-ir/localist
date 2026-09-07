import 'dart:io';

import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/glass.dart';

class AppGuidePage extends StatelessWidget {
  const AppGuidePage({super.key, required this.simple});

  final bool simple;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final sections = [
      _GuideSectionData(
        number: '01',
        icon: Icons.share_outlined,
        title: l10n.guideSharingTitle,
        body: Platform.isWindows
            ? l10n.guideSharingWindows
            : l10n.guideSharingAndroid,
        tips: [
          _GuideTip(
            Icons.power_settings_new_outlined,
            _t(
              context,
              'سرویس اشتراک‌گذاری را شروع کنید.',
              'Start the sharing service.',
            ),
          ),
          _GuideTip(
            Icons.wifi_tethering_outlined,
            _t(
              context,
              'هر دو دستگاه باید در یک شبکه قابل دسترس باشند.',
              'Keep both devices reachable on the same network.',
            ),
          ),
        ],
      ),
      _GuideSectionData(
        number: '02',
        icon: Icons.qr_code_2_outlined,
        title: l10n.guideQrTitle,
        body: l10n.guideQrBody,
        tips: [
          _GuideTip(
            Icons.qr_code_scanner_outlined,
            _t(
              context,
              'در دستگاه مقصد کد را اسکن کنید.',
              'Scan the code from the destination device.',
            ),
          ),
          _GuideTip(
            Icons.copy_all_outlined,
            _t(
              context,
              'در صورت نیاز، تنظیمات را کپی و دستی بارگذاری کنید.',
              'If needed, copy the configuration and load it manually.',
            ),
          ),
        ],
      ),
      _GuideSectionData(
        number: '03',
        icon: Icons.send_outlined,
        title: 'Quick Send',
        body: _t(
          context,
          'برای ارسال مستقیم فایل یا پیام بین دستگاه‌های نزدیک، بدون اینترنت، از Quick Send استفاده کنید.',
          'Use Quick Send to transfer files or messages directly between nearby devices without the internet.',
        ),
        tips: [
          _GuideTip(
            Icons.devices_outlined,
            _t(
              context,
              'دستگاه مقصد را انتخاب کنید و فایل‌ها را اضافه کنید.',
              'Choose a nearby device and add files to send.',
            ),
          ),
          _GuideTip(
            Icons.markunread_mailbox_outlined,
            _t(
              context,
              'درخواست‌های ورودی در ابتدای همین صفحه نمایش داده می‌شوند.',
              'Incoming requests appear at the top of the Quick Send page.',
            ),
          ),
        ],
      ),
      _GuideSectionData(
        number: '04',
        icon: Icons.notifications_active_outlined,
        title: _t(
          context,
          'درخواست‌ها و اعلان‌ها',
          'Requests and notifications',
        ),
        body: _t(
          context,
          'اگر درخواست Quick Send در صفحه دیگری برسد، Localist یک اعلان داخلی نشان می‌دهد. در حالت پس‌زمینه، اعلان سیستم مسیر را مستقیماً به درخواست باز می‌کند.',
          'When a Quick Send request arrives on another page, Localist shows an in-app notice. In the background, a system notification opens the request directly.',
        ),
        tips: [
          _GuideTip(
            Icons.touch_app_outlined,
            _t(
              context,
              'با لمس اعلان، برنامه به Quick Send می‌رود و درخواست را نمایش می‌دهد.',
              'Tap the notification to open Quick Send and reveal the request.',
            ),
          ),
          _GuideTip(
            Icons.lock_clock_outlined,
            _t(
              context,
              'مجوز اعلان اندروید را برای دریافت اعلان‌های بیرونی فعال کنید.',
              'Allow Android notifications so background requests can reach you.',
            ),
          ),
        ],
      ),
      _GuideSectionData(
        number: '05',
        icon: Icons.tune_outlined,
        title: l10n.settings,
        body: _t(
          context,
          'تنظیمات از دکمه بالای صفحه در دسترس است و در یک صفحه مستقل باز می‌شود.',
          'Open Settings from the top bar; it is presented as a separate page.',
        ),
        tips: [
          _GuideTip(
            Icons.palette_outlined,
            _t(
              context,
              'ظاهر، زبان و رفتار بستن پنجره را تنظیم کنید.',
              'Adjust appearance, language, and window-close behavior.',
            ),
          ),
          _GuideTip(
            Icons.system_update_alt_outlined,
            _t(
              context,
              'گزارش‌ها و به‌روزرسانی برنامه را از همین صفحه مدیریت کنید.',
              'Manage app updates and diagnostic details from this page.',
            ),
          ),
        ],
      ),
      _GuideSectionData(
        number: '06',
        icon: Icons.shield_outlined,
        title: l10n.guideStartVpnTitle,
        body: l10n.guideStartVpnBody,
        tips: [
          _GuideTip(
            Icons.sync_problem_outlined,
            _t(
              context,
              'سرویس‌های اشتراک‌گذاری و دریافت هم‌زمان اجرا نمی‌شوند.',
              'Sharing and receiving services are mutually exclusive.',
            ),
          ),
          _GuideTip(
            Icons.subject_outlined,
            _t(
              context,
              'برای عیب‌یابی، گزارش‌ها را از دکمه بالای صفحه باز کنید.',
              'Open Logs from the top bar when troubleshooting.',
            ),
          ),
        ],
      ),
    ];

    return GlassBackground(
      simple: simple,
      child: Scaffold(
        backgroundColor: simple
            ? Theme.of(context).colorScheme.surface
            : Colors.transparent,
        appBar: GlassAppBar(
          title: Text(l10n.appGuide),
          actions: Platform.isWindows
              ? [
                  IconButton(
                    tooltip: l10n.close,
                    onPressed: () => Navigator.of(context).maybePop(),
                    icon: const Icon(Icons.arrow_back),
                  ),
                ]
              : null,
        ),
        body: PageSurface(
          children: [
            _GuideHero(simple: simple),
            for (final section in sections) _GuideSectionCard(data: section),
            GlassPanel(
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle_outline,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      _t(
                        context,
                        'هر زمان خواستید، این راهنما از آیکون علامت سؤال بالای برنامه دوباره در دسترس است.',
                        'You can reopen this guide anytime from the help icon in the top bar.',
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  FilledButton(
                    onPressed: () => Navigator.of(context).maybePop(),
                    child: Text(l10n.gotIt),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GuideHero extends StatelessWidget {
  const _GuideHero({required this.simple});

  final bool simple;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = context.l10n;
    return GlassPanel(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(18),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(14),
                  child: Icon(
                    Icons.auto_awesome,
                    color: scheme.onPrimaryContainer,
                    size: 28,
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.guideWelcome,
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      _t(
                        context,
                        'یک مسیر کوتاه برای آشنایی با اتصال، انتقال فایل و اعلان‌های Localist.',
                        'A quick, visual tour of Localist connections, transfers, and notifications.',
                      ),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 18),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _GuideChip(icon: Icons.share_outlined, label: l10n.sharing),
              _GuideChip(icon: Icons.qr_code_2_outlined, label: l10n.receiving),
              const _GuideChip(icon: Icons.send_outlined, label: 'Quick Send'),
              _GuideChip(icon: Icons.tune_outlined, label: l10n.settings),
            ],
          ),
          if (!simple) ...[
            const SizedBox(height: 18),
            ClipRRect(
              borderRadius: BorderRadius.circular(99),
              child: LinearProgressIndicator(
                minHeight: 5,
                value: 1,
                backgroundColor: scheme.surfaceContainerHighest.withValues(
                  alpha: .55,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _GuideChip extends StatelessWidget {
  const _GuideChip({required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: .62),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: .5)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 7),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: scheme.primary),
            const SizedBox(width: 6),
            Text(label, style: Theme.of(context).textTheme.labelMedium),
          ],
        ),
      ),
    );
  }
}

class _GuideSectionData {
  const _GuideSectionData({
    required this.number,
    required this.icon,
    required this.title,
    required this.body,
    required this.tips,
  });

  final String number;
  final IconData icon;
  final String title;
  final String body;
  final List<_GuideTip> tips;
}

class _GuideTip {
  const _GuideTip(this.icon, this.text);

  final IconData icon;
  final String text;
}

class _GuideSectionCard extends StatelessWidget {
  const _GuideSectionCard({required this.data});

  final _GuideSectionData data;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GlassPanel(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  color: scheme.primaryContainer.withValues(alpha: .78),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: SizedBox(
                  width: 52,
                  height: 52,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      Icon(data.icon, color: scheme.onPrimaryContainer),
                      Positioned(
                        right: 4,
                        top: 3,
                        child: Text(
                          data.number,
                          style: Theme.of(context).textTheme.labelSmall
                              ?.copyWith(
                                color: scheme.onPrimaryContainer.withValues(
                                  alpha: .76,
                                ),
                                fontWeight: FontWeight.w800,
                              ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      data.title,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Text(data.body),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          for (final tip in data.tips) ...[
            _GuideTipRow(tip: tip),
            if (tip != data.tips.last) const SizedBox(height: 10),
          ],
        ],
      ),
    );
  }
}

class _GuideTipRow extends StatelessWidget {
  const _GuideTipRow({required this.tip});

  final _GuideTip tip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(tip.icon, size: 18, color: scheme.primary),
        const SizedBox(width: 10),
        Expanded(
          child: Text(tip.text, style: Theme.of(context).textTheme.bodySmall),
        ),
      ],
    );
  }
}

String _t(BuildContext context, String persian, String english) {
  return context.l10n.isPersian ? persian : english;
}
