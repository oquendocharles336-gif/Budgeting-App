import 'package:flutter/material.dart';

import '../../theme/glass.dart';
import '../../widgets/motion/cascade.dart';
import '../../widgets/motion/fade_indexed_stack.dart';
import '../../widgets/photo_migration_line.dart';
import 'capital_screen.dart';
import 'inventory_screen.dart';
import 'orders_screen.dart';
import 'products_screen.dart';
import 'sales_screen.dart';

/// The business side.
///
/// Opened from Home ("Business") and closed with the "Personal" switch (top
/// left, where a back arrow would be) or the phone's Back. With Business
/// Mode on it is also a tab of the home screen ([asTab]): then there is no
/// "Personal" switch, and its sections sit in a row under the title instead
/// of a second bottom bar. Same lazy sections either way: each is built the
/// first time it's opened, so its list cascade plays then.
class BusinessShell extends StatefulWidget {
  const BusinessShell({super.key, this.asTab = false});

  /// Shown as the "Business" tab of the home screen.
  final bool asTab;

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  int _index = 0;
  final Set<int> _built = {0};

  static const _sections = <({String title, IconData icon})>[
    (title: 'Sales', icon: Icons.bar_chart_rounded),
    (title: 'Orders', icon: Icons.receipt_rounded),
    (title: 'Products', icon: Icons.sell_rounded),
    (title: 'Inventory', icon: Icons.inventory_2_rounded),
    (title: 'Capital', icon: Icons.savings_rounded),
  ];

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _built.add(i);
    });
  }

  @override
  Widget build(BuildContext context) {
    const pages = <Widget>[SalesScreen(), OrdersScreen(), ProductsScreen(), InventoryScreen(), CapitalScreen()];
    final title = Text('Business · ${_sections[_index].title}', overflow: TextOverflow.ellipsis);
    return Scaffold(
      appBar: widget.asTab
          ? AppBar(
              title: title,
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(56),
                child: _SectionRow(sections: _sections, selected: _index, onSelect: _select),
              ),
            )
          : AppBar(
              // No back arrow: the "Personal" switch takes its place.
              automaticallyImplyLeading: false,
              leadingWidth: 128,
              leading: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    style: TextButton.styleFrom(minimumSize: const Size(48, 48), padding: const EdgeInsets.symmetric(horizontal: 10)),
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.swap_horiz_rounded),
                    label: const Text('Personal', semanticsLabel: 'Switch to personal budget'),
                  ),
                ),
              ),
              titleSpacing: 0,
              title: title,
            ),
      body: Column(
        children: [
          const PhotoMigrationLine(),
          Expanded(
            child: FadeIndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < pages.length; i++)
                  _built.contains(i) ? CascadeScope(child: pages[i]) : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: widget.asTab
          ? null
          : GlassBar(
              child: NavigationBar(
                selectedIndex: _index,
                onDestinationSelected: _select,
                destinations: [
                  for (final s in _sections) NavigationDestination(icon: Icon(s.icon), label: s.title),
                ],
              ),
            ),
    );
  }
}

/// The five sections in one fixed row (no scrolling, so it never fights
/// the home screen's tab swipe).
class _SectionRow extends StatelessWidget {
  const _SectionRow({required this.sections, required this.selected, required this.onSelect});
  final List<({String title, IconData icon})> sections;
  final int selected;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 56,
      child: Row(
        children: [
          for (var i = 0; i < sections.length; i++)
            Expanded(
              child: Semantics(
                selected: i == selected,
                button: true,
                label: sections[i].title,
                excludeSemantics: true,
                child: InkWell(
                  onTap: () => onSelect(i),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(sections[i].icon, size: 22, color: i == selected ? scheme.primary : scheme.onSurfaceVariant),
                      const SizedBox(height: 2),
                      FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(
                          sections[i].title,
                          maxLines: 1,
                          style: TextStyle(
                            fontSize: 12,
                            color: i == selected ? scheme.primary : scheme.onSurfaceVariant,
                            fontWeight: i == selected ? FontWeight.w700 : FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
