import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/product.dart';
import '../../../models/sale.dart';
import '../../../services/product_service.dart';
import '../../../services/sales_service.dart';
import '../../../utils/currency.dart';

/// Store → POS: a checkout screen. Staff pick products from a filterable
/// grid (with live stock badges); selections build up a cart that is
/// finalized via [SalesService.recordSale], which atomically decrements
/// stock and writes a [Sale] record.
class AdminPosTab extends StatefulWidget {
  const AdminPosTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminPosTab> createState() => _AdminPosTabState();
}

class _AdminPosTabState extends State<AdminPosTab> {
  late final _productService = ProductService(gymId: widget.gymId);
  late final _salesService = SalesService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _categoryFilter = 'all';
  String _paymentMethod = 'cash';

  /// productId -> quantity in cart.
  final Map<String, int> _cart = {};
  bool _checkingOut = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filtered(List<Product> products) {
    final q = _searchQuery.toLowerCase();
    return products.where((p) {
      if (!p.active) return false;
      final matchSearch = q.isEmpty || p.name.toLowerCase().contains(q);
      final matchCategory =
          _categoryFilter == 'all' || p.category == _categoryFilter;
      return matchSearch && matchCategory;
    }).toList();
  }

  void _addToCart(Product product) {
    if (!product.isUnlimitedStock &&
        product.stock <= (_cart[product.id] ?? 0)) {
      return;
    }
    setState(() => _cart[product.id] = (_cart[product.id] ?? 0) + 1);
  }

  void _removeFromCart(String productId) {
    setState(() {
      final current = _cart[productId] ?? 0;
      if (current <= 1) {
        _cart.remove(productId);
      } else {
        _cart[productId] = current - 1;
      }
    });
  }

  Future<void> _checkout(List<Product> allProducts) async {
    if (_cart.isEmpty) return;
    setState(() => _checkingOut = true);
    try {
      final items = _cart.entries.map((entry) {
        final product =
            allProducts.firstWhere((p) => p.id == entry.key);
        return SaleItem(
          productId: product.id,
          productName: product.name,
          quantity: entry.value,
          unitPrice: product.retailPrice,
        );
      }).toList();

      final user = FirebaseAuth.instance.currentUser;
      await _salesService.recordSale(
        items: items,
        paymentMethod: _paymentMethod,
        soldByName: user?.displayName ?? user?.email ?? 'Admin',
      );

      if (mounted) {
        setState(() => _cart.clear());
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('Sale completed'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content:
                  Text(context.l10n.tr('Could not complete sale: {error}')
                      .replaceAll('{error}', '$e'))),
        );
      }
    } finally {
      if (mounted) setState(() => _checkingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Product>>(
      stream: _productService.streamProducts(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Product>[];
        final categories = all
            .map((p) => p.category)
            .where((c) => c.isNotEmpty)
            .toSet()
            .toList()
          ..sort();
        final visible = _filtered(all);
        final isWide = MediaQuery.sizeOf(context).width >= 900;

        final grid = Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Text(
                context.l10n.tr('Point of Sale'),
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  SizedBox(
                    width: 220,
                    child: DropdownButtonFormField<String>(
                      value: _categoryFilter,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Category'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: 'all',
                            child: Text(context.l10n.tr('All categories'))),
                        ...categories.map(
                          (c) => DropdownMenuItem(value: c, child: Text(c)),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _categoryFilter = v ?? 'all'),
                    ),
                  ),
                  SizedBox(
                    width: 260,
                    child: TextField(
                      controller: _searchController,
                      decoration: InputDecoration(
                        labelText: context.l10n.tr('Search'),
                        prefixIcon: const Icon(Icons.search),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      onChanged: (v) =>
                          setState(() => _searchQuery = v.trim()),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : visible.isEmpty
                      ? Center(
                          child: Text(context.l10n.tr('No products found')))
                      : GridView.builder(
                          padding: const EdgeInsets.all(16),
                          gridDelegate:
                              const SliverGridDelegateWithMaxCrossAxisExtent(
                            maxCrossAxisExtent: 200,
                            mainAxisSpacing: 12,
                            crossAxisSpacing: 12,
                            childAspectRatio: 0.78,
                          ),
                          itemCount: visible.length,
                          itemBuilder: (context, i) {
                            final product = visible[i];
                            final inCart = _cart[product.id] ?? 0;
                            return _ProductCard(
                              product: product,
                              inCart: inCart,
                              onAdd: () => _addToCart(product),
                            );
                          },
                        ),
            ),
          ],
        );

        final cart = _CartPanel(
          cart: _cart,
          products: all,
          paymentMethod: _paymentMethod,
          checkingOut: _checkingOut,
          onPaymentMethodChanged: (v) => setState(() => _paymentMethod = v),
          onIncrement: (id) {
            final product = all.firstWhere((p) => p.id == id);
            _addToCart(product);
          },
          onDecrement: _removeFromCart,
          onCheckout: () => _checkout(all),
        );

        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(child: grid),
              SizedBox(width: 320, child: cart),
            ],
          );
        }

        return Column(
          children: [
            Expanded(child: grid),
            SizedBox(height: 260, child: cart),
          ],
        );
      },
    );
  }
}

