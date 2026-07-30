import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../../l10n/app_localizations.dart';
import '../../../models/product.dart';
import '../../../services/product_service.dart';
import '../../../services/storage_service.dart';
import '../../../utils/currency.dart';

/// Max size for an uploaded product image (matches the reference tool's
/// "Max 4mb" hint on the Create Product dialog).
const _kMaxImageBytes = 4 * 1024 * 1024;

/// Accepted image file extensions for product photos.
const _kAllowedImageExtensions = ['png', 'jpg', 'jpeg', 'webp'];

/// Store → Products: inventory list with search/category/status filters, a
/// "Create New" product dialog, and per-row edit/deactivate/delete actions.
class AdminProductsTab extends StatefulWidget {
  const AdminProductsTab({super.key, required this.gymId});

  final String gymId;

  @override
  State<AdminProductsTab> createState() => _AdminProductsTabState();
}

class _AdminProductsTabState extends State<AdminProductsTab> {
  late final _service = ProductService(gymId: widget.gymId);
  final _searchController = TextEditingController();
  String _searchQuery = '';
  String _categoryFilter = 'all';
  String _statusFilter = 'active'; // 'all' | 'active' | 'deactivated'
  List<String> _knownCategories = const [];

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Product> _filtered(List<Product> products) {
    final q = _searchQuery.toLowerCase();
    return products.where((p) {
      final matchSearch = q.isEmpty ||
          p.name.toLowerCase().contains(q) ||
          p.sku.toLowerCase().contains(q);
      final matchCategory =
          _categoryFilter == 'all' || p.category == _categoryFilter;
      final matchStatus = _statusFilter == 'all' ||
          (_statusFilter == 'active' ? p.active : !p.active);
      return matchSearch && matchCategory && matchStatus;
    }).toList();
  }

  Future<void> _openEditor([Product? product]) async {
    await showDialog<void>(
      context: context,
      builder: (_) => _ProductEditorDialog(
        service: _service,
        product: product,
        gymId: widget.gymId,
        existingCategories: _knownCategories,
      ),
    );
  }

