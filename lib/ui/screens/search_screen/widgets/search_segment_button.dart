import 'package:flutter/material.dart';
import 'package:lumox/ui/theme/theme_ui_values.dart';

class SearchSegmentButton extends StatelessWidget {
  const SearchSegmentButton({super.key, required this.selected, required this.onTap, required this.icon, required this.label});

  final bool selected;
  final VoidCallback onTap;
  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(context.uiRadiusMd),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOutCubic,
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(context.uiRadiusMd),
          color: selected ? cs.secondaryContainer.withValues(alpha: 0.75) : Colors.transparent,
          border: selected ? Border.all(color: cs.outlineVariant.withValues(alpha: 0.65)) : null,
        ),
        child: AnimatedDefaultTextStyle(
          duration: const Duration(milliseconds: 180),
          style: TextStyle(
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
            fontSize: 13,
            color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 18, color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Flexible(child: Text(label, overflow: TextOverflow.ellipsis)),
            ],
          ),
        ),
      ),
    );
  }
}

