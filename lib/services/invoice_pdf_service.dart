import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/invoice.dart';
import '../utils/currency.dart';

/// Generates, prints, and shares PDF invoices.
class InvoicePdfService {
  static const _brand = PdfColor.fromInt(0xFF0F4C45);
  static const _accent = PdfColor.fromInt(0xFF0F766E);
  static const _light = PdfColor.fromInt(0xFFE6F4F1);
  static const _grey = PdfColor.fromInt(0xFF6B7280);
  static const _red = PdfColor.fromInt(0xFFDC2626);

  // ── Public API ────────────────────────────────────────────────────────────

  /// Builds and returns the raw PDF bytes for [invoice].
  ///
  /// Uses Unicode-capable fonts (Noto Sans + Noto Sans Arabic fallback) so that
  /// non-Latin content — Arabic member names, accented notes, etc. — renders
  /// correctly. The `pdf` package's built-in Helvetica is Latin-1 only and
  /// throws ("Helvetica has no Unicode support") on any other glyph.
  static Future<Uint8List> generateBytes(Invoice invoice) async {
    final theme = pw.ThemeData.withFont(
      base: await PdfGoogleFonts.notoSansRegular(),
      bold: await PdfGoogleFonts.notoSansBold(),
      italic: await PdfGoogleFonts.notoSansItalic(),
      boldItalic: await PdfGoogleFonts.notoSansBoldItalic(),
      fontFallback: [
        await PdfGoogleFonts.notoSansArabicRegular(),
        await PdfGoogleFonts.notoSansArabicBold(),
      ],
    );

    final pdf = pw.Document(theme: theme);
    final dateFmt = DateFormat('d MMM yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        header: (ctx) => _header(invoice),
        footer: (ctx) => _footer(ctx),
        build: (ctx) => [
          pw.SizedBox(height: 24),
          _billTo(invoice, dateFmt),
          pw.SizedBox(height: 20),
          _itemsTable(invoice),
          pw.SizedBox(height: 12),
          _totals(invoice),
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _notesSection(invoice),
          ],
          if (invoice.payments.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _paymentHistory(invoice, dateFmt),
          ],
        ],
      ),
    );

    return pdf.save();
  }

  /// Opens the system print dialog for [invoice].
  static Future<void> printInvoice(Invoice invoice) async {
    final bytes = await generateBytes(invoice);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  /// Opens the system share sheet for [invoice].
  static Future<void> shareInvoice(Invoice invoice) async {
    final bytes = await generateBytes(invoice);
    await Printing.sharePdf(
      bytes: bytes,
      filename: '${invoice.invoiceNumber}.pdf',
    );
  }

  // ── PDF sections ──────────────────────────────────────────────────────────

  static pw.Widget _header(Invoice invoice) {
    return pw.Container(
      padding: const pw.EdgeInsets.only(bottom: 12),
      decoration: const pw.BoxDecoration(
        border: pw.Border(
          bottom: pw.BorderSide(color: _brand, width: 2),
        ),
      ),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
        crossAxisAlignment: pw.CrossAxisAlignment.start,
        children: [
          pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              pw.Text(
                invoice.isCreditNote ? 'CREDIT NOTE' : 'INVOICE',
                style: pw.TextStyle(
                  fontSize: 28,
                  fontWeight: pw.FontWeight.bold,
                  color: _brand,
                ),
              ),
              pw.SizedBox(height: 2),
              pw.Text(
                invoice.invoiceNumber,
                style: const pw.TextStyle(fontSize: 13, color: _grey),
              ),
              // Seller identity (Tunisian matricule fiscal etc.)
              if (invoice.sellerName.isNotEmpty) ...[
                pw.SizedBox(height: 8),
                pw.Text(
                  invoice.sellerName,
                  style: pw.TextStyle(
                      fontSize: 11, fontWeight: pw.FontWeight.bold),
                ),
              ],
              if (invoice.sellerAddress.isNotEmpty)
                pw.Text(
                  invoice.sellerAddress,
                  style: const pw.TextStyle(fontSize: 10, color: _grey),
                ),
              if (invoice.sellerTaxId.isNotEmpty)
                pw.Text(
                  'Matricule Fiscal: ${invoice.sellerTaxId}',
                  style: const pw.TextStyle(fontSize: 10, color: _grey),
                ),
            ],
          ),
          _statusBadge(invoice),
        ],
      ),
    );
  }

  static pw.Widget _statusBadge(Invoice invoice) {
    final color = switch (invoice.status) {
      InvoiceStatus.paid => PdfColors.green700,
      InvoiceStatus.partial => PdfColors.orange700,
      InvoiceStatus.overdue => _red,
      InvoiceStatus.void_ => _grey,
      InvoiceStatus.draft => _grey,
      _ => _accent,
    };
    return pw.Container(
      padding:
          const pw.EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: pw.BoxDecoration(
        color: color,
        borderRadius: pw.BorderRadius.circular(4),
      ),
      child: pw.Text(
        invoice.status.toUpperCase(),
        style: pw.TextStyle(
          fontSize: 10,
          fontWeight: pw.FontWeight.bold,
          color: PdfColors.white,
        ),
      ),
    );
  }

  static pw.Widget _billTo(Invoice invoice, DateFormat dateFmt) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _label('BILL TO'),
              pw.SizedBox(height: 4),
              pw.Text(invoice.memberName,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if (invoice.memberEmail.isNotEmpty)
                pw.Text(invoice.memberEmail,
                    style: const pw.TextStyle(color: _grey, fontSize: 11)),
              if (invoice.memberPhone.isNotEmpty)
                pw.Text(invoice.memberPhone,
                    style: const pw.TextStyle(color: _grey, fontSize: 11)),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _dateRow('Issue Date', dateFmt.format(invoice.issuedAt)),
              if (invoice.dueDate != null)
                _dateRow('Due Date', dateFmt.format(invoice.dueDate!)),
            ],
          ),
        ),
      ],
    );
  }

  static pw.Widget _dateRow(String label, String value) {
    return pw.Padding(
      padding: const pw.EdgeInsets.only(bottom: 4),
      child: pw.Row(
        mainAxisAlignment: pw.MainAxisAlignment.end,
        children: [
          pw.Text('$label: ',
              style: const pw.TextStyle(color: _grey, fontSize: 11)),
          pw.Text(value,
              style: pw.TextStyle(
                  fontWeight: pw.FontWeight.bold, fontSize: 11)),
        ],
      ),
    );
  }

  static pw.Widget _itemsTable(Invoice invoice) {
    final hasVat = invoice.items.any((i) => i.taxRate > 0);

    final headers = [
      'Description',
      if (hasVat) 'VAT %',
      'Amount',
      if (hasVat) 'Tax',
      'Total',
    ];

    final rows = invoice.items.map((item) {
      return [
        item.description,
        if (hasVat) '${item.taxRate}%',
        Currency.format(item.amount, invoice.currency),
        if (hasVat) Currency.format(item.taxAmount, invoice.currency),
        Currency.format(item.amount + item.taxAmount, invoice.currency),
      ];
    }).toList();

    return pw.TableHelper.fromTextArray(
      headers: headers,
      data: rows,
      headerStyle: pw.TextStyle(
        fontWeight: pw.FontWeight.bold,
        color: PdfColors.white,
        fontSize: 11,
      ),
      headerDecoration:
          const pw.BoxDecoration(color: _brand),
      headerCellDecoration: const pw.BoxDecoration(color: _brand),
      oddRowDecoration: const pw.BoxDecoration(color: PdfColors.grey100),
      cellStyle: const pw.TextStyle(fontSize: 11),
      cellAlignments: {
        0: pw.Alignment.centerLeft,
        1: pw.Alignment.center,
        2: pw.Alignment.centerRight,
        3: pw.Alignment.centerRight,
        4: pw.Alignment.centerRight,
      },
      border: const pw.TableBorder(
        bottom: pw.BorderSide(color: _accent, width: 0.5),
        horizontalInside: pw.BorderSide(color: PdfColors.grey300, width: 0.5),
      ),
    );
  }

  static pw.Widget _totals(Invoice invoice) {
    final rows = <(String, String)>[];

    if (invoice.taxAmount > 0 || invoice.discountAmount > 0) {
      rows.add(('Subtotal', Currency.format(invoice.subtotal, invoice.currency)));
    }
    if (invoice.taxAmount > 0) {
      rows.add(('VAT / Tax', Currency.format(invoice.taxAmount, invoice.currency)));
    }
    if (invoice.discountAmount > 0) {
      rows.add(('Discount', '-${Currency.format(invoice.discountAmount, invoice.currency)}'));
    }
    if (invoice.stampDuty > 0) {
      rows.add(('Timbre Fiscal',
          Currency.format(invoice.stampDuty, invoice.currency)));
    }
    // Always show the total. The invoice intentionally omits amount-paid /
    // balance-due so it never reveals the outstanding (missing) amount.
    rows.add(('TOTAL', Currency.format(invoice.totalAmount, invoice.currency)));

    return pw.Align(
      alignment: pw.Alignment.centerRight,
      child: pw.Container(
        width: 260,
        decoration: pw.BoxDecoration(
          color: _light,
          borderRadius: pw.BorderRadius.circular(6),
        ),
        padding: const pw.EdgeInsets.all(12),
        child: pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.stretch,
          children: rows.asMap().entries.map((e) {
            final isTotal = e.key == rows.length - 1;
            return pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 3),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(
                    e.value.$1,
                    style: pw.TextStyle(
                      fontSize: isTotal ? 13 : 11,
                      fontWeight:
                          isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: isTotal ? _accent : null,
                    ),
                  ),
                  pw.Text(
                    e.value.$2,
                    style: pw.TextStyle(
                      fontSize: isTotal ? 13 : 11,
                      fontWeight:
                          isTotal ? pw.FontWeight.bold : pw.FontWeight.normal,
                      color: isTotal ? _accent : null,
                    ),
                  ),
                ],
              ),
            );
          }).toList(),
        ),
      ),
    );
  }

  static pw.Widget _notesSection(Invoice invoice) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label('NOTES'),
        pw.SizedBox(height: 4),
        pw.Container(
          width: double.infinity,
          padding: const pw.EdgeInsets.all(10),
          decoration: pw.BoxDecoration(
            border: pw.Border.all(color: PdfColors.grey300),
            borderRadius: pw.BorderRadius.circular(4),
          ),
          child: pw.Text(invoice.notes,
              style: const pw.TextStyle(fontSize: 11, color: _grey)),
        ),
      ],
    );
  }

  static pw.Widget _paymentHistory(
      Invoice invoice, DateFormat dateFmt) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label('PAYMENT HISTORY'),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: ['Date', 'Method', 'Amount', 'Notes'],
          data: invoice.payments
              .map((p) => [
                    dateFmt.format(p.date),
                    p.method,
                    Currency.format(p.amount, invoice.currency),
                    p.notes,
                  ])
              .toList(),
          headerStyle: pw.TextStyle(
              fontWeight: pw.FontWeight.bold,
              color: PdfColors.white,
              fontSize: 10),
          headerDecoration: const pw.BoxDecoration(color: _accent),
          cellStyle: const pw.TextStyle(fontSize: 10),
          border: const pw.TableBorder(
            bottom: pw.BorderSide(color: _accent, width: 0.5),
            horizontalInside:
                pw.BorderSide(color: PdfColors.grey300, width: 0.5),
          ),
        ),
      ],
    );
  }

  static pw.Widget _footer(pw.Context ctx) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        'Page ${ctx.pageNumber} of ${ctx.pagesCount}',
        style: const pw.TextStyle(fontSize: 9, color: _grey),
      ),
    );
  }

  static pw.Widget _label(String text) => pw.Text(
        text,
        style: pw.TextStyle(
          fontSize: 9,
          fontWeight: pw.FontWeight.bold,
          color: _grey,
          letterSpacing: 1,
        ),
      );
}
