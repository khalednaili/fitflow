import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/invoice.dart';
import '../../services/billing_service.dart';
import '../../utils/crash_logger.dart';

/// Full-screen invoice view — looks like a printed invoice.
/// Supports adding / editing line-items after creation.
class InvoiceDetailScreen extends StatefulWidget {
  const InvoiceDetailScreen({super.key, required this.invoice});

  final Invoice invoice;

  @override
  State<InvoiceDetailScreen> createState() => _InvoiceDetailScreenState();
}

class _InvoiceDetailScreenState extends State<InvoiceDetailScreen> {
  late final BillingService _billing;

  @override
  void initState() {
    super.initState();
    _billing = BillingService(gymId: widget.invoice.gymId);
  }

  void _openEditItems(Invoice invoice) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _EditItemsSheet(
        invoice: invoice,
        billingService: _billing,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<Invoice?>(
      stream: _billing.streamInvoice(widget.invoice.id),
      builder: (context, snap) {
        final invoice = snap.data ?? widget.invoice;
        return _InvoiceView(
          invoice: invoice,
          onEditItems: () => _openEditItems(invoice),
        );
      },
    );
  }
}

// ── Stateless view ─────────────────────────────────────────────────────────────

class _InvoiceView extends StatelessWidget {
  const _InvoiceView({required this.invoice, required this.onEditItems});
  final Invoice invoice;
  final VoidCallback onEditItems;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final cs = Theme.of(context).colorScheme;
    final dateFmt = DateFormat('d MMM yyyy');
    final timeFmt = DateFormat('HH:mm');

    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        title: Text(invoice.invoiceNumber),
        backgroundColor: const Color(0xFF0F4C45),
        foregroundColor: Colors.white,
        elevation: 0,
        actions: [
          IconButton(
            tooltip: l10n.tr('Edit Items'),
            icon: const Icon(Icons.edit_note_outlined),
            onPressed: onEditItems,
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: Card(
              elevation: 4,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // ── Header ────────────────────────────────────────────
                    _InvoiceHeader(invoice: invoice, dateFmt: dateFmt),
                    const Divider(height: 40, thickness: 1.5),

                    // ── Bill To ───────────────────────────────────────────
                    _SectionLabel(l10n.tr('Bill To')),
                    const SizedBox(height: 8),
                    _InfoRow(Icons.person_outline, invoice.memberName),
                    if (invoice.memberEmail.isNotEmpty)
                      _InfoRow(Icons.email_outlined, invoice.memberEmail),
                    if (invoice.memberPhone.isNotEmpty)
                      _InfoRow(Icons.phone_outlined, invoice.memberPhone),
                    const SizedBox(height: 24),

                    // ── Line items ────────────────────────────────────────
                    _SectionLabel(l10n.tr('Items')),
                    const SizedBox(height: 8),
                    _ItemsTable(invoice: invoice),
                    const SizedBox(height: 20),

                    // ── Totals ────────────────────────────────────────────
                    _TotalsSection(invoice: invoice, l10n: l10n),
                    const Divider(height: 40, thickness: 1.5),

                    // ── Payment history ────────────────────────────────────
                    if (invoice.payments.isNotEmpty) ...[
                      _SectionLabel(l10n.tr('Payment History')),
                      const SizedBox(height: 8),
                      ...invoice.payments.map(
                        (p) => _PaymentRow(
                          payment: p,
                          currency: invoice.currency,
                          dateFmt: dateFmt,
                          timeFmt: timeFmt,
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // ── Notes ─────────────────────────────────────────────
                    if (invoice.notes.isNotEmpty) ...[
                      _SectionLabel(l10n.tr('Notes')),
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: cs.surfaceContainerLowest,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: cs.outlineVariant),
                        ),
                        child: Text(
                          invoice.notes,
                          style: const TextStyle(height: 1.5),
                        ),
                      ),
                      const SizedBox(height: 20),
                    ],

                    // (status badge removed — invoice total is shown in the items section)
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Edit items bottom sheet ────────────────────────────────────────────────────

class _EditItemsSheet extends StatefulWidget {
  const _EditItemsSheet({
    required this.invoice,
    required this.billingService,
  });
  final Invoice invoice;
  final BillingService billingService;

  @override
  State<_EditItemsSheet> createState() => _EditItemsSheetState();
}

class _EditItemsSheetState extends State<_EditItemsSheet> {
  /// Mutable copy of current items (description, amount, currency).
  late List<({TextEditingController desc, TextEditingController amount, String currency})> _rows;
  bool _saving = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    _rows = widget.invoice.items.map((item) {
      final desc = TextEditingController(text: item.description);
      final amount = TextEditingController(text: item.amount.toString());
      amount.addListener(() => setState(() {}));
      return (desc: desc, amount: amount, currency: item.currency);
    }).toList();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.desc.dispose();
      r.amount.dispose();
    }
    super.dispose();
  }

  void _addRow() {
    final currency = widget.invoice.currency;
    final desc = TextEditingController();
    final amount = TextEditingController();
    amount.addListener(() => setState(() {}));
    setState(() => _rows.add((desc: desc, amount: amount, currency: currency)));
  }

  void _removeRow(int index) {
    setState(() {
      final r = _rows.removeAt(index);
      r.desc.dispose();
      r.amount.dispose();
    });
  }

  int _total() => _rows.fold(
        0,
        (sum, r) => sum + (int.tryParse(r.amount.text.trim()) ?? 0),
      );

  Future<void> _save() async {
    final items = <InvoiceItem>[];
    for (final r in _rows) {
      final desc = r.desc.text.trim();
      final amt = int.tryParse(r.amount.text.trim()) ?? 0;
      if (desc.isEmpty) {
        setState(() => _error = context.l10n.tr('All items need a description.'));
        return;
      }
      if (amt <= 0) {
        setState(() => _error = context.l10n.tr('All items need an amount > 0.'));
        return;
      }
      items.add(InvoiceItem(description: desc, amount: amt, currency: r.currency));
    }
    if (items.isEmpty) {
      setState(() => _error = context.l10n.tr('Invoice must have at least one item.'));
      return;
    }

    setState(() {
      _saving = true;
      _error = '';
    });
    try {
      await widget.billingService.updateInvoiceItems(
        invoiceId: widget.invoice.id,
        items: items,
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e, s) {
      await CrashLogger.log(e, s, reason: 'EditItemsSheet._save');
      if (mounted) setState(() { _saving = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final mq = MediaQuery.of(context);
    final currency = widget.invoice.currency;
    final total = _total();

    return Container(
      height: mq.size.height * 0.85,
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Container(
            margin: const EdgeInsets.only(top: 10),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.grey.shade300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    l10n.tr('Edit Invoice Items'),
                    style: const TextStyle(fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.close),
                ),
              ],
            ),
          ),
          const Divider(height: 16),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
              children: [
                for (int i = 0; i < _rows.length; i++) ...[
                  _EditItemRow(
                    key: ValueKey(i),
                    descController: _rows[i].desc,
                    amountController: _rows[i].amount,
                    currency: currency,
                    onRemove: _rows.length > 1 ? () => _removeRow(i) : null,
                    l10n: l10n,
                  ),
                  const SizedBox(height: 8),
                ],
                TextButton.icon(
                  onPressed: _addRow,
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(l10n.tr('Add Item')),
                  style: TextButton.styleFrom(
                    foregroundColor: const Color(0xFF0F766E),
                    alignment: Alignment.centerLeft,
                    padding: EdgeInsets.zero,
                  ),
                ),
                const SizedBox(height: 12),
                // Total summary
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F4C45).withValues(alpha: 0.05),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: const Color(0xFF0F4C45).withValues(alpha: 0.15)),
                  ),
                  child: Row(
                    children: [
                      Text(l10n.tr('New Total'),
                          style: const TextStyle(fontWeight: FontWeight.w700)),
                      const Spacer(),
                      Text(
                        '$currency $total',
                        style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            fontSize: 16,
                            color: Color(0xFF0F4C45)),
                      ),
                    ],
                  ),
                ),
                if (_error.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.red.shade200),
                    ),
                    child: Text(_error,
                        style: TextStyle(color: Colors.red.shade700)),
                  ),
                ],
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: _saving ? null : _save,
                    style: FilledButton.styleFrom(
                      backgroundColor: const Color(0xFF0F766E),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.save_outlined),
                    label: Text(
                      _saving ? l10n.tr('Saving…') : l10n.tr('Save Changes'),
                      style: const TextStyle(
                          fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EditItemRow extends StatelessWidget {
  const _EditItemRow({
    super.key,
    required this.descController,
    required this.amountController,
    required this.currency,
    required this.onRemove,
    required this.l10n,
  });
  final TextEditingController descController;
  final TextEditingController amountController;
  final String currency;
  final VoidCallback? onRemove;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: TextField(
            controller: descController,
            decoration: InputDecoration(
              hintText: l10n.tr('Description'),
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          flex: 2,
          child: TextField(
            controller: amountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              hintText: l10n.tr('Amount'),
              prefixText: '$currency ',
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              isDense: true,
            ),
          ),
        ),
        if (onRemove != null)
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.remove_circle_outline, color: Colors.red),
            padding: const EdgeInsets.only(left: 4),
            constraints: const BoxConstraints(),
          )
        else
          const SizedBox(width: 36),
      ],
    );
  }
}

