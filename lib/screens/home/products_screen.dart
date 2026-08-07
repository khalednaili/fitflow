import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../../l10n/app_localizations.dart';
import '../../models/product.dart';
import '../../models/product_order.dart';
import '../../models/sale.dart';
import '../../services/product_order_service.dart';
import '../../services/product_service.dart';
import '../../utils/currency.dart';

/// Member-facing Store: browse products the gym has made visible in-app,
/// build a cart, and place an order. Orders are written as a
/// [ProductOrder] with `status: pending` for staff to fulfill — the member
/// picks up and pays for the products in person at the gym; no online
/// payment is involved.
class ProductsScreen extends StatefulWidget {
  const ProductsScreen({super.key, this.gymId = ''});

  final String gymId;

  @override
  State<ProductsScreen> createState() => _ProductsScreenState();
}

class _ProductsScreenState extends State<ProductsScreen> {
  late final _productService = ProductService(gymId: widget.gymId);
  late final _orderService = ProductOrderService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _categoryFilter = 'all';

  /// productId -> quantity in cart.
  final Map<String, int> _cart = {};
  bool _placingOrder = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filtered(List<Product> products) {
    final q = _searchQuery.toLowerCase();
    return products.where((p) {
      if (!p.active || !p.displayInApp) return false;
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

  Future<void> _placeOrder(List<Product> allProducts) async {
    if (_cart.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _placingOrder = true);
    try {
      final items = _cart.entries.map((entry) {
        final product = allProducts.firstWhere((p) => p.id == entry.key);
        return SaleItem(
          productId: product.id,
          productName: product.name,
          quantity: entry.value,
          unitPrice: product.retailPrice,
        );
      }).toList();

      await _orderService.placeOrder(
        items: items,
        userId: user.uid,
        userName: user.displayName ?? user.email ?? '',
      );

      if (mounted) {
        setState(() => _cart.clear());
        Navigator.of(context).pop(); // close cart sheet if open
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(context.l10n.tr('Order placed! Pick up and pay at the gym.')),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n
                .tr('Could not place order: {error}')
                .replaceAll('{error}', '$e')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _placingOrder = false);
    }
  }

  void _openCart(List<Product> allProducts) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheetState) {
          return _CartSheet(
            cart: _cart,
            products: allProducts,
            placingOrder: _placingOrder,
            onIncrement: (id) {
              final product = allProducts.firstWhere((p) => p.id == id);
              setState(() => _addToCart(product));
              setSheetState(() {});
            },
            onDecrement: (id) {
              setState(() => _removeFromCart(id));
              setSheetState(() {});
            },
            onPlaceOrder: () => _placeOrder(allProducts),
          );
        },
      ),
    );
  }

  void _openMyOrders() {
    Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => _MyOrdersScreen(orderService: _orderService),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cartCount =
        _cart.values.fold<int>(0, (total, qty) => total + qty);

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tr('Store')),
        actions: [
          IconButton(
            tooltip: l10n.tr('My Orders'),
            onPressed: _openMyOrders,
            icon: const Icon(Icons.receipt_long_outlined),
          ),
        ],
      ),
      body: StreamBuilder<List<Product>>(
        stream: _productService.streamProducts(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Product>[];
          final visibleAll =
              all.where((p) => p.active && p.displayInApp).toList();
          final categories = visibleAll
              .map((p) => p.category)
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));
          final visible = _filtered(all);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _categoryFilter,
                        decoration: InputDecoration(
                          labelText: l10n.tr('Category'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                            value: 'all',
                            child: Text(l10n.tr('All categories')),
                          ),
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
                          labelText: l10n.tr('Search'),
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
              Expanded(
                child: !snapshot.hasData
                    ? const Center(child: CircularProgressIndicator())
                    : visible.isEmpty
                        ? Center(child: Text(l10n.tr('No products found')))
                        : GridView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                            gridDelegate:
                                const SliverGridDelegateWithMaxCrossAxisExtent(
                              maxCrossAxisExtent: 200,
                              mainAxisSpacing: 12,
                              crossAxisSpacing: 12,
                              childAspectRatio: 0.72,
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
        },
      ),
      floatingActionButton: cartCount == 0
          ? null
          : StreamBuilder<List<Product>>(
              stream: _productService.streamProducts(),
              builder: (context, snapshot) {
                final all = snapshot.data ?? const <Product>[];
                return FloatingActionButton.extended(
                  onPressed: () => _openCart(all),
                  icon: Badge(
                    label: Text('$cartCount'),
                    child: const Icon(Icons.shopping_cart),
                  ),
                  label: Text(l10n.tr('Cart')),
                );
              },
            ),
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
                Positioned.fill(
                  child: Container(
                    color:
                        Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: product.imageUrl.isEmpty
                        ? Center(
                            child: Icon(
                              Icons.shopping_bag_outlined,
                              color: Theme.of(context).colorScheme.outline,
                              size: 32,
                            ),
                          )
                        : Image.network(product.imageUrl, fit: BoxFit.cover),
                  ),
                ),
                if (outOfStock)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: _Badge(
                      text: context.l10n.tr('Out of stock'),
                      color: Colors.red,
                    ),
                  ),
                Positioned(
                  bottom: 6,
                  right: 6,
                  child: FloatingActionButton.small(
                    heroTag: 'add_${product.id}',
                    backgroundColor: outOfStock ? Colors.grey : Colors.teal,
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

class _Badge extends StatelessWidget {
  const _Badge({required this.text, required this.color});

  final String text;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: color,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(
            color: Colors.white, fontSize: 11, fontWeight: FontWeight.bold),
      ),
    );
  }
}

