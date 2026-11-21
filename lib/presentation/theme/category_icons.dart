import 'package:flutter/material.dart';

/// Icons are stored in the database by key (not code point) so release
/// builds can tree-shake the icon font.
class CategoryIcons {
  CategoryIcons._();

  static const Map<String, IconData> all = {
    'food': Icons.restaurant_rounded,
    'transport': Icons.directions_bus_rounded,
    'bills': Icons.receipt_long_rounded,
    'shopping': Icons.shopping_bag_rounded,
    'health': Icons.favorite_rounded,
    'entertainment': Icons.movie_rounded,
    'education': Icons.school_rounded,
    'other': Icons.category_rounded,
    'coffee': Icons.coffee_rounded,
    'groceries': Icons.local_grocery_store_rounded,
    'home': Icons.home_rounded,
    'pets': Icons.pets_rounded,
    'gift': Icons.card_giftcard_rounded,
    'travel': Icons.flight_rounded,
    'phone': Icons.smartphone_rounded,
    'fitness': Icons.fitness_center_rounded,
    'salary': Icons.payments_rounded,
    'savings': Icons.savings_rounded,
    'baby': Icons.child_friendly_rounded,
    'beauty': Icons.spa_rounded,
    'car': Icons.directions_car_rounded,
    'games': Icons.sports_esports_rounded,
    'music': Icons.music_note_rounded,
    'church': Icons.volunteer_activism_rounded,
    'tools': Icons.build_rounded,
    'internet': Icons.wifi_rounded,
    'water': Icons.water_drop_rounded,
    'electricity': Icons.bolt_rounded,
  };

  static IconData of(String key) => all[key] ?? Icons.category_rounded;

  static const palette = <int>[
    0xFFFF7043, 0xFF42A5F5, 0xFFAB47BC, 0xFFEC407A, 0xFF26A69A, 0xFFFFB300,
    0xFF5C6BC0, 0xFF78909C, 0xFF8D6E63, 0xFF66BB6A, 0xFFEF5350, 0xFF29B6F6,
    0xFF7E57C2, 0xFFD4E157, 0xFF26C6DA, 0xFFFFA726,
  ];
}