// ── Header ────────────────────────────────────────────────────────────────────

class _InvoiceHeader extends StatelessWidget {
  const _InvoiceHeader({required this.invoice, required this.dateFmt});
  final Invoice invoice;
  final DateFormat dateFmt;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Left: brand block
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF0F4C45),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Text(
                  'FitFlow',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    letterSpacing: 1,
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                context.l10n.tr('INVOICE'),
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w900,
                  color: Colors.grey.shade800,
                  letterSpacing: 3,
                ),
              ),
            ],
          ),
        ),
        // Right: invoice meta
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _MetaRow(context.l10n.tr('Invoice #'), invoice.invoiceNumber),
            const SizedBox(height: 4),
            _MetaRow(context.l10n.tr('Issued'), dateFmt.format(invoice.issuedAt)),
            if (invoice.dueDate != null) ...[
              const SizedBox(height: 4),
              _MetaRow(context.l10n.tr('Due'), dateFmt.format(invoice.dueDate!)),
            ],
          ],
        ),
      ],
    );
  }
}

class _MetaRow extends StatelessWidget {
  const _MetaRow(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          '$label: ',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 12),
        ),
        Text(
          value,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12),
        ),
      ],
    );
  }
}

// ── Items table ───────────────────────────────────────────────────────────────

class _ItemsTable extends StatelessWidget {
  const _ItemsTable({required this.invoice});
  final Invoice invoice;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF0F4C45),
              borderRadius: BorderRadius.only(
                topLeft: Radius.circular(7),
                topRight: Radius.circular(7),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(context.l10n.tr('Description'),
                      style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12)),
                ),
                Text(context.l10n.tr('Amount'),
                    style: const TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 12)),
              ],
            ),
          ),
          // Rows
          ...invoice.items.asMap().entries.map((entry) {
            final isLast = entry.key == invoice.items.length - 1;
            final item = entry.value;
            return Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: entry.key.isEven ? Colors.white : Colors.grey.shade50,
                borderRadius: isLast
                    ? const BorderRadius.only(
                        bottomLeft: Radius.circular(7),
                        bottomRight: Radius.circular(7),
                      )
                    : null,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Text(item.description,
                        style: const TextStyle(fontSize: 13)),
                  ),
                  Text(
                    '${item.currency} ${item.amount}',
                    style: const TextStyle(
                        fontWeight: FontWeight.w600, fontSize: 13),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ── Totals ────────────────────────────────────────────────────────────────────

class _TotalsSection extends StatelessWidget {
  const _TotalsSection({required this.invoice, required this.l10n});
  final Invoice invoice;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerRight,
      child: _TotalRow(
        l10n.tr('Total'),
        '${invoice.currency} ${invoice.totalAmount}',
        bold: true,
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value, {this.bold = false});
  final String label;
  final String value;
  final bool bold;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
      fontSize: bold ? 15 : 13,
    );
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        children: [
          Expanded(child: Text(label, style: style)),
          Text(value, style: style),
        ],
      ),
    );
  }
}

