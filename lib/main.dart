import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'firebase_options.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const StockInventoryApp());
}

class StockInventoryApp extends StatelessWidget {
  const StockInventoryApp({super.key});

  static const Color _primary = Color(0xFF087F73);
  static const Color _pageBackground = Color(0xFFF3F7F7);

  @override
  Widget build(BuildContext context) {
    final colorScheme = ColorScheme.fromSeed(
      seedColor: _primary,
      brightness: Brightness.light,
    );

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Stock Inventory Manager',
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: colorScheme,
        scaffoldBackgroundColor: _pageBackground,
        appBarTheme: const AppBarTheme(
          backgroundColor: _pageBackground,
          foregroundColor: Color(0xFF172B2A),
          elevation: 0,
          surfaceTintColor: Colors.transparent,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFFF7FAFA),
          contentPadding:
          const EdgeInsets.symmetric(horizontal: 15, vertical: 16),
          hintStyle: const TextStyle(color: Color(0xFF8A9A98)),
          labelStyle: const TextStyle(color: Color(0xFF60716F)),
          prefixIconColor: const Color(0xFF71827F),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDCE6E4)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFDCE6E4)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _primary, width: 1.6),
          ),
          errorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9534F)),
          ),
          focusedErrorBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Color(0xFFD9534F), width: 1.5),
          ),
        ),
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            minimumSize: const Size.fromHeight(52),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(13),
            ),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        textTheme: const TextTheme(
          headlineMedium: TextStyle(
            color: Color(0xFF172B2A),
            fontSize: 27,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
          ),
          titleLarge: TextStyle(
            color: Color(0xFF1F3331),
            fontSize: 19,
            fontWeight: FontWeight.w700,
          ),
          bodyMedium: TextStyle(color: Color(0xFF60716F), fontSize: 14),
        ),
      ),
      home: const InventoryPage(),
    );
  }
}

/// Forces typed text to upper case (so "stk-101" becomes "STK-101").
class _UpperCaseFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
      TextEditingValue oldValue,
      TextEditingValue newValue,
      ) {
    return newValue.copyWith(text: newValue.text.toUpperCase());
  }
}

class InventoryPage extends StatefulWidget {
  const InventoryPage({super.key});

  @override
  State<InventoryPage> createState() => _InventoryPageState();
}

class _InventoryPageState extends State<InventoryPage> {
  final _formKey = GlobalKey<FormState>();
  final _skuController = TextEditingController();
  final _nameController = TextEditingController();
  final _quantityController = TextEditingController();
  final _priceController = TextEditingController();
  final _reorderController = TextEditingController();
  final _searchController = TextEditingController();

  static const Color _primary = Color(0xFF087F73);
  static const Color _textDark = Color(0xFF1F3331);
  static const Color _muted = Color(0xFF71827F);

  static const List<String> _categories = [
    'Electronics',
    'Stationery',
    'Hardware',
    'Grocery',
  ];

  String? _category;
  String _keyword = '';
  String _filterCategory = 'All';
  DateTime? _filterDate;
  bool _lowStockOnly = false;
  bool _ascending = true;
  bool _saving = false;

  // Changed after every successful save so the category dropdown is rebuilt
  // from scratch and always shows "Select a category" again.
  int _formVersion = 0;

  CollectionReference<Map<String, dynamic>> get _stockCollection =>
      FirebaseFirestore.instance.collection('stockItems');

  @override
  void dispose() {
    _skuController.dispose();
    _nameController.dispose();
    _quantityController.dispose();
    _priceController.dispose();
    _reorderController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------------------------------------------------------------------
  // Validators (specific, field-level messages)
  // ---------------------------------------------------------------------------

  String? _validateSku(String? value) {
    final sku = (value ?? '').trim();
    if (sku.isEmpty) return 'SKU is required';
    if (!RegExp(r'^STK-\d{3}$').hasMatch(sku)) {
      return 'Invalid SKU. Use STK- followed by 3 digits, e.g. STK-101';
    }
    return null;
  }

  String? _validateName(String? value) {
    final name = (value ?? '').trim();
    if (name.isEmpty) return 'Item name is required';
    if (name.length < 3) return 'Item name must be at least 3 characters';
    return null;
  }

  String? _validateWholeNumber(String? value, String fieldName) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return '$fieldName is required';
    final number = int.tryParse(text);
    if (number == null) {
      return '$fieldName must be a whole number (no decimals or letters)';
    }
    if (number < 0) return '$fieldName cannot be negative';
    return null;
  }

