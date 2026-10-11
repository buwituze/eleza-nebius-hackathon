import 'dart:math' as math;

import 'package:flutter/material.dart';

class AdminUi {
  static const Color primaryText = Color(0xFF161616);
  static const Color mutedText = Color(0xFF76756F);
  static const Color placeholderText = Color(0xFF9A9992);
  static const Color chrome = Color(0xFF3C3B36);
  static const Color filterSurface = Colors.white;
  static const Color tableSurface = Colors.white;
  static const Color tableHeader = Color(0xFFF0EFE9);
  static const Color icon = Color(0xFF111111);
  static const Color viewAction = Color(0xFF1E3A5F);
  static const Color editAction = Color(0xFFB45309);
  static const Color deleteAction = Color(0xFF7F1D1D);
}

class AdminTableShell extends StatelessWidget {
  final double minWidth;
  final Widget child;

  const AdminTableShell({
    super.key,
    required this.minWidth,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AdminUi.tableSurface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AdminUi.chrome.withAlpha(120)),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final effectiveMinWidth = math.max(minWidth, constraints.maxWidth);
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: effectiveMinWidth),
                child: child,
              ),
            );
          },
        ),
      ),
    );
  }
}

class AdminSearchField extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;
  final String hintText;

  const AdminSearchField({
    super.key,
    required this.controller,
    required this.hintText,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AdminUi.filterSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminUi.chrome.withAlpha(165)),
      ),
      child: Row(
        children: [
          const SizedBox(width: 18),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: onChanged,
              style: const TextStyle(fontSize: 14, color: AdminUi.primaryText),
              decoration: const InputDecoration(
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
              ).copyWith(
                hintText: hintText,
                hintStyle: const TextStyle(
                  fontSize: 14,
                  color: AdminUi.placeholderText,
                ),
              ),
            ),
          ),
          const Padding(
            padding: EdgeInsets.only(right: 16),
            child: Icon(Icons.search, color: AdminUi.icon, size: 20),
          ),
        ],
      ),
    );
  }
}

class AdminDropdownFilter extends StatelessWidget {
  final String value;
  final List<String> items;
  final IconData icon;
  final ValueChanged<String?> onChanged;
  final String Function(String item)? itemLabel;
  final String Function(String item)? selectedLabelBuilder;

  const AdminDropdownFilter({
    super.key,
    required this.value,
    required this.items,
    required this.icon,
    required this.onChanged,
    this.itemLabel,
    this.selectedLabelBuilder,
  });

  @override
  Widget build(BuildContext context) {
    final safeValue = items.contains(value) ? value : items.first;
    return Container(
      height: 52,
      decoration: BoxDecoration(
        color: AdminUi.filterSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminUi.chrome.withAlpha(165)),
      ),
      child: DropdownButtonHideUnderline(
        child: ButtonTheme(
          alignedDropdown: true,
          child: DropdownButton<String>(
            value: safeValue,
            isExpanded: true,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            icon: Icon(icon, size: 18, color: AdminUi.icon),
            borderRadius: BorderRadius.circular(16),
            dropdownColor: Colors.white,
            selectedItemBuilder:
                (context) =>
                    items
                        .map(
                          (item) => Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              selectedLabelBuilder?.call(item) ??
                                  itemLabel?.call(item) ??
                                  item,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 14,
                                color: AdminUi.primaryText,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        )
                        .toList(),
            items:
                items
                    .map(
                      (item) => DropdownMenuItem<String>(
                        value: item,
                        child: Text(
                          itemLabel?.call(item) ?? item,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AdminUi.primaryText,
                          ),
                        ),
                      ),
                    )
                    .toList(),
            onChanged: onChanged,
          ),
        ),
      ),
    );
  }
}

class AdminDateRangeFilter extends StatelessWidget {
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<DateTime?> onFromDateChanged;
  final ValueChanged<DateTime?> onToDateChanged;
  final bool enabled;
  final String unavailableLabel;

  const AdminDateRangeFilter({
    super.key,
    required this.fromDate,
    required this.toDate,
    required this.onFromDateChanged,
    required this.onToDateChanged,
    this.enabled = true,
    this.unavailableLabel = 'Created date unavailable',
  });

  static String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    const months = [
      'Jan',
      'Feb',
      'Mar',
      'Apr',
      'May',
      'Jun',
      'Jul',
      'Aug',
      'Sep',
      'Oct',
      'Nov',
      'Dec',
    ];
    return '${date.day.toString().padLeft(2, '0')} ${months[date.month - 1]} ${date.year}';
  }

  Future<void> _pickDate(BuildContext context, bool isFrom) async {
    if (!enabled) return;

    final currentValue = isFrom ? fromDate : toDate;
    final picked = await showDatePicker(
      context: context,
      initialDate: currentValue ?? DateTime.now(),
      firstDate: DateTime(2020),
      lastDate: DateTime(2035),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF8B9E3A),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: AdminUi.primaryText,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked == null) return;
    if (isFrom) {
      onFromDateChanged(picked);
    } else {
      onToDateChanged(picked);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = fromDate != null || toDate != null;
    final content = Container(
      height: 52,
      decoration: BoxDecoration(
        color: AdminUi.filterSurface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AdminUi.chrome.withAlpha(165)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: 18,
              color: AdminUi.icon,
            ),
            const SizedBox(width: 10),
            Expanded(
              child:
                  enabled
                      ? Row(
                        children: [
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickDate(context, true),
                              borderRadius: BorderRadius.circular(10),
                              child: Text(
                                'From ${_formatDate(fromDate)}',
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      fromDate == null
                                          ? AdminUi.placeholderText
                                          : AdminUi.primaryText,
                                  fontWeight:
                                      fromDate == null
                                          ? FontWeight.w400
                                          : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          const Text(
                            'to',
                            style: TextStyle(
                              fontSize: 13,
                              color: AdminUi.mutedText,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: InkWell(
                              onTap: () => _pickDate(context, false),
                              borderRadius: BorderRadius.circular(10),
                              child: Text(
                                _formatDate(toDate),
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13,
                                  color:
                                      toDate == null
                                          ? AdminUi.placeholderText
                                          : AdminUi.primaryText,
                                  fontWeight:
                                      toDate == null
                                          ? FontWeight.w400
                                          : FontWeight.w500,
                                ),
                              ),
                            ),
                          ),
                        ],
                      )
                      : Text(
                        unavailableLabel,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 13,
                          color: AdminUi.placeholderText,
                        ),
                      ),
            ),
            if (enabled && hasSelection)
              InkWell(
                onTap: () {
                  onFromDateChanged(null);
                  onToDateChanged(null);
                },
                borderRadius: BorderRadius.circular(999),
                child: const Padding(
                  padding: EdgeInsets.all(4),
                  child: Icon(Icons.close, size: 16, color: AdminUi.icon),
                ),
              ),
          ],
        ),
      ),
    );

    if (enabled) return content;
    return Tooltip(
      message: unavailableLabel,
      child: Opacity(opacity: 0.76, child: content),
    );
  }
}

class AdminActionIconButton extends StatelessWidget {
  final String tooltip;
  final IconData icon;
  final Color backgroundColor;
  final VoidCallback? onTap;

  const AdminActionIconButton({
    super.key,
    required this.tooltip,
    required this.icon,
    required this.backgroundColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      preferBelow: false,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        ),
      ),
    );
  }
}
