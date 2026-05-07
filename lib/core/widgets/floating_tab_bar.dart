import 'dart:ui';
import 'package:flutter/material.dart';
import '../theme/app_colors.dart';
import '../theme/app_typography.dart';

enum AppTab { home, routine, chat, catalog, profile }

class FloatingTabBar extends StatelessWidget {
  const FloatingTabBar({
    super.key,
    required this.active,
    required this.onSelect,
  });

  final AppTab active;
  final ValueChanged<AppTab> onSelect;

  static const _items = <(AppTab, IconData, String)>[
    (AppTab.home, Icons.home_rounded, 'Дом'),
    (AppTab.routine, Icons.auto_awesome_rounded, 'Уход'),
    (AppTab.chat, Icons.chat_bubble_rounded, 'Чат'),
    (AppTab.catalog, Icons.grid_view_rounded, 'Каталог'),
    (AppTab.profile, Icons.person_rounded, 'Профиль'),
  ];

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 14),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(999),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
          child: Container(
            height: 64,
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.78),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(
                  color: AppColors.primaryAccent.withOpacity(0.18)),
              boxShadow: [
                BoxShadow(
                  color: AppColors.primaryAccent.withOpacity(0.35),
                  blurRadius: 40,
                  offset: const Offset(0, 14),
                  spreadRadius: -12,
                ),
              ],
            ),
            child: Row(
              children: _items.map((item) {
                final (tab, icon, label) = item;
                final selected = tab == active;
                return Expanded(
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(999),
                      onTap: () => onSelect(tab),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            icon,
                            size: 22,
                            color: selected
                                ? AppColors.roseDeep
                                : AppColors.textSecondary,
                          ),
                          const SizedBox(height: 3),
                          Text(
                            label,
                            style: AppTypography.micro.copyWith(
                              fontSize: 10,
                              color: selected
                                  ? AppColors.roseDeep
                                  : AppColors.textSecondary,
                              fontWeight: selected
                                  ? FontWeight.w600
                                  : FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