  String? _validatePrice(String? value) {
    final text = (value ?? '').trim();
    if (text.isEmpty) return 'Unit price is required';
    final price = double.tryParse(text);
    if (price == null || !price.isFinite) {
      return 'Enter a valid price, e.g. 19.90';
    }
    if (price <= 0) return 'Unit price must be greater than RM0.00';
    return null;
  }

  // ---------------------------------------------------------------------------
  // Save to Firestore
  // ---------------------------------------------------------------------------

  Future<void> _saveItem() async {
    FocusScope.of(context).unfocus();

    // Validation gate: nothing is written to Firestore if any field is invalid.
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);
    try {
      // The Future completes only after Firestore acknowledges the write.
      await _stockCollection.add({
        'sku': _skuController.text.trim().toUpperCase(),
        'itemName': _nameController.text.trim(),
        'category': _category,
        'quantity': int.parse(_quantityController.text.trim()),
        'unitPrice': double.parse(_priceController.text.trim()),
        'reorderLevel': int.parse(_reorderController.text.trim()),
        'createdAt': FieldValue.serverTimestamp(),
      }).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      // Clear the form only AFTER the confirmed write.
      _skuController.clear();
      _nameController.clear();
      _quantityController.clear();
      _priceController.clear();
      _reorderController.clear();
      _formKey.currentState!.reset();
      setState(() {
        _category = null;
        _formVersion++;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF176B53),
          content: const Row(
            children: [
              Icon(Icons.check_circle_outline, color: Colors.white),
              SizedBox(width: 10),
              Expanded(child: Text('Stock item saved successfully.')),
            ],
          ),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      final String reason;
      if (error is TimeoutException) {
        reason = 'The request timed out. Check your connection and try again.';
      } else if (error is FirebaseException) {
        reason = error.message ?? error.code;
      } else {
        reason = error.toString();
      }
      // The form is NOT cleared on failure.
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: const Color(0xFF9E3632),
          content: Text('Save failed. Your form was kept. $reason'),
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _pickFilterDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _filterDate ?? now,
      firstDate: DateTime(2000),
      lastDate: DateTime(now.year + 10),
      helpText: 'Filter by stock creation date',
      cancelText: 'CANCEL',
      confirmText: 'APPLY',
    );

    if (!mounted || picked == null) return;
    setState(() => _filterDate = DateTime(picked.year, picked.month, picked.day));
  }

  bool _isSameLocalDate(DateTime timestamp, DateTime selectedDate) {
    final localTimestamp = timestamp.toLocal();
    return localTimestamp.year == selectedDate.year &&
        localTimestamp.month == selectedDate.month &&
        localTimestamp.day == selectedDate.day;
  }

  String _formatFilterDate(DateTime date) {
    String twoDigits(int number) => number.toString().padLeft(2, '0');
    return '${twoDigits(date.day)}/${twoDigits(date.month)}/${date.year}';
  }

  void _clearFilters() {
    _searchController.clear();
    setState(() {
      _keyword = '';
      _filterCategory = 'All';
      _filterDate = null;
      _lowStockOnly = false;
      _ascending = true;
    });
  }

