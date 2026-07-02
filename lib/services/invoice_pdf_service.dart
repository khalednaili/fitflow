import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';

import '../models/invoice.dart';
import '../utils/currency.dart';

/// Localized labels for the invoice PDF. English / French / Arabic.
class _PdfLabels {
  const _PdfLabels({
    required this.invoice,
    required this.creditNote,
    required this.billTo,
    required this.issueDate,
    required this.dueDate,
    required this.matriculeFiscal,
    required this.description,
    required this.vatPct,
    required this.amount,
    required this.tax,
    required this.total,
    required this.subtotal,
    required this.vat,
    required this.discount,
    required this.timbre,
    required this.totalRow,
    required this.notes,
    required this.paymentHistory,
    required this.dateCol,
    required this.methodCol,
    required this.pageOf,
  });

  final String invoice;
  final String creditNote;
  final String billTo;
  final String issueDate;
  final String dueDate;
  final String matriculeFiscal;
  final String description;
  final String vatPct;
  final String amount;
  final String tax;
  final String total;
  final String subtotal;
  final String vat;
  final String discount;
  final String timbre;
  final String totalRow;
  final String notes;
  final String paymentHistory;
  final String dateCol;
  final String methodCol;
  final String Function(int page, int pages) pageOf;

  static _PdfLabels forLanguage(String lang) {
    switch (lang) {
      case 'fr':
        return _PdfLabels(
          invoice: 'FACTURE',
          creditNote: "FACTURE D'AVOIR",
          billTo: 'FACTURÉ À',
          issueDate: "Date d'émission",
          dueDate: 'Échéance',
          matriculeFiscal: 'Matricule Fiscal',
          description: 'Désignation',
          vatPct: 'TVA %',
          amount: 'Montant',
          tax: 'TVA',
          total: 'Total',
          subtotal: 'Sous-total',
          vat: 'TVA',
          discount: 'Remise',
          timbre: 'Timbre Fiscal',
          totalRow: 'TOTAL TTC',
          notes: 'NOTES',
          paymentHistory: 'HISTORIQUE DES PAIEMENTS',
          dateCol: 'Date',
          methodCol: 'Mode',
          pageOf: (p, t) => 'Page $p / $t',
        );
      case 'ar':
        return _PdfLabels(
          invoice: 'فاتورة',
          creditNote: 'إشعار دائن',
          billTo: 'فوترة إلى',
          issueDate: 'تاريخ الإصدار',
          dueDate: 'تاريخ الاستحقاق',
          matriculeFiscal: 'المعرّف الجبائي',
          description: 'البيان',
          vatPct: 'الأداء ٪',
          amount: 'المبلغ',
          tax: 'الأداء',
          total: 'المجموع',
          subtotal: 'المجموع الفرعي',
          vat: 'الأداء على القيمة المضافة',
          discount: 'تخفيض',
          timbre: 'الطابع الجبائي',
          totalRow: 'المجموع الكلي',
          notes: 'ملاحظات',
          paymentHistory: 'سجل الدفعات',
          dateCol: 'التاريخ',
          methodCol: 'طريقة الدفع',
          pageOf: (p, t) => 'صفحة $p من $t',
        );
      default: // 'en'
        return _PdfLabels(
          invoice: 'INVOICE',
          creditNote: 'CREDIT NOTE',
          billTo: 'BILL TO',
          issueDate: 'Issue Date',
          dueDate: 'Due Date',
          matriculeFiscal: 'Matricule Fiscal',
          description: 'Description',
          vatPct: 'VAT %',
          amount: 'Amount',
          tax: 'Tax',
          total: 'Total',
          subtotal: 'Subtotal',
          vat: 'VAT / Tax',
          discount: 'Discount',
          timbre: 'Timbre Fiscal',
          totalRow: 'TOTAL',
          notes: 'NOTES',
          paymentHistory: 'PAYMENT HISTORY',
          dateCol: 'Date',
          methodCol: 'Method',
          pageOf: (p, t) => 'Page $p of $t',
        );
    }
  }
}

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
  /// Labels are rendered in [Invoice.language] ('en' | 'fr' | 'ar'); Arabic
  /// lays out right-to-left. Uses Unicode-capable fonts (Noto Sans + Noto Sans
  /// Arabic fallback) so non-Latin content renders correctly. The `pdf`
  /// package's built-in Helvetica is Latin-1 only and throws on other glyphs.
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

    final labels = _PdfLabels.forLanguage(invoice.language);
    final isRtl = invoice.language == 'ar';
    final pdf = pw.Document(theme: theme);
    // Locale-neutral numeric date (standard on Tunisian invoices), so month
    // names never need locale data.
    final dateFmt = DateFormat('dd/MM/yyyy');

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(40),
        textDirection: isRtl ? pw.TextDirection.rtl : pw.TextDirection.ltr,
        header: (ctx) => _header(invoice, labels),
        footer: (ctx) => _footer(ctx, labels),
        build: (ctx) => [
          pw.SizedBox(height: 24),
          _billTo(invoice, dateFmt, labels),
          pw.SizedBox(height: 20),
          _itemsTable(invoice, labels),
          pw.SizedBox(height: 12),
          _totals(invoice, labels),
          if (invoice.notes.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _notesSection(invoice, labels),
          ],
          if (invoice.payments.isNotEmpty) ...[
            pw.SizedBox(height: 20),
            _paymentHistory(invoice, dateFmt, labels),
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

  static pw.Widget _header(Invoice invoice, _PdfLabels labels) {
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
                invoice.isCreditNote ? labels.creditNote : labels.invoice,
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
                  '${labels.matriculeFiscal}: ${invoice.sellerTaxId}',
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

  static pw.Widget _billTo(
      Invoice invoice, DateFormat dateFmt, _PdfLabels labels) {
    return pw.Row(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: [
              _label(labels.billTo),
              pw.SizedBox(height: 4),
              pw.Text(invoice.memberName,
                  style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              if (invoice.memberEmail.isNotEmpty)
                pw.Text(invoice.memberEmail,
                    style: const pw.TextStyle(color: _grey, fontSize: 11)),
              if (invoice.memberPhone.isNotEmpty)
                pw.Text(invoice.memberPhone,
                    style: const pw.TextStyle(color: _grey, fontSize: 11)),
              if (invoice.memberAddress.isNotEmpty)
                pw.Text(invoice.memberAddress,
                    style: const pw.TextStyle(color: _grey, fontSize: 11)),
              if (invoice.memberTaxId.isNotEmpty)
                pw.Text('${labels.matriculeFiscal}: ${invoice.memberTaxId}',
                    style: const pw.TextStyle(color: _grey, fontSize: 11)),
            ],
          ),
        ),
        pw.Expanded(
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.end,
            children: [
              _dateRow(labels.issueDate, dateFmt.format(invoice.issuedAt)),
              if (invoice.dueDate != null)
                _dateRow(labels.dueDate, dateFmt.format(invoice.dueDate!)),
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

  static pw.Widget _itemsTable(Invoice invoice, _PdfLabels labels) {
    final hasVat = invoice.items.any((i) => i.taxRate > 0);

    final headers = [
      labels.description,
      if (hasVat) labels.vatPct,
      labels.amount,
      if (hasVat) labels.tax,
      labels.total,
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

  static pw.Widget _totals(Invoice invoice, _PdfLabels labels) {
    final rows = <(String, String)>[];

    if (invoice.taxAmount > 0 || invoice.discountAmount > 0) {
      rows.add(
          (labels.subtotal, Currency.format(invoice.subtotal, invoice.currency)));
    }
    if (invoice.taxAmount > 0) {
      rows.add(
          (labels.vat, Currency.format(invoice.taxAmount, invoice.currency)));
    }
    if (invoice.discountAmount > 0) {
      rows.add((labels.discount,
          '-${Currency.format(invoice.discountAmount, invoice.currency)}'));
    }
    if (invoice.stampDuty > 0) {
      rows.add((labels.timbre,
          Currency.format(invoice.stampDuty, invoice.currency)));
    }
    // Always show the total. The invoice intentionally omits amount-paid /
    // balance-due so it never reveals the outstanding (missing) amount.
    rows.add(
        (labels.totalRow, Currency.format(invoice.totalAmount, invoice.currency)));

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

  static pw.Widget _notesSection(Invoice invoice, _PdfLabels labels) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label(labels.notes),
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
      Invoice invoice, DateFormat dateFmt, _PdfLabels labels) {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.start,
      children: [
        _label(labels.paymentHistory),
        pw.SizedBox(height: 4),
        pw.TableHelper.fromTextArray(
          headers: [
            labels.dateCol,
            labels.methodCol,
            labels.amount,
            labels.notes,
          ],
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

  static pw.Widget _footer(pw.Context ctx, _PdfLabels labels) {
    return pw.Container(
      alignment: pw.Alignment.centerRight,
      margin: const pw.EdgeInsets.only(top: 8),
      child: pw.Text(
        labels.pageOf(ctx.pageNumber, ctx.pagesCount),
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
