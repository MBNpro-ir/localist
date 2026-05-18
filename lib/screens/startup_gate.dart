import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../models/app_settings.dart';
import '../widgets/onboarding_flow.dart';

class StartupGate extends StatefulWidget {
  const StartupGate({
    super.key,
    required this.settings,
    required this.simple,
    required this.child,
  });

  final AppSettings settings;
  final bool simple;
  final Widget child;

  @override
  State<StartupGate> createState() => _StartupGateState();
}

class _StartupGateState extends State<StartupGate> {
  late AppLanguage _selectedLanguage;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selectedLanguage = widget.settings.language;
  }

  @override
  void didUpdateWidget(covariant StartupGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings != widget.settings) {
      _selectedLanguage = widget.settings.language;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.settings.languageSelected) {
      return widget.child;
    }
    final l10n = context.l10n;
    return AnimatedSwitcher(
      duration: widget.simple
          ? Duration.zero
          : const Duration(milliseconds: 320),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeInCubic,
      child: OnboardingFrame(
        key: const ValueKey('language-onboarding'),
        simple: widget.simple,
        steps: [l10n.languageStep, l10n.permissionsStep, l10n.mainStep],
        currentStep: 0,
        icon: Icons.translate,
        title: l10n.languageTitle,
        subtitle: l10n.languageSubtitle,
        children: [
          _LanguageChoiceTile(
            selected: _selectedLanguage == AppLanguage.system,
            flagCode: 'system',
            title: l10n.languageSystem,
            subtitle: l10n.languageSystemSubtitle,
            onTap: () => setState(() => _selectedLanguage = AppLanguage.system),
          ),
          const SizedBox(height: 10),
          _LanguageChoiceTile(
            selected: _selectedLanguage == AppLanguage.english,
            flagCode: 'en',
            title: l10n.languageEnglish,
            subtitle: l10n.languageEnglishSubtitle,
            onTap: () =>
                setState(() => _selectedLanguage = AppLanguage.english),
          ),
          const SizedBox(height: 10),
          _LanguageChoiceTile(
            selected: _selectedLanguage == AppLanguage.persian,
            flagCode: 'fa',
            title: l10n.languagePersian,
            subtitle: l10n.languagePersianSubtitle,
            onTap: () =>
                setState(() => _selectedLanguage = AppLanguage.persian),
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _saving ? null : _saveLanguage,
              icon: _saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.arrow_forward),
              label: Text(l10n.continueButton),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _saveLanguage() async {
    setState(() => _saving = true);
    try {
      await widget.settings.setLanguage(_selectedLanguage);
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }
}

class _LanguageChoiceTile extends StatelessWidget {
  const _LanguageChoiceTile({
    required this.selected,
    required this.flagCode,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  final bool selected;
  final String flagCode;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primaryContainer.withValues(alpha: .82)
          : scheme.surfaceContainerHighest.withValues(alpha: .48),
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              LanguageFlag(languageCode: flagCode),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(context).textTheme.titleSmall),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Icon(
                selected ? Icons.radio_button_checked : Icons.radio_button_off,
                color: selected ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