class _CartSheet extends StatelessWidget {
  const _CartSheet({
    required this.cart,
    required this.products,
    required this.placingOrder,
    required this.onIncrement,
    required this.onDecrement,
    required this.onPlaceOrder,
  });

  final Map<String, int> cart;
  final List<Product> products;
  final bool placingOrder;
  final ValueChanged<String> onIncrement;
  final ValueChanged<String> onDecrement;
  final VoidCallback onPlaceOrder;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final entries = cart.entries.toList();
    num total = 0;
    for (final entry in entries) {
      final product = products.firstWhere(
        (p) => p.id == entry.key,
        orElse: () =>
            Product(id: entry.key, name: '', createdAt: DateTime.now()),
      );
      total += product.retailPrice * entry.value;
    }

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.viewInsetsOf(context).bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.shopping_cart_outlined),
                const SizedBox(width: 8),
                Text(l10n.tr('Cart'),
                    style: Theme.of(context).textTheme.titleMedium),
              ],
            ),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: entries.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(child: Text(l10n.tr('Cart is empty'))),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final entry = entries[i];
                        final product = products.firstWhere(
                          (p) => p.id == entry.key,
                          orElse: () => Product(
                              id: entry.key,
                              name: '',
                              createdAt: DateTime.now()),
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
            const Divider(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.tr('Total'),
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
              onPressed: entries.isEmpty || placingOrder ? null : onPlaceOrder,
              icon: placingOrder
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.check_circle_outline),
              label: Text(l10n.tr('Place Order')),
            ),
          ],
        ),
      ),
    );
  }
}

class _MyOrdersScreen extends StatelessWidget {
  const _MyOrdersScreen({required this.orderService});

  final ProductOrderService orderService;

  Color _statusColor(String status) {
    switch (status) {
      case ProductOrderStatus.ready:
        return Colors.blue;
      case ProductOrderStatus.completed:
        return Colors.green;
      case ProductOrderStatus.cancelled:
        return Colors.red;
      default:
        return Colors.orange;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.tr('My Orders'))),
      body: user == null
          ? Center(child: Text(l10n.tr('Please sign in first.')))
          : StreamBuilder<List<ProductOrder>>(
              stream: orderService.streamMyOrders(user.uid),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                final orders = snapshot.data ?? const <ProductOrder>[];
                if (orders.isEmpty) {
                  return Center(
                    child: Text(l10n.tr("You haven't placed any orders yet.")),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: orders.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 8),
                  itemBuilder: (context, i) {
                    final order = orders[i];
                    return Card(
                      child: ListTile(
                        title: Text(
                          order.items.map((e) => '${e.quantity}x ${e.productName}').join(', '),
                        ),
                        subtitle: Text(
                          '${Currency.format(order.total, Currency.defaultCode)} · ${_formatDate(order.createdAt)}',
                        ),
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: _statusColor(order.status),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            l10n.tr(order.status),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
    );
  }

  String _formatDate(DateTime date) =>
      '${date.day.toString().padLeft(2, '0')}/${date.month.toString().padLeft(2, '0')}/${date.year}';
}
