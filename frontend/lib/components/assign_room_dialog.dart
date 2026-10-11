import 'package:flutter/material.dart';
import '../services/api_service.dart';

// ─── Design tokens ──────────────────────────────────────────────────────────
const _dGreen = Color(0xFF8B9E3A);
const _dBorder = Color(0xFFD1D5DB);
const _dTextDark = Color(0xFF111827);
const _dTextMid = Color(0xFF374151);
const _dTextLight = Color(0xFF6B7280);
const _dHeaderBg = Color(0xFFF9FAFB);

// Frontend mock exam options. Backend also auto-assigns exams; these allow
// the doctor to preview / customise before confirming.
const _kAllExams = [
  'Complete Blood Count (CBC)',
  'Basic Metabolic Panel (BMP)',
  'Vital Signs Recheck',
  'C-Reactive Protein (CRP)',
  'Urinalysis',
  'Point-of-Care Glucose',
  'Chest X-Ray',
  'Pulse Oximetry Trend',
  'ECG',
  'Liver Function Panel',
  'Electrolytes Panel',
  'Physical Examination Follow-up',
];

// Default exams pre-selected when the dialog opens.
const _kDefaultExams = [
  'Complete Blood Count (CBC)',
  'Basic Metabolic Panel (BMP)',
  'Vital Signs Recheck',
];

typedef OnAssignNextStep =
    void Function(int roomId, List<String> selectedExams);

/// "Assign Next Step" dialog – lets a doctor pick an examination room
/// (searchable dropdown) and customise the required examinations.
class AssignRoomDialog extends StatefulWidget {
  final OnAssignNextStep onRoomAssigned;

  const AssignRoomDialog({Key? key, required this.onRoomAssigned})
    : super(key: key);

  @override
  State<AssignRoomDialog> createState() => _AssignRoomDialogState();
}

class _AssignRoomDialogState extends State<AssignRoomDialog> {
  // Rooms state
  List<RoomResponse> _allRooms = [];
  bool _loadingRooms = true;
  String? _roomsError;

  // Searchable dropdown
  final _searchCtrl = TextEditingController();
  String _roomQuery = '';
  bool _dropdownOpen = false;
  RoomResponse? _selectedRoom;

  // Exams state
  bool _examsExpanded = true;
  final Set<String> _checkedExams = Set.from(_kDefaultExams);