// ── Payment history row ───────────────────────────────────────────────────────

class _PaymentRow extends StatelessWidget {
  const _PaymentRow({
    required this.payment,
    required this.currency,
    required this.dateFmt,
    required this.timeFmt,
  });
  final InvoicePayment payment;
  final String currency;
  final DateFormat dateFmt;
  final DateFormat timeFmt;

  @override
  Widget build(BuildContext context) {
    final methodColor = _methodColor(payment.method);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: methodColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: methodColor.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(_methodIcon(payment.method), size: 18, color: methodColor),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  payment.method.toUpperCase(),
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: methodColor,
                    fontSize: 11,
                    letterSpacing: 0.5,
                  ),
                ),
                if (payment.notes.isNotEmpty)
                  Text(payment.notes,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$currency ${payment.amount}',
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 14),
              ),
              Text(
                '${dateFmt.format(payment.date)} ${timeFmt.format(payment.date)}',
                style: const TextStyle(fontSize: 11, color: Colors.grey),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Color _methodColor(String method) {
    switch (method.toLowerCase()) {
      case 'card':
        return const Color(0xFF2563EB);
      case 'transfer':
        return const Color(0xFF7C3AED);
      case 'cash':
      default:
        return const Color(0xFF059669);
    }
  }

  IconData _methodIcon(String method) {
    switch (method.toLowerCase()) {
      case 'card':
        return Icons.credit_card;
      case 'transfer':
        return Icons.swap_horiz;
      case 'cash':
      default:
        return Icons.payments_outlined;
    }
  }
}

// ── Helpers ───────────────────────────────────────────────────────────────────

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        color: Colors.grey.shade500,
        letterSpacing: 1.2,
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow(this.icon, this.text);
  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 14, color: Colors.grey.shade500),
          const SizedBox(width: 6),
          Flexible(
            child: Text(text, style: const TextStyle(fontSize: 13)),
          ),
        ],
      ),
    );
  }
}
