import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../l10n/app_localizations.dart';
import '../../models/invoice.dart';

/// Full-screen invoice view — looks like a printed invoice.
class InvoiceDetailScreen extends StatelessWidget {
  const InvoiceDetailScreen({super.key, required this.invoice});

  final Invoice invoice;

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

                    // ── Status badge ───────────────────────────────────────
                    Center(child: _StatusBadge(status: invoice.status, l10n: l10n)),
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
      child: SizedBox(
        width: 260,
        child: Column(
          children: [
            _TotalRow(l10n.tr('Total'), '${invoice.currency} ${invoice.totalAmount}',
                bold: false),
            _TotalRow(l10n.tr('Amount Paid'),
                '${invoice.currency} ${invoice.amountPaid}',
                color: Colors.green.shade700, bold: false),
            const Divider(height: 16, thickness: 1),
            _TotalRow(
              l10n.tr('Balance Due'),
              '${invoice.currency} ${invoice.remainingAmount}',
              bold: true,
              color: invoice.remainingAmount > 0
                  ? Colors.red.shade700
                  : Colors.green.shade700,
            ),
          ],
        ),
      ),
    );
  }
}

class _TotalRow extends StatelessWidget {
  const _TotalRow(this.label, this.value,
      {this.bold = false, this.color});
  final String label;
  final String value;
  final bool bold;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontWeight: bold ? FontWeight.w800 : FontWeight.normal,
      fontSize: bold ? 15 : 13,
      color: color,
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

// ── Status badge ──────────────────────────────────────────────────────────────

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status, required this.l10n});
  final String status;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) {
    Color bg;
    Color fg;
    switch (status) {
      case 'paid':
        bg = Colors.green.shade100;
        fg = Colors.green.shade800;
        break;
      case 'partial':
        bg = Colors.orange.shade100;
        fg = Colors.orange.shade800;
        break;
      default:
        bg = Colors.red.shade100;
        fg = Colors.red.shade800;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        status.toUpperCase(),
        style: TextStyle(
            color: fg, fontWeight: FontWeight.w800, letterSpacing: 1.5),
      ),
    );
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