  // ---------------------------------------------------------------------------
  // UI
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 76,
        titleSpacing: MediaQuery.of(context).size.width >= 600 ? 24 : 16,
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: const Color(0xFFDDF2ED),
                borderRadius: BorderRadius.circular(13),
              ),
              child: const Icon(
                Icons.inventory_2_rounded,
                color: _primary,
                size: 23,
              ),
            ),
            const SizedBox(width: 12),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Stock Manager',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                    color: _textDark,
                  ),
                ),
                SizedBox(height: 2),
                Text(
                  'INVENTORY CONTROL',
                  style: TextStyle(
                    fontSize: 10,
                    letterSpacing: 1.35,
                    fontWeight: FontWeight.w700,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: MediaQuery.of(context).size.width >= 560
            ? [
          Padding(
            padding: const EdgeInsets.only(right: 24),
            child: Center(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: const Color(0xFFE3EBEA)),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.cloud_done_outlined,
                        size: 16, color: _primary),
                    SizedBox(width: 7),
                    Text(
                      'CLOUD FIRESTORE',
                      style: TextStyle(
                        fontSize: 10,
                        letterSpacing: 0.8,
                        fontWeight: FontWeight.w800,
                        color: _textDark,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ]
            : const [],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth >= 1080;
          final horizontalPadding = constraints.maxWidth >= 1400
              ? 38.0
              : constraints.maxWidth >= 700
              ? 26.0
              : 16.0;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              horizontalPadding,
              22,
              horizontalPadding,
              36,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1540),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _pageHeading(),
                    const SizedBox(height: 22),
                    if (isWide)
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          SizedBox(width: 410, child: _buildFormPanel()),
                          const SizedBox(width: 22),
                          Expanded(child: _buildInventoryPanel()),
                        ],
                      )
                    else ...[
                      _buildFormPanel(),
                      const SizedBox(height: 22),
                      _buildInventoryPanel(),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _pageHeading() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Inventory overview',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 27,
                  height: 1.2,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.7,
                ),
              ),
              SizedBox(height: 6),
              Text(
                'Add stock, monitor quantities and find items quickly.',
                style: TextStyle(color: _muted, fontSize: 14),
              ),
            ],
          ),
        ),
        if (MediaQuery.of(context).size.width >= 520) ...[
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFFE6F4F0),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.verified_user_outlined, size: 15, color: _primary),
                SizedBox(width: 6),
                Text(
                  'NET4207 LAB',
                  style: TextStyle(
                    color: _primary,
                    fontSize: 10,
                    letterSpacing: 0.7,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildFormPanel() {
    return _panel(
      child: Form(
        key: _formKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _panelTitle(
              icon: Icons.add_box_outlined,
              title: 'Add a stock item',
              subtitle: 'Enter the item details below',
            ),
            const SizedBox(height: 22),
            _fieldLabel('SKU'),
            TextFormField(
              controller: _skuController,
              textCapitalization: TextCapitalization.characters,
              inputFormatters: [_UpperCaseFormatter()],
              decoration: const InputDecoration(
                hintText: 'e.g. STK-101',
                prefixIcon: Icon(Icons.qr_code_2_rounded),
              ),
              validator: _validateSku,
            ),
            const SizedBox(height: 15),
            _fieldLabel('Item name'),
            TextFormField(
              controller: _nameController,
              textCapitalization: TextCapitalization.words,
              decoration: const InputDecoration(
                hintText: 'e.g. USB C Cable',
                prefixIcon: Icon(Icons.inventory_2_outlined),
              ),
              validator: _validateName,
            ),
            const SizedBox(height: 15),
            _fieldLabel('Category'),
            DropdownButtonFormField<String>(
              key: ValueKey('category-$_formVersion'),
              value: _category,
              isExpanded: true,
              decoration: const InputDecoration(
                hintText: 'Select a category',
                prefixIcon: Icon(Icons.category_outlined),
              ),
              items: _categories
                  .map((category) => DropdownMenuItem(
                value: category,
                child: Text(category),
              ))
                  .toList(),
              onChanged: (value) => setState(() => _category = value),
              validator: (value) =>
              value == null ? 'Please select a category' : null,
            ),
            const SizedBox(height: 15),
            _fieldLabel('Quantity'),
            TextFormField(
              controller: _quantityController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: '0',
                prefixIcon: Icon(Icons.numbers_rounded),
              ),
              validator: (value) => _validateWholeNumber(value, 'Quantity'),
            ),
            const SizedBox(height: 15),
            _fieldLabel('Unit price (RM)'),
            TextFormField(
              controller: _priceController,
              keyboardType:
              const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(
                hintText: 'e.g. 19.90',
                prefixIcon: Icon(Icons.payments_outlined),
              ),
              validator: _validatePrice,
            ),
            const SizedBox(height: 15),
            _fieldLabel('Reorder level'),
            TextFormField(
              controller: _reorderController,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(
                hintText: 'e.g. 5',
                prefixIcon: Icon(Icons.notifications_active_outlined),
              ),
              validator: (value) =>
                  _validateWholeNumber(value, 'Reorder level'),
            ),
            const SizedBox(height: 22),
            FilledButton.icon(
              onPressed: _saving ? null : _saveItem,
              icon: _saving
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
                  : const Icon(Icons.add_rounded, size: 20),
              label: Text(_saving ? 'Saving item...' : 'Save Item'),
            ),
            const SizedBox(height: 10),
            const Text(
              'All fields are required. Items are saved to Cloud Firestore.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _muted, fontSize: 11, height: 1.4),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInventoryPanel() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _stockCollection.snapshots(),
      builder: (context, snapshot) {
        final allItems = snapshot.data?.docs
            .map((doc) => StockItem.fromMap(doc.id, doc.data()))
            .toList() ??
            <StockItem>[];

        // AND between all active controls.
        final query = _keyword.toLowerCase();
        final items = allItems.where((item) {
          final matchesKeyword = query.isEmpty ||
              item.itemName.toLowerCase().contains(query) ||
              item.sku.toLowerCase().contains(query);
          final matchesCategory =
              _filterCategory == 'All' || item.category == _filterCategory;
          final matchesLowStock =
              !_lowStockOnly || item.quantity <= item.reorderLevel;
          final matchesDate = _filterDate == null ||
              (item.createdAt != null &&
                  _isSameLocalDate(item.createdAt!, _filterDate!));
          return matchesKeyword &&
              matchesCategory &&
              matchesLowStock &&
              matchesDate;
        }).toList()
          ..sort((a, b) {
            final byQuantity = _ascending
                ? a.quantity.compareTo(b.quantity)
                : b.quantity.compareTo(a.quantity);
            // Tie-break on SKU so equal quantities keep a stable order.
            return byQuantity != 0 ? byQuantity : a.sku.compareTo(b.sku);
          });

        return _panel(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _panelTitle(
                icon: Icons.warehouse_outlined,
                title: 'Firestore inventory',
                subtitle: 'Your saved stock records',
                trailing: Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFE8F4F1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${snapshot.hasData ? allItems.length : '—'} ITEMS',
                    style: const TextStyle(
                      color: _primary,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.6,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 18),
              _buildSummaryStats(allItems),
              const SizedBox(height: 24),
              const Text(
                'Find an item',
                style: TextStyle(
                  color: _textDark,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 10),
              TextField(
                controller: _searchController,
                decoration: const InputDecoration(
                  hintText: 'Search by item name or SKU...',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
                onChanged: (value) => setState(() => _keyword = value.trim()),
              ),
              const SizedBox(height: 12),
              LayoutBuilder(
                builder: (context, constraints) {
                  final filterWidth = constraints.maxWidth >= 700
                      ? 220.0
                      : constraints.maxWidth;
                  return Wrap(
                    spacing: 10,
                    runSpacing: 10,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      SizedBox(
                        width: filterWidth,
                        child: DropdownButtonFormField<String>(
                          key: ValueKey('filter-$_filterCategory'),
                          value: _filterCategory,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Category',
                            prefixIcon: Icon(Icons.filter_list_rounded),
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 12,
                              vertical: 12,
                            ),
                          ),
                          items: ['All', ..._categories]
                              .map((category) => DropdownMenuItem(
                            value: category,
                            child: Text(category),
                          ))
                              .toList(),
                          onChanged: (value) => setState(
                                () => _filterCategory = value ?? 'All',
                          ),
                        ),
                      ),
                      OutlinedButton.icon(
                        onPressed: _pickFilterDate,
                        icon: const Icon(Icons.calendar_month_outlined, size: 18),
                        label: Text(
                          _filterDate == null
                              ? 'Created date'
                              : _formatFilterDate(_filterDate!),
                        ),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _filterDate == null
                              ? const Color(0xFF526562)
                              : _primary,
                          backgroundColor: _filterDate == null
                              ? Colors.white
                              : const Color(0xFFE8F4F1),
                          side: BorderSide(
                            color: _filterDate == null
                                ? const Color(0xFFDCE6E4)
                                : const Color(0xFF9CCFC3),
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 15,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                      ),
                      if (_filterDate != null)
                        IconButton(
                          tooltip: 'Clear created date filter',
                          onPressed: () => setState(() => _filterDate = null),
                          icon: const Icon(Icons.close_rounded),
                          color: _muted,
                        ),
                      FilterChip(
                        selected: _lowStockOnly,
                        showCheckmark: true,
                        avatar: Icon(
                          Icons.warning_amber_rounded,
                          size: 17,
                          color: _lowStockOnly
                              ? _primary
                              : const Color(0xFF9A6B25),
                        ),
                        label: const Text('Low stock only'),
                        onSelected: (value) =>
                            setState(() => _lowStockOnly = value),
                        selectedColor: const Color(0xFFDDF2ED),
                        side: BorderSide(
                          color: _lowStockOnly
                              ? const Color(0xFF9CCFC3)
                              : const Color(0xFFDCE6E4),
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(11),
                        ),
                      ),
                      SegmentedButton<bool>(
                        showSelectedIcon: false,
                        style: SegmentedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          foregroundColor: const Color(0xFF526562),
                          selectedForegroundColor: _primary,
                          selectedBackgroundColor: const Color(0xFFDDF2ED),
                        ),
                        segments: const [
                          ButtonSegment<bool>(
                            value: true,
                            icon: Icon(Icons.arrow_upward_rounded, size: 15),
                            label: Text('Qty Low–High'),
                          ),
                          ButtonSegment<bool>(
                            value: false,
                            icon: Icon(Icons.arrow_downward_rounded, size: 15),
                            label: Text('Qty High–Low'),
                          ),
                        ],
                        selected: {_ascending},
                        onSelectionChanged: (selection) => setState(
                              () => _ascending = selection.first,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: _clearFilters,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Clear Filters'),
                        style: TextButton.styleFrom(
                          foregroundColor: _primary,
                          textStyle: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
              const SizedBox(height: 22),
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Stock items',
                      style: TextStyle(
                        color: _textDark,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  Text(
                    '${items.length} shown',
                    style: const TextStyle(
                      color: _muted,
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              if (snapshot.hasError)
                _stateMessage(
                  icon: Icons.cloud_off_outlined,
                  title: 'Could not load inventory',
                  message:
                  'Check your Firebase connection and access rules.\n${snapshot.error}',
                  isError: true,
                )
              else if (snapshot.connectionState == ConnectionState.waiting &&
                  !snapshot.hasData)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 44),
                  child: Center(
                    child: Column(
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 12),
                        Text(
                          'Loading Firestore records...',
                          style: TextStyle(color: _muted),
                        ),
                      ],
                    ),
                  ),
                )
              else if (items.isEmpty)
                  _stateMessage(
                    icon: allItems.isEmpty
                        ? Icons.inventory_2_outlined
                        : Icons.search_off_rounded,
                    title: allItems.isEmpty
                        ? 'Your inventory is empty'
                        : 'No matching items found',
                    message: allItems.isEmpty
                        ? 'Add your first stock item using the form.'
                        : 'No items match your keyword, category and low-stock '
                        'filters. Try changing them or press Clear Filters.',
                  )
                else
                  Column(
                    children: items.map(_itemCard).toList(),
                  ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildSummaryStats(List<StockItem> items) {
    final totalUnits = items.fold<int>(0, (sum, item) => sum + item.quantity);
    final lowStockCount =
        items.where((item) => item.quantity <= item.reorderLevel).length;
    final stockValue = items.fold<double>(
      0,
          (sum, item) => sum + item.quantity * item.unitPrice,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 760 ? 4 : 2;
        const spacing = 10.0;
        final cardWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            SizedBox(
              width: cardWidth,
              child: _statCard(
                'Total items',
                '${items.length}',
                Icons.inventory_2_outlined,
                const Color(0xFF087F73),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _statCard(
                'Total units',
                '$totalUnits',
                Icons.widgets_outlined,
                const Color(0xFF4777A8),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _statCard(
                'Low stock',
                '$lowStockCount',
                Icons.warning_amber_rounded,
                const Color(0xFFB7791F),
              ),
            ),
            SizedBox(
              width: cardWidth,
              child: _statCard(
                'Stock value',
                'RM ${stockValue.toStringAsFixed(2)}',
                Icons.payments_outlined,
                const Color(0xFF7661A8),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _statCard(
      String label,
      String value,
      IconData icon,
      Color accent,
      ) {
    return Container(
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEEE)),
      ),
      child: Row(
        children: [
          Container(
            width: 35,
            height: 35,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.10),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: accent, size: 18),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: _textDark,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _formatCreatedAt(DateTime value) {
    final local = value.toLocal();
    String twoDigits(int number) => number.toString().padLeft(2, '0');

    return '${local.year}-${twoDigits(local.month)}-${twoDigits(local.day)} '
        '${twoDigits(local.hour)}:${twoDigits(local.minute)}:${twoDigits(local.second)} '
        '(local time)';
  }

  Widget _itemCard(StockItem item) {
    final isLowStock = item.quantity <= item.reorderLevel;
    final statusColor =
    isLowStock ? const Color(0xFFB7791F) : const Color(0xFF23845D);
    final statusBackground =
    isLowStock ? const Color(0xFFFFF4DE) : const Color(0xFFE6F5ED);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(15),
        border: Border.all(color: const Color(0xFFE7ECEB)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 43,
                height: 43,
                decoration: BoxDecoration(
                  color: const Color(0xFFE8F4F1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.inventory_2_outlined,
                  color: _primary,
                  size: 21,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.itemName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: _textDark,
                        fontSize: 15,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.sku,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: statusBackground,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isLowStock
                          ? Icons.warning_amber_rounded
                          : Icons.check_circle_outline,
                      size: 14,
                      color: statusColor,
                    ),
                    const SizedBox(width: 5),
                    Text(
                      isLowStock ? 'LOW STOCK' : 'IN STOCK',
                      style: TextStyle(
                        color: statusColor,
                        fontSize: 9,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(height: 1, color: const Color(0xFFEEF1F1)),
          const SizedBox(height: 12),
          Wrap(
            spacing: 24,
            runSpacing: 10,
            children: [
              _itemMetric('CATEGORY', item.category),
              _itemMetric('QUANTITY', '${item.quantity} units'),
              _itemMetric(
                  'UNIT PRICE', 'RM ${item.unitPrice.toStringAsFixed(2)}'),
              _itemMetric('REORDER LEVEL', '${item.reorderLevel} units'),
            ],
          ),
          const SizedBox(height: 12),
          Container(height: 1, color: const Color(0xFFEEF1F1)),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(
                Icons.schedule_rounded,
                size: 15,
                color: _muted,
              ),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  item.createdAt == null
                      ? 'Created at: Timestamp not available'
                      : 'Created at: ${_formatCreatedAt(item.createdAt!)}',
                  style: const TextStyle(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _itemMetric(String label, String value) {
    return SizedBox(
      width: 125,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: const TextStyle(
              color: Color(0xFF84928F),
              fontSize: 9,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: _textDark,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _panel({required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(21),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2EAE8)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x080E403A),
            blurRadius: 22,
            offset: Offset(0, 7),
          ),
        ],
      ),
      child: child,
    );
  }

  Widget _panelTitle({
    required IconData icon,
    required String title,
    required String subtitle,
    Widget? trailing,
  }) {
    return Row(
      children: [
        Container(
          width: 39,
          height: 39,
          decoration: BoxDecoration(
            color: const Color(0xFFE8F4F1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, color: _primary, size: 20),
        ),
        const SizedBox(width: 11),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: _textDark,
                  fontSize: 17,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                subtitle,
                style: const TextStyle(color: _muted, fontSize: 12),
              ),
            ],
          ),
        ),
        if (trailing != null) trailing,
      ],
    );
  }

  Widget _fieldLabel(String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 7),
      child: Text(
        label,
        style: const TextStyle(
          color: Color(0xFF344946),
          fontSize: 12,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _stateMessage({
    required IconData icon,
    required String title,
    required String message,
    bool isError = false,
  }) {
    final accent = isError ? const Color(0xFFAD403A) : _primary;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 30),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFA),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFFE8EEEE)),
      ),
      child: Column(
        children: [
          Icon(icon, color: accent, size: 32),
          const SizedBox(height: 10),
          Text(
            title,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _textDark,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 5),
          Text(
            message,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: _muted,
              fontSize: 12,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

class StockItem {
  const StockItem({
    required this.id,
    required this.sku,
    required this.itemName,
    required this.category,
    required this.quantity,
    required this.unitPrice,
    required this.reorderLevel,
    required this.createdAt,
  });

  final String id;
  final String sku;
  final String itemName;
  final String category;
  final int quantity;
  final double unitPrice;
  final int reorderLevel;
  final DateTime? createdAt;

  factory StockItem.fromMap(String id, Map<String, dynamic> data) {
    int toInt(dynamic value) => value is num
        ? value.toInt()
        : int.tryParse(value?.toString() ?? '') ?? 0;
    double toDouble(dynamic value) => value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '') ?? 0.0;
    DateTime? toDateTime(dynamic value) {
      if (value is Timestamp) return value.toDate();
      if (value is DateTime) return value;
      return null;
    }

    return StockItem(
      id: id,
      sku: data['sku']?.toString() ?? '',
      itemName: data['itemName']?.toString() ?? '',
      category: data['category']?.toString() ?? '',
      quantity: toInt(data['quantity']),
      unitPrice: toDouble(data['unitPrice']),
      reorderLevel: toInt(data['reorderLevel']),
      createdAt: toDateTime(data['createdAt']),
    );
  }
}
