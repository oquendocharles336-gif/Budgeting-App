import 'package:flutter/material.dart';

import '../../widgets/motion/cascade.dart';
import '../../widgets/photo_migration_line.dart';
import 'capital_screen.dart';
import 'inventory_screen.dart';
import 'orders_screen.dart';
import 'products_screen.dart';
import 'sales_screen.dart';

/// The business side, opened from Home ("Business") and closed with the
/// "Personal" button or Back. Same lazy tabs as the personal side: each is
/// built the first time it's opened, so its list cascade plays then.
class BusinessShell extends StatefulWidget {
  const BusinessShell({super.key});

  @override
  State<BusinessShell> createState() => _BusinessShellState();
}

class _BusinessShellState extends State<BusinessShell> {
  int _index = 0;
  final Set<int> _built = {0};

  static const _titles = ['Sales', 'Orders', 'Products', 'Inventory', 'Capital'];

  @override
  Widget build(BuildContext context) {
    const pages = <Widget>[SalesScreen(), OrdersScreen(), ProductsScreen(), InventoryScreen(), CapitalScreen()];
    return Scaffold(
      appBar: AppBar(
        title: Text('Business · ${_titles[_index]}'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: TextButton.icon(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: () => Navigator.of(context).pop(),
              icon: const Icon(Icons.person_rounded),
              label: const Text('Personal', semanticsLabel: 'Switch to personal budget'),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          const PhotoMigrationLine(),
          Expanded(
            child: IndexedStack(
              index: _index,
              children: [
                for (var i = 0; i < pages.length; i++)
                  _built.contains(i) ? CascadeScope(child: pages[i]) : const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() {
          _index = i;
          _built.add(i);
        }),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.bar_chart_rounded), label: 'Sales'),
          NavigationDestination(icon: Icon(Icons.receipt_rounded), label: 'Orders'),
          NavigationDestination(icon: Icon(Icons.sell_rounded), label: 'Products'),
          NavigationDestination(icon: Icon(Icons.inventory_2_rounded), label: 'Inventory'),
          NavigationDestination(icon: Icon(Icons.savings_rounded), label: 'Capital'),
        ],
      ),
    );
  }
}