  @override
  void initState() {
    super.initState();
    _fetchRooms();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _fetchRooms() async {
    setState(() {
      _loadingRooms = true;
      _roomsError = null;
    });
    try {
      final rooms = await ApiService.getRooms(status: 'active');
      if (!mounted) return;
      setState(() {
        _allRooms = rooms;
        _loadingRooms = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _roomsError = 'Could not load rooms. Check connectivity.';
        _loadingRooms = false;
      });
    }
  }

  List<RoomResponse> get _filteredRooms {
    final q = _roomQuery.trim().toLowerCase();
    if (q.isEmpty) return _allRooms;
    return _allRooms
        .where(
          (r) =>
              r.roomName.toLowerCase().contains(q) ||
              r.roomType.toLowerCase().contains(q),
        )
        .toList();
  }

  void _pickRoom(RoomResponse room) {
    setState(() {
      _selectedRoom = room;
      _searchCtrl.text = '${room.roomName}  ·  ${room.roomType}';
      _roomQuery = '';
      _dropdownOpen = false;
    });
  }

  void _confirm() {
    if (_selectedRoom == null) return;
    widget.onRoomAssigned(_selectedRoom!.roomId, _checkedExams.toList());
    Navigator.pop(context);
  }

  // ── Build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _header(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _label('Assignment Type'),
                    const SizedBox(height: 8),
                    _assignmentTypeChip(),
                    const SizedBox(height: 22),
                    _label('Examination Room'),
                    const SizedBox(height: 8),
                    _roomDropdown(),
                    const SizedBox(height: 22),
                    _examsSection(),
                    const SizedBox(height: 8),
                  ],
                ),
              ),
            ),
            _footer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 14),
      decoration: const BoxDecoration(
        color: _dHeaderBg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(bottom: BorderSide(color: _dBorder)),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.assignment_turned_in_outlined,
            color: _dGreen,
            size: 20,
          ),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Assign Next Step',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.w700,
                color: _dTextDark,
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close, size: 18, color: _dTextLight),
            onPressed: () => Navigator.pop(context),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(),
          ),
        ],
      ),
    );
  }

  Widget _footer() {
    return Container(
      padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
      decoration: const BoxDecoration(
        color: _dHeaderBg,
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(10)),
        border: Border(top: BorderSide(color: _dBorder)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Cancel',
              style: TextStyle(color: _dTextMid, fontSize: 13),
            ),
          ),
          const SizedBox(width: 10),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor:
                  _selectedRoom != null ? _dGreen : Colors.grey[300],
              foregroundColor:
                  _selectedRoom != null ? Colors.white : _dTextLight,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              elevation: 0,
            ),
            onPressed: _selectedRoom != null ? _confirm : null,
            icon: const Icon(Icons.check, size: 15),
            label: const Text(
              'Confirm Assignment',
              style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }

  Widget _label(String text) {
    return Text(
      text.toUpperCase(),
      style: const TextStyle(
        fontSize: 11,
        fontWeight: FontWeight.w600,
        color: _dTextLight,
        letterSpacing: 0.5,
      ),
    );
  }

  Widget _assignmentTypeChip() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: _dGreen.withAlpha(20),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: _dGreen.withAlpha(90)),
      ),
      child: const Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, size: 15, color: _dGreen),
          SizedBox(width: 7),
          Text(
            'Examination',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: _dGreen,
            ),
          ),
        ],
      ),
    );
  }

  // ── Searchable room dropdown ─────────────────────────────────────────────

  Widget _roomDropdown() {
    if (_loadingRooms) {
      return Container(
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          border: Border.all(color: _dBorder),
          borderRadius: BorderRadius.circular(6),
        ),
        child: const SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2, color: _dGreen),
        ),
      );
    }
    if (_roomsError != null) {
      return Row(
        children: [
          Expanded(
            child: Text(
              _roomsError!,
              style: const TextStyle(color: Colors.red, fontSize: 12),
            ),
          ),
          TextButton.icon(
            onPressed: _fetchRooms,
            icon: const Icon(Icons.refresh, size: 14),
            label: const Text('Retry', style: TextStyle(fontSize: 12)),
          ),
        ],
      );
    }

    final filtered = _filteredRooms;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Text field
        TextField(
          controller: _searchCtrl,
          onTap: () => setState(() => _dropdownOpen = true),
          onChanged:
              (v) => setState(() {
                _roomQuery = v;
                _dropdownOpen = true;
                // Deselect room if user types something different
                if (_selectedRoom != null &&
                    '${_selectedRoom!.roomName}  ·  ${_selectedRoom!.roomType}' !=
                        v) {
                  _selectedRoom = null;
                }
              }),
          style: const TextStyle(fontSize: 13, color: _dTextDark),
          decoration: InputDecoration(
            hintText:
                _allRooms.isEmpty
                    ? 'No active rooms in your facility'
                    : 'Search by room name or type…',
            hintStyle: const TextStyle(fontSize: 13, color: _dTextLight),
            prefixIcon: const Icon(Icons.search, size: 16, color: _dTextLight),
            suffixIcon:
                _selectedRoom != null
                    ? const Icon(Icons.check_circle, size: 17, color: _dGreen)
                    : Icon(
                      _dropdownOpen
                          ? Icons.arrow_drop_up
                          : Icons.arrow_drop_down,
                      color: _dTextLight,
                    ),
            contentPadding: const EdgeInsets.symmetric(
              vertical: 10,
              horizontal: 4,
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: BorderSide(
                color: _selectedRoom != null ? _dGreen : _dBorder,
              ),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(6),
              borderSide: const BorderSide(color: _dGreen, width: 1.5),
            ),
          ),
        ),

        // Dropdown list
        if (_dropdownOpen)
          Container(
            constraints: const BoxConstraints(maxHeight: 200),
            margin: const EdgeInsets.only(top: 4),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: _dBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withAlpha(20),
                  blurRadius: 8,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child:
                filtered.isEmpty
                    ? Padding(
                      padding: const EdgeInsets.all(16),
                      child: Text(
                        _allRooms.isEmpty
                            ? 'No active rooms are available in your facility'
                            : 'No rooms match "${_roomQuery.trim()}"',
                        style: const TextStyle(
                          fontSize: 12,
                          color: _dTextLight,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    )
                    : ListView.separated(
                      shrinkWrap: true,
                      padding: EdgeInsets.zero,
                      itemCount: filtered.length,
                      separatorBuilder:
                          (_, __) => Divider(height: 1, color: _dBorder),
                      itemBuilder: (ctx, i) {
                        final room = filtered[i];
                        final sel = _selectedRoom?.roomId == room.roomId;
                        return InkWell(
                          onTap: () => _pickRoom(room),
                          child: Container(
                            color:
                                sel
                                    ? _dGreen.withAlpha(18)
                                    : Colors.transparent,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        room.roomName,
                                        style: TextStyle(
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                          color: sel ? _dGreen : _dTextDark,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        [
                                          room.roomType,
                                          if (room.floorNumber != null)
                                            'Floor ${room.floorNumber}',
                                          'Cap: ${room.capacity}',
                                        ].join(' · '),
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: _dTextLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (sel)
                                  const Icon(
                                    Icons.check,
                                    size: 15,
                                    color: _dGreen,
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
          ),
      ],
    );
  }

  // ── Exams section ────────────────────────────────────────────────────────

  Widget _examsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(4),
          onTap: () => setState(() => _examsExpanded = !_examsExpanded),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 2),
            child: Row(
              children: [
                const Text(
                  'REQUIRED EXAMINATIONS',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: _dTextLight,
                    letterSpacing: 0.5,
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: _dGreen.withAlpha(28),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${_checkedExams.length} / ${_kAllExams.length}',
                    style: const TextStyle(
                      fontSize: 10,
                      fontWeight: FontWeight.w700,
                      color: _dGreen,
                    ),
                  ),
                ),
                const Spacer(),
                Icon(
                  _examsExpanded
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  size: 18,
                  color: _dTextLight,
                ),
              ],
            ),
          ),
        ),
        if (_examsExpanded) ...[
          const SizedBox(height: 8),
          Container(
            decoration: BoxDecoration(
              border: Border.all(color: _dBorder),
              borderRadius: BorderRadius.circular(6),
            ),
            child: ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: _kAllExams.length,
              separatorBuilder: (_, __) => Divider(height: 1, color: _dBorder),
              itemBuilder: (_, i) {
                final exam = _kAllExams[i];
                final checked = _checkedExams.contains(exam);
                return InkWell(
                  onTap:
                      () => setState(() {
                        if (checked) {
                          _checkedExams.remove(exam);
                        } else {
                          _checkedExams.add(exam);
                        }
                      }),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 9,
                    ),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 18,
                          height: 18,
                          child: Checkbox(
                            value: checked,
                            onChanged:
                                (v) => setState(() {
                                  if (v == true) {
                                    _checkedExams.add(exam);
                                  } else {
                                    _checkedExams.remove(exam);
                                  }
                                }),
                            activeColor: _dGreen,
                            materialTapTargetSize:
                                MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            exam,
                            style: TextStyle(
                              fontSize: 13,
                              color: checked ? _dTextDark : _dTextLight,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}
