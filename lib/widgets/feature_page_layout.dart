import 'package:flutter/material.dart';

/// Keeps feature cards readable on a desktop and stacks them on a phone.
class FeaturePageLayout extends StatelessWidget {
  const FeaturePageLayout({
    super.key,
    required this.heading,
    required this.sections,
    this.fullWidthSections = const [],
  });
  final List<Widget> heading;
  final List<Widget> sections;
  final List<Widget> fullWidthSections;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final contentWidth = (constraints.maxWidth - 36).clamp(0.0, 1180.0);
      final twoColumns = contentWidth >= 860;
      final cardWidth = twoColumns ? (contentWidth - 18) / 2 : contentWidth;
      return SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(18, 20, 18, 120),
        child: Center(
          child: SizedBox(
            width: contentWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                ...heading,
                const SizedBox(height: 20),
                Wrap(
                  spacing: 18,
                  runSpacing: 18,
                  children: [
                    for (final section in sections)
                      SizedBox(width: cardWidth, child: section),
                  ],
                ),
                for (final section in fullWidthSections) ...[
                  const SizedBox(height: 18),
                  section,
                ],
              ],
            ),
          ),
        ),
      );
    },
  );
}
