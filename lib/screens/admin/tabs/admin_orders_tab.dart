import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/product_order.dart';
import '../../../services/product_order_service.dart';
import '../../../utils/currency.dart';
import '../../../utils/download_helper.dart';

/// Store → Orders: a filterable queue of member-placed [ProductOrder]s
/// awaiting fulfillment, with status actions (mark ready / complete /
/// cancel) and a CSV export, mirroring the Sales screen's conventions.
class AdminOrdersTab extends StatefulWidget {
  const AdminOrdersTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminOrdersTab> createState() => _AdminOrdersTabState();
}

class _AdminOrdersTabState extends State<AdminOrdersTab> {
  late final _service = ProductOrderService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all' | pending | ready | completed | cancelled
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _dateFormat = DateFormat('dd/MM/yyyy');
  final Set<String> _busyOrderIds = {};

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<ProductOrder> _filtered(List<ProductOrder> orders) {
    final q = _searchQuery.toLowerCase();
    return orders.where((o) {
      final matchStatus = _statusFilter == 'all' || o.status == _statusFilter;
      final matchSearch = q.isEmpty ||
          o.userName.toLowerCase().contains(q) ||
          o.items.any((i) => i.productName.toLowerCase().contains(q));
      final matchFrom = _dateFrom == null ||
          !o.createdAt.isBefore(
              DateTime(_dateFrom!.year, _dateFrom!.month, _dateFrom!.day));
      final matchTo = _dateTo == null ||
          o.createdAt.isBefore(
              DateTime(_dateTo!.year, _dateTo!.month, _dateTo!.day)
                  .add(const Duration(days: 1)));
      return matchStatus && matchSearch && matchFrom && matchTo;
    }).toList();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _dateFrom : _dateTo) ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2100),
    );
    if (picked != null) {
      setState(() => isFrom ? _dateFrom = picked : _dateTo = picked);
    }
  }

  Future<void> _setStatus(ProductOrder order, String status) async {
    setState(() => _busyOrderIds.add(order.id));
    try {
      await _service.setStatus(order.id, status);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n
                .tr('Could not update order: {error}')
                .replaceAll('{error}', '$e')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(order.id));
    }
  }

  Future<void> _cancel(ProductOrder order) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Cancel order?')),
        content: Text(
          context.l10n.tr(
              'This will restore stock for all items in this order.'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Back')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Cancel Order')),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    setState(() => _busyOrderIds.add(order.id));
    try {
      await _service.cancelOrder(order.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('Order cancelled'))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n
                .tr('Could not update order: {error}')
                .replaceAll('{error}', '$e')),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _busyOrderIds.remove(order.id));
    }
  }

  void _exportCsv(List<ProductOrder> orders) {
    final buffer = StringBuffer()
      ..writeln('Date,Member,Items,Quantity,Status,Total');
    for (final order in orders) {
      final itemsSummary =
          order.items.map((i) => '${i.productName} x${i.quantity}').join('; ');
      buffer.writeln(
        '"${_dateFormat.format(order.createdAt)}","${order.userName}",'
        '"$itemsSummary",${order.itemCount},${order.status},'
        '${Currency.formatAmount(order.total, maxDecimals: 3)}',
      );
    }
    final filename =
        'orders_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    triggerJsonDownload(buffer.toString(), filename);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(context.l10n
            .tr('Exported {count} order(s)')
            .replaceAll('{count}', '${orders.length}')),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return StreamBuilder<List<ProductOrder>>(
      stream: _service.streamOrders(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <ProductOrder>[];
        final rows = _filtered(all);
        final pendingCount =
            all.where((o) => o.status == ProductOrderStatus.pending).length;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Text(
                        l10n.tr('Orders'),
                        style: Theme.of(context).textTheme.headlineSmall,
                      ),
                      if (pendingCount > 0) ...[
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.orange,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            l10n
                                .tr('{count} pending')
                                .replaceAll('{count}', '$pendingCount'),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold),
                          ),
                        ),
                      ],
                    ],
                  ),
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty ? null : () => _exportCsv(rows),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(l10n.tr('CSV Export')),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Wrap(
                spacing: 12,
                runSpacing: 12,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  SizedBox(
                    width: 200,
                    child: DropdownButtonFormField<String>(
                      value: _statusFilter,
                      decoration: InputDecoration(
                        labelText: l10n.tr('Status'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: 'all', child: Text(l10n.tr('All'))),
                        DropdownMenuItem(
                            value: ProductOrderStatus.pending,
                            child: Text(l10n.tr('pending'))),
                        DropdownMenuItem(
                            value: ProductOrderStatus.ready,
                            child: Text(l10n.tr('ready'))),
                        DropdownMenuItem(
                            value: ProductOrderStatus.completed,
                            child: Text(l10n.tr('completed'))),
                        DropdownMenuItem(
                            value: ProductOrderStatus.cancelled,
                            child: Text(l10n.tr('cancelled'))),
                      ],
                      onChanged: (v) =>
                          setState(() => _statusFilter = v ?? 'all'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_dateFrom == null
                        ? l10n.tr('Date From')
                        : _dateFormat.format(_dateFrom!)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_dateTo == null
                        ? l10n.tr('Date To')
                        : _dateFormat.format(_dateTo!)),
                  ),
                  if (_dateFrom != null || _dateTo != null)
                    TextButton(
                      onPressed: () => setState(() {
                        _dateFrom = null;
                        _dateTo = null;
                      }),
                      child: Text(l10n.tr('Clear dates')),
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
            const SizedBox(height: 12),
            Expanded(
              child: !snapshot.hasData
                  ? const Center(child: CircularProgressIndicator())
                  : rows.isEmpty
                      ? Center(child: Text(l10n.tr('No Data')))
                      : _OrdersTable(
                          orders: rows,
                          dateFormat: _dateFormat,
                          busyOrderIds: _busyOrderIds,
                          onMarkReady: (o) =>
                              _setStatus(o, ProductOrderStatus.ready),
                          onMarkCompleted: (o) =>
                              _setStatus(o, ProductOrderStatus.completed),
                          onCancel: _cancel,
                        ),
            ),
          ],
        );
      },
    );
  }
}

