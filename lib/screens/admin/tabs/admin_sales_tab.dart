import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/sale.dart';
import '../../../services/sales_service.dart';
import '../../../utils/currency.dart';
import '../../../utils/download_helper.dart';

/// Store → Sales: a filterable log of completed POS transactions, with a CSV
/// export action (matches the reference tool's Sales screen).
class AdminSalesTab extends StatefulWidget {
  const AdminSalesTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminSalesTab> createState() => _AdminSalesTabState();
}

class _AdminSalesTabState extends State<AdminSalesTab> {
  late final _service = SalesService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _statusFilter = 'all'; // 'all' | 'completed' | 'refunded'
  DateTime? _dateFrom;
  DateTime? _dateTo;
  final _dateFormat = DateFormat('dd/MM/yyyy');

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Sale> _filtered(List<Sale> sales) {
    final q = _searchQuery.toLowerCase();
    return sales.where((s) {
      final matchStatus = _statusFilter == 'all' || s.status == _statusFilter;
      final matchSearch = q.isEmpty ||
          s.items.any((i) => i.productName.toLowerCase().contains(q)) ||
          s.soldByName.toLowerCase().contains(q);
      final matchFrom = _dateFrom == null ||
          !s.soldAt.isBefore(DateTime(
              _dateFrom!.year, _dateFrom!.month, _dateFrom!.day));
      final matchTo = _dateTo == null ||
          s.soldAt.isBefore(DateTime(
                  _dateTo!.year, _dateTo!.month, _dateTo!.day)
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

  void _exportCsv(List<Sale> sales) {
    final buffer = StringBuffer()
      ..writeln('Date,Items,Quantity,Payment,Status,Total');
    for (final sale in sales) {
      final itemsSummary =
          sale.items.map((i) => '${i.productName} x${i.quantity}').join('; ');
      buffer.writeln(
        '"${_dateFormat.format(sale.soldAt)}","$itemsSummary",'
        '${sale.itemCount},${sale.paymentMethod},${sale.status},'
        '${Currency.formatAmount(sale.total, maxDecimals: 3)}',
      );
    }
    final filename =
        'sales_${DateFormat('yyyyMMdd_HHmmss').format(DateTime.now())}.csv';
    triggerJsonDownload(buffer.toString(), filename);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(context.l10n.tr('Exported {count} sale(s)')
          .replaceAll('{count}', '${sales.length}'))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Sale>>(
      stream: _service.streamSales(),
      builder: (context, snapshot) {
        final all = snapshot.data ?? const <Sale>[];
        final rows = _filtered(all);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    context.l10n.tr('Sales'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                  OutlinedButton.icon(
                    onPressed: rows.isEmpty ? null : () => _exportCsv(rows),
                    icon: const Icon(Icons.download_outlined),
                    label: Text(context.l10n.tr('CSV Export')),
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
                        labelText: context.l10n.tr('Status'),
                        isDense: true,
                        border: const OutlineInputBorder(),
                      ),
                      items: [
                        DropdownMenuItem(
                            value: 'all', child: Text(context.l10n.tr('All'))),
                        DropdownMenuItem(
                            value: 'completed',
                            child: Text(context.l10n.tr('Completed'))),
                        DropdownMenuItem(
                            value: 'refunded',
                            child: Text(context.l10n.tr('Refunded'))),
                      ],
                      onChanged: (v) =>
                          setState(() => _statusFilter = v ?? 'all'),
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: true),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_dateFrom == null
                        ? context.l10n.tr('Date From')
                        : _dateFormat.format(_dateFrom!)),
                  ),
                  OutlinedButton.icon(
                    onPressed: () => _pickDate(isFrom: false),
                    icon: const Icon(Icons.calendar_today, size: 16),
                    label: Text(_dateTo == null
                        ? context.l10n.tr('Date To')
                        : _dateFormat.format(_dateTo!)),
                  ),
                  if (_dateFrom != null || _dateTo != null)
                    TextButton(
                      onPressed: () =>
                          setState(() {
                        _dateFrom = null;
                        _dateTo = null;
                      }),
                      child: Text(context.l10n.tr('Clear dates')),
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
                  : rows.isEmpty
                      ? Center(child: Text(context.l10n.tr('No Data')))
                      : _SalesTable(sales: rows, dateFormat: _dateFormat),
            ),
          ],
        );
      },
    );
  }
}

class _SalesTable extends StatelessWidget {
  const _SalesTable({required this.sales, required this.dateFormat});

  final List<Sale> sales;
  final DateFormat dateFormat;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(context.l10n.tr('Date'))),
            DataColumn(label: Text(context.l10n.tr('Items'))),
            DataColumn(label: Text(context.l10n.tr('Payment'))),
            DataColumn(label: Text(context.l10n.tr('Sold by'))),
            DataColumn(label: Text(context.l10n.tr('Status'))),
            DataColumn(label: Text(context.l10n.tr('Total'))),
          ],
          rows: sales.map((sale) {
            final summary = sale.items
                .map((i) => '${i.productName} x${i.quantity}')
                .join(', ');
            return DataRow(cells: [
              DataCell(Text(
                  '${dateFormat.format(sale.soldAt)} ${TimeOfDay.fromDateTime(sale.soldAt).format(context)}')),
              DataCell(SizedBox(
                width: 260,
                child:
                    Text(summary, maxLines: 2, overflow: TextOverflow.ellipsis),
              )),
              DataCell(Text(sale.paymentMethod)),
              DataCell(Text(sale.soldByName)),
              DataCell(Chip(
                label: Text(sale.status),
                visualDensity: VisualDensity.compact,
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                backgroundColor: sale.status == 'refunded'
                    ? Colors.red.withValues(alpha: 0.15)
                    : Colors.green.withValues(alpha: 0.15),
              )),
              DataCell(Text(Currency.format(sale.total, Currency.defaultCode))),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}