  Future<void> _confirmDelete(Product product) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(context.l10n.tr('Delete product?')),
        content: Text(
          context.l10n
              .tr('This will permanently remove "{name}".')
              .replaceAll('{name}', product.name),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(context.l10n.tr('Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(context.l10n.tr('Delete')),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _service.delete(product.id);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(context.l10n.tr('Product deleted'))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        icon: const Icon(Icons.add),
        label: Text(context.l10n.tr('Create New')),
      ),
      body: StreamBuilder<List<Product>>(
        stream: _service.streamProducts(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const <Product>[];
          final categories = all
              .map((p) => p.category)
              .where((c) => c.isNotEmpty)
              .toSet()
              .toList()
            ..sort();
          _knownCategories = categories;
          final rows = _filtered(all);

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                child: Row(
                  children: [
                    Text(
                      context.l10n.tr('Products'),
                      style: Theme.of(context).textTheme.headlineSmall,
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
                            child: Text(context.l10n.tr('All categories')),
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
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _statusFilter,
                        decoration: InputDecoration(
                          labelText: context.l10n.tr('Status'),
                          isDense: true,
                          border: const OutlineInputBorder(),
                        ),
                        items: [
                          DropdownMenuItem(
                              value: 'all',
                              child: Text(context.l10n.tr('All'))),
                          DropdownMenuItem(
                              value: 'active',
                              child: Text(context.l10n.tr('Active'))),
                          DropdownMenuItem(
                              value: 'deactivated',
                              child: Text(context.l10n.tr('Deactivated'))),
                        ],
                        onChanged: (v) =>
                            setState(() => _statusFilter = v ?? 'active'),
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
                    : rows.isEmpty
                        ? Center(
                            child: Text(context.l10n.tr('No products yet')))
                        : _ProductsTable(
                            products: rows,
                            onEdit: _openEditor,
                            onToggleActive: (p) =>
                                _service.setActive(p.id, !p.active),
                            onDelete: _confirmDelete,
                          ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _ProductsTable extends StatelessWidget {
  const _ProductsTable({
    required this.products,
    required this.onEdit,
    required this.onToggleActive,
    required this.onDelete,
  });

  final List<Product> products;
  final ValueChanged<Product> onEdit;
  final ValueChanged<Product> onToggleActive;
  final ValueChanged<Product> onDelete;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: DataTable(
          columns: [
            DataColumn(label: Text(context.l10n.tr('Product'))),
            DataColumn(label: Text(context.l10n.tr('Category'))),
            DataColumn(label: Text(context.l10n.tr('SKU'))),
            DataColumn(label: Text(context.l10n.tr('Cost'))),
            DataColumn(label: Text(context.l10n.tr('Retail'))),
            DataColumn(label: Text(context.l10n.tr('VAT'))),
            DataColumn(label: Text(context.l10n.tr('Stock'))),
            DataColumn(label: Text(context.l10n.tr('Actions'))),
          ],
          rows: products.map((p) {
            return DataRow(cells: [
              DataCell(Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Opacity(opacity: p.active ? 1 : 0.5, child: Text(p.name)),
                  if (!p.active) ...[
                    const SizedBox(width: 6),
                    Chip(
                      label: Text(context.l10n.tr('Deactivated')),
                      visualDensity: VisualDensity.compact,
                      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ],
                ],
              )),
              DataCell(Text(p.category)),
              DataCell(Text(p.sku)),
              DataCell(Text(Currency.format(p.cost, Currency.defaultCode))),
              DataCell(
                  Text(Currency.format(p.retailPrice, Currency.defaultCode))),
              DataCell(Text(
                  p.vatPercent > 0 ? '${Currency.formatAmount(p.vatPercent)}%' : '—')),
              DataCell(Text(
                p.isUnlimitedStock ? context.l10n.tr('Unlimited') : '${p.stock}',
                style: TextStyle(
                  color: !p.isUnlimitedStock && p.stock <= 0 ? Colors.red : null,
                  fontWeight:
                      !p.isUnlimitedStock && p.stock <= 0 ? FontWeight.bold : null,
                ),
              )),
              DataCell(PopupMenuButton<String>(
                onSelected: (action) {
                  switch (action) {
                    case 'edit':
                      onEdit(p);
                    case 'toggle':
                      onToggleActive(p);
                    case 'delete':
                      onDelete(p);
                  }
                },
                itemBuilder: (ctx) => [
                  PopupMenuItem(
                      value: 'edit', child: Text(ctx.l10n.tr('Edit'))),
                  PopupMenuItem(
                    value: 'toggle',
                    child: Text(p.active
                        ? ctx.l10n.tr('Deactivate')
                        : ctx.l10n.tr('Activate')),
                  ),
                  PopupMenuItem(
                      value: 'delete', child: Text(ctx.l10n.tr('Delete'))),
                ],
              )),
            ]);
          }).toList(),
        ),
      ),
    );
  }
}

class _ProductEditorDialog extends StatefulWidget {
  const _ProductEditorDialog({
    required this.service,
    required this.gymId,
    this.product,
    this.existingCategories = const [],
  });

  final ProductService service;
  final String gymId;
  final Product? product;
  final List<String> existingCategories;

  @override
  State<_ProductEditorDialog> createState() => _ProductEditorDialogState();
}

class _ProductEditorDialogState extends State<_ProductEditorDialog> {
  late final _storageService = StorageService();
  late final _nameController =
      TextEditingController(text: widget.product?.name ?? '');
  late final _newCategoryController = TextEditingController();
  late final _skuController =
      TextEditingController(text: widget.product?.sku ?? '');
  late final _costController =
      TextEditingController(text: '${widget.product?.cost ?? 0}');
  late final _retailController =
      TextEditingController(text: '${widget.product?.retailPrice ?? 0}');
  late final _vatController =
      TextEditingController(text: '${widget.product?.vatPercent ?? 0}');
  late final _stockController = TextEditingController(
      text: '${widget.product?.stock ?? 0}');
  late final _descriptionController =
      TextEditingController(text: widget.product?.description ?? '');

  bool _active = true;
  bool _saving = false;
  String? _nameError;

  /// `'unlimited'` | `'limited'`.
  late String _stockType;

  /// `'current'` | `'new'` — matches the reference tool's
  /// "Select from Current" / "Create New Category" radio choice.
  late String _categoryMode;
  String? _selectedCategory;

  /// Already-uploaded image URLs plus any newly-picked-but-not-yet-uploaded
  /// bytes, capped at 3 total (matches the reference tool's "0 / 3" limit).
  late List<String> _imageUrls;
  final List<Uint8List> _pendingUploads = [];

  /// Filename kept alongside each pending upload so [StorageService] can
  /// infer the right content-type/extension once uploaded.
  final List<String> _pendingFilenames = [];
  bool _uploadingImage = false;

  bool get _displayInApp => widget.product?.displayInApp ?? true;

  @override
  void initState() {
    super.initState();
    _active = widget.product?.active ?? true;
    _stockType = widget.product?.stockType ?? 'unlimited';
    _imageUrls = List<String>.from(widget.product?.imageUrls ?? const []);
    final category = widget.product?.category ?? '';
    if (category.isNotEmpty && widget.existingCategories.contains(category)) {
      _categoryMode = 'current';
      _selectedCategory = category;
    } else if (category.isNotEmpty) {
      _categoryMode = 'new';
      _newCategoryController.text = category;
    } else {
      _categoryMode = widget.existingCategories.isEmpty ? 'new' : 'current';
    }
    _displayInAppValue = _displayInApp;
  }

  late bool _displayInAppValue;

  @override
  void dispose() {
    _nameController.dispose();
    _newCategoryController.dispose();
    _skuController.dispose();
    _costController.dispose();
    _retailController.dispose();
    _vatController.dispose();
    _stockController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  String get _resolvedCategory => _categoryMode == 'current'
      ? (_selectedCategory ?? '')
      : _newCategoryController.text.trim();

  Future<void> _pickImage() async {
    if (_imageUrls.length + _pendingUploads.length >= 3) return;
    final picked =
        await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final extension = _extensionOf(picked.name);
    if (!_kAllowedImageExtensions.contains(extension)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(context.l10n
                .tr('Unsupported file type. Use PNG, JPG or WEBP images.')),
          ),
        );
      }
      return;
    }

    final bytes = await picked.readAsBytes();

    if (bytes.lengthInBytes > _kMaxImageBytes) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              context.l10n
                  .tr('Image is too large ({size}MB). Max size is 4MB.')
                  .replaceAll(
                    '{size}',
                    (bytes.lengthInBytes / (1024 * 1024)).toStringAsFixed(1),
                  ),
            ),
          ),
        );
      }
      return;
    }

    setState(() {
      _pendingUploads.add(bytes);
      _pendingFilenames.add(picked.name);
    });
  }

  /// Lower-cased file extension (without the dot), or empty string if [name]
  /// has none.
  String _extensionOf(String name) {
    final dot = name.lastIndexOf('.');
    if (dot == -1 || dot == name.length - 1) return '';
    return name.substring(dot + 1).toLowerCase();
  }

  void _removeExistingImage(int index) {
    setState(() => _imageUrls.removeAt(index));
  }

  void _removePendingImage(int index) {
    setState(() {
      _pendingUploads.removeAt(index);
      _pendingFilenames.removeAt(index);
    });
  }

  Future<List<String>> _uploadPendingImages() async {
    if (_pendingUploads.isEmpty) return _imageUrls;
    setState(() => _uploadingImage = true);
    try {
      final uploaded = <String>[];
      for (var i = 0; i < _pendingUploads.length; i++) {
        final url = await _storageService.uploadProductImage(
          gymId: widget.gymId,
          filename: _pendingFilenames[i],
          bytes: _pendingUploads[i],
        );
        uploaded.add(url);
      }
      return [..._imageUrls, ...uploaded];
    } finally {
      if (mounted) setState(() => _uploadingImage = false);
    }
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      setState(() => _nameError = context.l10n.tr('Product name is required'));
      return;
    }
    setState(() => _saving = true);
    try {
      final cost = Currency.parse(_costController.text) ?? 0;
      final retail = Currency.parse(_retailController.text) ?? 0;
      final vat = Currency.parse(_vatController.text) ?? 0;
      final stock = int.tryParse(_stockController.text.trim()) ?? 0;
      final imageUrls = await _uploadPendingImages();

      if (widget.product == null) {
        await widget.service.create(Product(
          id: '',
          name: name,
          category: _resolvedCategory,
          sku: _skuController.text.trim(),
          cost: cost,
          retailPrice: retail,
          vatPercent: vat,
          stockType: _stockType,
          stock: _stockType == 'unlimited' ? 0 : stock,
          description: _descriptionController.text.trim(),
          displayInApp: _displayInAppValue,
          imageUrls: imageUrls,
          active: _active,
          gymId: widget.gymId,
          createdAt: DateTime.now(),
        ));
      } else {
        await widget.service.update(widget.product!.copyWith(
          name: name,
          category: _resolvedCategory,
          sku: _skuController.text.trim(),
          cost: cost,
          retailPrice: retail,
          vatPercent: vat,
          stockType: _stockType,
          stock: _stockType == 'unlimited' ? 0 : stock,
          description: _descriptionController.text.trim(),
          displayInApp: _displayInAppValue,
          imageUrls: imageUrls,
          active: _active,
        ));
      }
      if (mounted) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.product != null;
    final totalImages = _imageUrls.length + _pendingUploads.length;
    return AlertDialog(
      title: Text(isEdit
          ? context.l10n.tr('Edit product')
          : context.l10n.tr('Create Product')),
      content: SizedBox(
        width: 480,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextField(
                controller: _nameController,
                decoration: InputDecoration(
                  labelText: context.l10n.tr('Name'),
                  errorText: _nameError,
                ),
                onChanged: (_) => setState(() => _nameError = null),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _skuController,
                      decoration:
                          InputDecoration(labelText: context.l10n.tr('SKU')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _costController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                          labelText: context.l10n.tr('Cost Price')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: TextField(
                      controller: _retailController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                          labelText: context.l10n.tr('Retail Price')),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _vatController,
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: InputDecoration(
                          labelText: context.l10n.tr('VAT Percentage')),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: DropdownButtonFormField<String>(
                      value: _stockType,
                      decoration: InputDecoration(
                          labelText: context.l10n.tr('Stock Type')),
                      items: [
                        DropdownMenuItem(
                          value: 'unlimited',
                          child: Text(context.l10n.tr('Unlimited Stock')),
                        ),
                        DropdownMenuItem(
                          value: 'limited',
                          child: Text(context.l10n.tr('Limited Stock')),
                        ),
                      ],
                      onChanged: (v) =>
                          setState(() => _stockType = v ?? 'unlimited'),
                    ),
                  ),
                ],
              ),
              if (_stockType == 'limited') ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _stockController,
                  keyboardType: TextInputType.number,
                  decoration:
                      InputDecoration(labelText: context.l10n.tr('Stock')),
                ),
              ],
              const SizedBox(height: 16),
              Text(context.l10n.tr('Product Category'),
                  style: Theme.of(context).textTheme.labelLarge),
              Row(
                children: [
                  Radio<String>(
                    value: 'current',
                    groupValue: _categoryMode,
                    onChanged: (v) => setState(() => _categoryMode = v!),
                  ),
                  Text(context.l10n.tr('Select from Current')),
                  const SizedBox(width: 16),
                  Radio<String>(
                    value: 'new',
                    groupValue: _categoryMode,
                    onChanged: (v) => setState(() => _categoryMode = v!),
                  ),
                  Text(context.l10n.tr('Create New Category')),
                ],
              ),
              if (_categoryMode == 'current')
                DropdownButtonFormField<String>(
                  value: widget.existingCategories.contains(_selectedCategory)
                      ? _selectedCategory
                      : null,
                  decoration: InputDecoration(
                      labelText: context.l10n.tr('Select Category')),
                  items: widget.existingCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (v) => setState(() => _selectedCategory = v),
                )
              else
                TextField(
                  controller: _newCategoryController,
                  decoration: InputDecoration(
                      labelText: context.l10n.tr('New category name')),
                ),
              const SizedBox(height: 16),
              TextField(
                controller: _descriptionController,
                minLines: 3,
                maxLines: 5,
                decoration: InputDecoration(
                    labelText: context.l10n.tr('Description')),
              ),
              const SizedBox(height: 16),
              Text(context.l10n.tr('Display in App'),
                  style: Theme.of(context).textTheme.labelLarge),
              Row(
                children: [
                  Radio<bool>(
                    value: true,
                    groupValue: _displayInAppValue,
                    onChanged: (v) =>
                        setState(() => _displayInAppValue = v ?? true),
                  ),
                  Text(context.l10n.tr('Yes')),
                  const SizedBox(width: 16),
                  Radio<bool>(
                    value: false,
                    groupValue: _displayInAppValue,
                    onChanged: (v) =>
                        setState(() => _displayInAppValue = v ?? true),
                  ),
                  Text(context.l10n.tr('No')),
                ],
              ),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(context.l10n.tr('Active')),
                value: _active,
                onChanged: (v) => setState(() => _active = v),
              ),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(context.l10n.tr('Product Images'),
                      style: Theme.of(context).textTheme.labelLarge),
                  Text('$totalImages / 3'),
                ],
              ),
              Text(
                context.l10n.tr('Max 4mb • PNG recommended'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (var i = 0; i < _imageUrls.length; i++)
                    _ImageThumb(
                      imageUrl: _imageUrls[i],
                      onRemove: () => _removeExistingImage(i),
                    ),
                  for (var i = 0; i < _pendingUploads.length; i++)
                    _ImageThumb(
                      bytes: _pendingUploads[i],
                      onRemove: () => _removePendingImage(i),
                    ),
                  if (totalImages < 3)
                    InkWell(
                      onTap: _uploadingImage ? null : _pickImage,
                      child: Container(
                        width: 72,
                        height: 72,
                        decoration: BoxDecoration(
                          border: Border.all(
                              color: Theme.of(context).dividerColor),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: _uploadingImage
                            ? const Center(
                                child: SizedBox(
                                  width: 20,
                                  height: 20,
                                  child:
                                      CircularProgressIndicator(strokeWidth: 2),
                                ),
                              )
                            : Icon(Icons.add_photo_alternate_outlined,
                                color: Theme.of(context).colorScheme.primary),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context),
          child: Text(context.l10n.tr('Cancel')),
        ),
        FilledButton(
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : Text(context.l10n.tr('Submit')),
        ),
      ],
    );
  }
}

class _ImageThumb extends StatelessWidget {
  const _ImageThumb({this.imageUrl, this.bytes, required this.onRemove});

  final String? imageUrl;
  final Uint8List? bytes;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 72,
            height: 72,
            child: imageUrl != null
                ? Image.network(imageUrl!, fit: BoxFit.cover)
                : Image.memory(bytes!, fit: BoxFit.cover),
          ),
        ),
        Positioned(
          top: -6,
          right: -6,
          child: IconButton(
            icon: const Icon(Icons.cancel, size: 18),
            color: Colors.red,
            onPressed: onRemove,
          ),
        ),
      ],
    );
  }
}