class _OrdersTable extends StatelessWidget {
  const _OrdersTable({
    required this.orders,
    required this.dateFormat,
    required this.busyOrderIds,
    required this.onMarkReady,
    required this.onMarkCompleted,
    required this.onCancel,
  });

  final List<ProductOrder> orders;
  final DateFormat dateFormat;
  final Set<String> busyOrderIds;
  final ValueChanged<ProductOrder> onMarkReady;
  final ValueChanged<ProductOrder> onMarkCompleted;
  final ValueChanged<ProductOrder> onCancel;

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

  void _showOrderDetails(BuildContext context, ProductOrder order) {
    showDialog<void>(
      context: context,
      builder: (_) => _OrderDetailsDialog(
        order: order,
        dateFormat: dateFormat,
        statusColor: _statusColor(order.status),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(l10n.tr('Date'))),
            DataColumn(label: Text(l10n.tr('Member'))),
            DataColumn(label: Text(l10n.tr('Items'))),
            DataColumn(label: Text(l10n.tr('Status'))),
            DataColumn(label: Text(l10n.tr('Total'))),
            DataColumn(label: Text(l10n.tr('Actions'))),
          ],
          rows: orders.map((order) {
            final summary = order.items
                .map((i) => '${i.productName} x${i.quantity}')
                .join(', ');
            final busy = busyOrderIds.contains(order.id);
            final isPending = order.status == ProductOrderStatus.pending;
            final isReady = order.status == ProductOrderStatus.ready;
            final isFinal = order.status == ProductOrderStatus.completed ||
                order.status == ProductOrderStatus.cancelled;

            return DataRow(cells: [
              DataCell(Text(
                  '${dateFormat.format(order.createdAt)} ${TimeOfDay.fromDateTime(order.createdAt).format(context)}')),
              DataCell(Text(
                  order.userName.isEmpty ? l10n.tr('Member') : order.userName)),
              DataCell(
                InkWell(
                  onTap: () => _showOrderDetails(context, order),
                  child: SizedBox(
                    width: 260,
                    child: Text(summary,
                        maxLines: 2, overflow: TextOverflow.ellipsis),
                  ),
                ),
              ),
              DataCell(Chip(
                label: Text(l10n.tr(order.status)),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: _statusColor(order.status).withValues(alpha: 0.15),
                labelStyle: TextStyle(
                    color: _statusColor(order.status),
                    fontWeight: FontWeight.bold),
              )),
              DataCell(
                  Text(Currency.format(order.total, Currency.defaultCode))),
              DataCell(
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      tooltip: l10n.tr('View Details'),
                      icon: const Icon(Icons.visibility_outlined, size: 20),
                      onPressed: () => _showOrderDetails(context, order),
                    ),
                    if (busy)
                      const Padding(
                        padding: EdgeInsets.symmetric(horizontal: 8),
                        child: SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    else if (!isFinal) ...[
                      if (isPending)
                        IconButton(
                          tooltip: l10n.tr('Mark Ready'),
                          icon: const Icon(Icons.inventory_2_outlined,
                              size: 20, color: Colors.blue),
                          onPressed: () => onMarkReady(order),
                        ),
                      if (isReady)
                        IconButton(
                          tooltip: l10n.tr('Mark Completed'),
                          icon: const Icon(Icons.check_circle_outline,
                              size: 20, color: Colors.green),
                          onPressed: () => onMarkCompleted(order),
                        ),
                      IconButton(
                        tooltip: l10n.tr('Cancel Order'),
                        icon: const Icon(Icons.cancel_outlined,
                            size: 20, color: Colors.red),
                        onPressed: () => onCancel(order),
                      ),
                    ],
                  ],
                ),
              ),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

/// Full order breakdown: every line item with its unit price, quantity and
/// line total, plus order metadata (member, date, status). Opened by
/// tapping the Items cell or the "View Details" action in [_OrdersTable].
class _OrderDetailsDialog extends StatelessWidget {
  const _OrderDetailsDialog({
    required this.order,
    required this.dateFormat,
    required this.statusColor,
  });

  final ProductOrder order;
  final DateFormat dateFormat;
  final Color statusColor;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return AlertDialog(
      title: Row(
        children: [
          Expanded(child: Text(l10n.tr('Order Details'))),
          Chip(
            label: Text(l10n.tr(order.status)),
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            backgroundColor: statusColor.withValues(alpha: 0.15),
            labelStyle:
                TextStyle(color: statusColor, fontWeight: FontWeight.bold),
          ),
        ],
      ),
      content: SizedBox(
        width: 420,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _DetailRow(
              label: l10n.tr('Member'),
              value: order.userName.isEmpty ? l10n.tr('Member') : order.userName,
            ),
            _DetailRow(
              label: l10n.tr('Date'),
              value:
                  '${dateFormat.format(order.createdAt)} ${TimeOfDay.fromDateTime(order.createdAt).format(context)}',
            ),
            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: order.items.length,
                separatorBuilder: (_, __) => const Divider(height: 16),
                itemBuilder: (context, i) {
                  final item = order.items[i];
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        flex: 3,
                        child: Text(item.productName,
                            style:
                                Theme.of(context).textTheme.bodyMedium),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          '${item.quantity} × ${Currency.format(item.unitPrice, Currency.defaultCode)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      ),
                      Expanded(
                        flex: 2,
                        child: Text(
                          Currency.format(item.lineTotal, Currency.defaultCode),
                          textAlign: TextAlign.end,
                          style: Theme.of(context)
                              .textTheme
                              .bodyMedium
                              ?.copyWith(fontWeight: FontWeight.w600),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(l10n.tr('Total'),
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.bold)),
                Text(
                  Currency.format(order.total, Currency.defaultCode),
                  style: Theme.of(context)
                      .textTheme
                      .titleMedium
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.tr('Close')),
        ),
      ],
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          SizedBox(
            width: 80,
            child: Text(
              label,
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          Expanded(child: Text(value)),
        ],
      ),
    );
  }
}
