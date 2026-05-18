import 'package:flutter/material.dart';

import 'glass.dart';

class OnboardingFrame extends StatelessWidget {
  const OnboardingFrame({
    super.key,
    required this.simple,
    required this.steps,
    required this.currentStep,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.children,
    this.onBack,
  });

  final bool simple;
  final List<String> steps;
  final int currentStep;
  final IconData icon;
  final String title;
  final String subtitle;
  final List<Widget> children;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return GlassBackground(
      simple: simple,
      child: Scaffold(
        backgroundColor: simple
            ? Theme.of(context).colorScheme.surface
            : Colors.transparent,
        body: SafeArea(
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 560),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 24),
                shrinkWrap: true,
                children: [
                  _OnboardingEntrance(
                    simple: simple,
                    child: OnboardingStepIndicator(
                      steps: steps,
                      currentStep: currentStep,
                    ),
                  ),
                  const SizedBox(height: 14),
                  _OnboardingEntrance(
                    simple: simple,
                    delay: const Duration(milliseconds: 80),
                    child: GlassPanel(
                      padding: const EdgeInsets.fromLTRB(20, 18, 20, 20),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              if (onBack != null) ...[
                                IconButton.filledTonal(
                                  tooltip: MaterialLocalizations.of(
                                    context,
                                  ).backButtonTooltip,
                                  onPressed: onBack,
                                  icon: const Icon(Icons.arrow_back),
                                ),
                                const SizedBox(width: 10),
                              ],
                              _OnboardingIcon(icon: icon),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      title,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.headlineSmall,
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      subtitle,
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyMedium,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 18),
                          ...children,
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class OnboardingStepIndicator extends StatelessWidget {
  const OnboardingStepIndicator({
    super.key,
    required this.steps,
    required this.currentStep,
  });

  final List<String> steps;
  final int currentStep;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      children: [
        for (var index = 0; index < steps.length; index++) ...[
          if (index > 0)
            Expanded(
              child: Container(
                height: 1,
                color: scheme.outlineVariant.withValues(alpha: .62),
              ),
            ),
          AnimatedContainer(
            duration: const Duration(milliseconds: 240),
            curve: Curves.easeOutCubic,
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: index == currentStep
                  ? scheme.primaryContainer
                  : scheme.surfaceContainerHighest.withValues(alpha: .72),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                color: index == currentStep
                    ? scheme.primary.withValues(alpha: .32)
                    : scheme.outlineVariant.withValues(alpha: .44),
              ),
            ),
            child: Text(
              steps[index],
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: index == currentStep
                    ? scheme.onPrimaryContainer
                    : scheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class LanguageFlag extends StatelessWidget {
  const LanguageFlag({super.key, required this.languageCode});

  final String languageCode;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ClipRRect(
      borderRadius: BorderRadius.circular(10),
      child: SizedBox(
        width: 48,
        height: 34,
        child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border.all(color: scheme.outlineVariant),
            borderRadius: BorderRadius.circular(10),
          ),
          child: switch (languageCode) {
            'fa' => const Column(
              children: [
                Expanded(child: ColoredBox(color: Color(0xFF239F40))),
                Expanded(child: ColoredBox(color: Colors.white)),
                Expanded(child: ColoredBox(color: Color(0xFFDA0000))),
              ],
            ),
            'en' => Stack(
              children: [
                Column(
                  children: [
                    for (var index = 0; index < 7; index++)
                      Expanded(
                        child: ColoredBox(
                          color: index.isEven
                              ? const Color(0xFFB22234)
                              : Colors.white,
                        ),
                      ),
                  ],
                ),
                const Align(
                  alignment: Alignment.topLeft,
                  child: SizedBox(
                    width: 18,
                    height: 16,
                    child: ColoredBox(color: Color(0xFF3C3B6E)),
                  ),
                ),
              ],
            ),
            _ => Stack(
              fit: StackFit.expand,
              children: [
                Positioned.fill(
                  child: Row(
                    children: [
                      Expanded(child: _FlagStripes.us()),
                      Expanded(child: _FlagStripes.iran()),
                    ],
                  ),
                ),
                Center(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: scheme.surface.withValues(alpha: .92),
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.language,
                        color: scheme.primary,
                        size: 16,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          },
        ),
      ),
    );
  }
}

class _FlagStripes extends StatelessWidget {
  const _FlagStripes.iran() : mode = 'ir';
  const _FlagStripes.us() : mode = 'us';

  final String mode;

  @override
  Widget build(BuildContext context) {
    if (mode == 'ir') {
      return const Column(
        children: [
          Expanded(child: ColoredBox(color: Color(0xFF239F40))),
          Expanded(child: ColoredBox(color: Colors.white)),
          Expanded(child: ColoredBox(color: Color(0xFFDA0000))),
        ],
      );
    }
    return Column(
      children: [
        for (var index = 0; index < 7; index++)
          Expanded(
            child: ColoredBox(
              color: index.isEven ? const Color(0xFFB22234) : Colors.white,
            ),
          ),
      ],
    );
  }
}

class _OnboardingIcon extends StatelessWidget {
  const _OnboardingIcon({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: scheme.primaryContainer,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Icon(icon, color: scheme.onPrimaryContainer),
      ),
    );
  }
}

class _OnboardingEntrance extends StatelessWidget {
  const _OnboardingEntrance({
    required this.simple,
    required this.child,
    this.delay = Duration.zero,
  });

  final bool simple;
  final Widget child;
  final Duration delay;

  @override
  Widget build(BuildContext context) {
    if (simple) {
      return child;
    }
    return TweenAnimationBuilder<double>(
      duration: Duration(milliseconds: 360 + delay.inMilliseconds),
      curve: Curves.easeOutCubic,
      tween: Tween<double>(begin: 0, end: 1),
      builder: (context, value, child) {
        final delayed = delay == Duration.zero
            ? value
            : ((value * (360 + delay.inMilliseconds) - delay.inMilliseconds) /
                      360)
                  .clamp(0.0, 1.0);
        return Opacity(
          opacity: delayed,
          child: Transform.translate(
            offset: Offset(0, (1 - delayed) * 12),
            child: child,
          ),
        );
      },
      child: child,
    );
  }
}
