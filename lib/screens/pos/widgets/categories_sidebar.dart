// lib/screens/pos/widgets/categories_sidebar.dart
//
// 🗂️ أقسام المواد في الكاشير:
//  • CategoriesSidebar — قائمة عمودية للشاشات العريضة
//  • CategoryChipsBar  — شريط أفقي للشاشات المتوسطة والصغيرة

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../models/category.dart';
import '../../../providers/pos_provider.dart';
import 'pos_style.dart';

class CategoriesSidebar extends StatelessWidget {
  const CategoriesSidebar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, pos, _) {
        final items = <Category?>[null, ...pos.categories];
        return Container(
          decoration: const BoxDecoration(
            color: PosColors.surface,
            border: BorderDirectional(end: BorderSide(color: PosColors.border)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 16, 16, 10),
                child: Text(
                  'الأقسام',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: PosColors.text),
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
                  itemCount: items.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 4),
                  itemBuilder: (context, i) {
                    final c = items[i];
                    final selected = c == null ? pos.selectedCategoryId == null : pos.selectedCategoryId == c.id;
                    return _RailItem(
                      label: c?.name ?? 'كل المواد',
                      icon: c == null ? Icons.apps_rounded : Icons.label_outline_rounded,
                      tint: c == null ? PosColors.primary : PosColors.tint(c.id),
                      selected: selected,
                      onTap: () => pos.selectCategory(c?.id),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _RailItem extends StatelessWidget {
  const _RailItem({
    required this.label,
    required this.icon,
    required this.tint,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color tint;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? PosColors.accentSoft : Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
          child: Row(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: selected ? tint : tint.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: selected ? Colors.white : tint),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    height: 1.25,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? PosColors.primary : PosColors.text,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// شريط أقسام أفقي (للشاشات المتوسطة والصغيرة)
class CategoryChipsBar extends StatelessWidget {
  const CategoryChipsBar({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, pos, _) {
        final items = <Category?>[null, ...pos.categories];
        if (items.length <= 1) return const SizedBox.shrink();
        return SizedBox(
          height: 40,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: items.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (context, i) {
              final c = items[i];
              final selected = c == null ? pos.selectedCategoryId == null : pos.selectedCategoryId == c.id;
              final tint = c == null ? PosColors.primary : PosColors.tint(c.id);
              return Material(
                color: selected ? tint : PosColors.surface,
                shape: StadiumBorder(side: BorderSide(color: selected ? tint : PosColors.border)),
                child: InkWell(
                  customBorder: const StadiumBorder(),
                  onTap: () => pos.selectCategory(c?.id),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Center(
                      child: Text(
                        c?.name ?? 'الكل',
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                          color: selected ? Colors.white : PosColors.text,
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
