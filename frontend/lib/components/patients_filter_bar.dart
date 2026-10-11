import 'package:flutter/material.dart';

class PatientsFilterBar extends StatefulWidget {
  final TextEditingController? searchController;
  final ValueChanged<String>? onSearchChanged;
  final String? selectedFilter;
  final List<String> filterOptions;
  final ValueChanged<String?>? onFilterChanged;
  final DateTime? fromDate;
  final DateTime? toDate;
  final ValueChanged<DateTime?>? onFromDateChanged;
  final ValueChanged<DateTime?>? onToDateChanged;

  const PatientsFilterBar({
    Key? key,
    this.searchController,
    this.onSearchChanged,
    this.selectedFilter,
    this.filterOptions = const [],
    this.onFilterChanged,
    this.fromDate,
    this.toDate,
    this.onFromDateChanged,
    this.onToDateChanged,
  }) : super(key: key);

  @override
  State<PatientsFilterBar> createState() => _PatientsFilterBarState();
}

class _PatientsFilterBarState extends State<PatientsFilterBar> {
  late TextEditingController _searchController;
  DateTime? _fromDate;
  DateTime? _toDate;

  @override
  void initState() {
    super.initState();
    _searchController = widget.searchController ?? TextEditingController();
    _fromDate = widget.fromDate;
    _toDate = widget.toDate;
  }

  @override
  void didUpdateWidget(covariant PatientsFilterBar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.fromDate != widget.fromDate) {
      _fromDate = widget.fromDate;
    }
    if (oldWidget.toDate != widget.toDate) {
      _toDate = widget.toDate;
    }
  }

  @override
  void dispose() {
    if (widget.searchController == null) {
      _searchController.dispose();
    }
    super.dispose();
  }

  String _formatDate(DateTime? date) {
    if (date == null) return 'Select date';
    final months = [
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
    final initial =
        isFrom ? (_fromDate ?? DateTime.now()) : (_toDate ?? DateTime.now());

    final picked = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: DateTime(2020),
      lastDate: DateTime(2030),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: Color(0xFF8B9E3A),
              onPrimary: Colors.white,
              surface: Colors.white,
              onSurface: Colors.black87,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        if (isFrom) {
          _fromDate = picked;
          widget.onFromDateChanged?.call(picked);
        } else {
          _toDate = picked;
          widget.onToDateChanged?.call(picked);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Search field
        Expanded(
          flex: 4,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: Row(
              children: [
                const SizedBox(width: 20),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: widget.onSearchChanged,
                    style: const TextStyle(fontSize: 14, color: Colors.black87),
                    decoration: InputDecoration(
                      hintText: 'Search All Patients Table...',
                      hintStyle: TextStyle(
                        fontSize: 14,
                        color: Colors.grey[400],
                      ),
                      border: InputBorder.none,
                      isDense: true,
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Icon(Icons.search, color: Colors.grey[600], size: 22),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Filter dropdown
        Expanded(
          flex: 2,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: DropdownButtonHideUnderline(
              child: ButtonTheme(
                alignedDropdown: true,
                child: DropdownButton<String>(
                  value: widget.selectedFilter,
                  hint: Text(
                    'Filter',
                    style: TextStyle(fontSize: 14, color: Colors.grey[500]),
                  ),
                  icon: Icon(
                    Icons.filter_alt_outlined,
                    color: Colors.grey[600],
                    size: 20,
                  ),
                  isExpanded: true,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  items:
                      widget.filterOptions.map((option) {
                        return DropdownMenuItem<String>(
                          value: option,
                          child: Text(
                            option,
                            style: const TextStyle(fontSize: 14),
                          ),
                        );
                      }).toList(),
                  onChanged: widget.onFilterChanged,
                ),
              ),
            ),
          ),
        ),
        const SizedBox(width: 16),

        // Date range picker
        Expanded(
          flex: 5,
          child: Container(
            height: 52,
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.grey[300]!, width: 1),
            ),
            child: Row(
              children: [
                const SizedBox(width: 16),
                Text(
                  'From',
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                    fontWeight: FontWeight.w400,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(context, true),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatDate(_fromDate),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Text(
                    'to',
                    style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                  ),
                ),
                Expanded(
                  child: GestureDetector(
                    onTap: () => _pickDate(context, false),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            _formatDate(_toDate),
                            style: const TextStyle(
                              fontSize: 13,
                              color: Colors.black87,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.calendar_today_outlined,
                          size: 18,
                          color: Colors.grey[600],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 16),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