class _ProductCard extends StatelessWidget {
  const _ProductCard({
    required this.product,
    required this.inCart,
    required this.onAdd,
  });

  final Product product;
  final int inCart;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final remaining = product.stock - inCart;
    final outOfStock = !product.isUnlimitedStock && remaining <= 0;
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: Stack(
              children: [
                Container(
                  color: Theme.of(context).colorScheme.surfaceContainerHighest,
                  child: product.imageUrl.isEmpty
                      ? Center(
                          child: Text(
                            context.l10n.tr('No Image'),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        )
                      : Image.network(product.imageUrl, fit: BoxFit.cover),
                ),
                Positioned(
                  top: 6,
                  left: 6,
                  child: product.isUnlimitedStock
                      ? const _StockBadge(count: null)
                      : _StockBadge(count: remaining),
                ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: FloatingActionButton.small(
                    heroTag: 'add_${product.id}',
                    backgroundColor: outOfStock ? Colors.grey : Colors.red,
                    onPressed: outOfStock ? null : onAdd,
                    child: const Icon(Icons.add_shopping_cart, size: 18),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  product.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                Text(
                  Currency.format(product.retailPrice, Currency.defaultCode),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _StockBadge extends StatelessWidget {
  const _StockBadge({required this.count});

  /// null means unlimited stock (shown as "∞").
  final int? count;

  @override
  Widget build(BuildContext context) {
    final color =
        count == null ? Colors.green : (count! <= 0 ? Colors.red : Colors.green);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        count == null ? '∞' : '$count',
        style: const TextStyle(
            color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CartPanel extends StatelessWidget {
  const _CartPanel({
    required this.cart,
    required this.products,
    required this.paymentMethod,
    required this.checkingOut,
    required this.onPaymentMethodChanged,
    required this.onIncrement,
    required this.onDecrement,
    required this.onCheckout,
  });

  final Map<String, int> cart;
  final List<Product> products;
  final String paymentMethod;
  final bool checkingOut;
  final ValueChanged<String> onPaymentMethodChanged;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;
  final VoidCallback onCheckout;

  @override
  Widget build(BuildContext context) {
    final entries = cart.entries.toList();
    num total = 0;
    for (final entry in entries) {
      final product = products.firstWhere(
        (p) => p.id == entry.key,
        orElse: () => Product(id: entry.key, name: '', createdAt: DateTime.now()),
      );
      total += product.retailPrice * entry.value;
    }

    return Container(
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: Theme.of(context).dividerColor),
        ),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                const Icon(Icons.shopping_cart_outlined),
                const SizedBox(width: 8),
                Text(context.l10n.tr('Cart'),
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
          ),
          Expanded(
            child: entries.isEmpty
                ? Center(child: Text(context.l10n.tr('Cart is empty')))
                : ListView.builder(
                    itemCount: entries.length,
                    itemBuilder: (context, i) {
                      final entry = entries[i];
                      final product = products.firstWhere(
                        (p) => p.id == entry.key,
                        orElse: () => Product(
                            id: entry.key, name: '', createdAt: DateTime.now()),
                      );
                      return ListTile(
                        dense: true,
                        title: Text(product.name),
                        subtitle: Text(Currency.format(
                            product.retailPrice, Currency.defaultCode)),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.remove_circle_outline),
                              onPressed: () => onDecrement(entry.key),
                            ),
                            Text('${entry.value}'),
                            IconButton(
                              icon: const Icon(Icons.add_circle_outline),
                              onPressed: () => onIncrement(entry.key),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SegmentedButton<String>(
                  segments: [
                    ButtonSegment(
                        value: 'cash',
                        label: Text(context.l10n.tr('Cash'))),
                    ButtonSegment(
                        value: 'card',
                        label: Text(context.l10n.tr('Card'))),
                  ],
                  selected: {paymentMethod},
                  onSelectionChanged: (s) => onPaymentMethodChanged(s.first),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(context.l10n.tr('Total'),
                        style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      Currency.format(total, Currency.defaultCode),
                      style: Theme.of(context)
                          .textTheme
                          .titleMedium
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed:
                      entries.isEmpty || checkingOut ? null : onCheckout,
                  icon: checkingOut
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child:
                              CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: Text(context.l10n.tr('Complete Sale')),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
