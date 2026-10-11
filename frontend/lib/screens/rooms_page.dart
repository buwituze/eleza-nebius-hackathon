import 'package:flutter/material.dart';

import '../components/admin_sidebar.dart';
import '../components/admin_ui.dart';
import '../components/app_navbar.dart';
import '../services/api_service.dart';
import 'all_patients.dart';
import 'patient_detail_page.dart';

class RoomsPage extends StatefulWidget {
  final String userRole;
  final String userName;
  final String? userSpecialty;

  const RoomsPage({
    Key? key,
    this.userRole = 'platform_admin',
    this.userName = '',
    this.userSpecialty,
  }) : super(key: key);

  @override
  State<RoomsPage> createState() => _RoomsPageState();
}

class _RoomRow {
  final RoomResponse room;
  final String facilityName;

  const _RoomRow({required this.room, required this.facilityName});
}

class _RoomsPageState extends State<RoomsPage> {
  static const Color _primaryGreen = Color(0xFF8B9E3A);
  static const Color _accentGold = Color(0xFFB8860B);

  final TextEditingController _searchController = TextEditingController();

  List<_RoomRow> _allRows = [];
  Map<int, String> _facilityMapById = {};
  bool _isLoading = true;
  bool _isRefreshing = false;
  String? _errorMessage;
  String _effectiveUserRole = '';
  String _effectiveUserName = '';
  String? _effectiveUserSpecialty;

  String _searchQuery = '';
  String _statusFilter = 'All';
  String _facilityFilter = 'All';

  static const List<String> _statusOptions = [
    'All',
    'active',
    'inactive',
    'maintenance',
  ];

  String _normalizeRole(String value) {
    return value.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  }

  String get _normalizedEffectiveUserRole {
    final role =
        _effectiveUserRole.trim().isEmpty
            ? widget.userRole
            : _effectiveUserRole;
    return _normalizeRole(role);
  }

  bool get _isDoctorView => _normalizedEffectiveUserRole == 'doctor';
  bool get _canToggleRoomStatus =>
      _normalizedEffectiveUserRole == 'hospital_admin';

  @override
  void initState() {
    super.initState();
    _fetch(showLoader: true);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetch({required bool showLoader}) async {
    if (showLoader) {
      setState(() {
        _isLoading = true;
        _errorMessage = null;
      });
    } else {
      setState(() {
        _isRefreshing = true;
        _errorMessage = null;
      });
    }

    try {
      final facilities = await ApiService.getFacilities();
      final facilityMap = <int, String>{
        for (final facility in facilities) facility.facilityId: facility.name,
      };

      final rows = <_RoomRow>[];

      // Use stored role as the authoritative source; fall back to widget prop.
      final storedUserInfo = await ApiService.getUserInfo();
      final resolvedRole =
          (storedUserInfo?['role'] as String? ?? widget.userRole).trim();
      final effectiveRole = _normalizeRole(resolvedRole);
      final resolvedName =
          (storedUserInfo?['full_name'] as String? ?? widget.userName).trim();
      final resolvedSpecialty =
          (storedUserInfo?['specialty'] as String? ?? widget.userSpecialty)
              ?.trim();
      final storedFacilityId = storedUserInfo?['facility_id'];
      final hasStoredNullFacility =
          storedUserInfo != null &&
          storedUserInfo.containsKey('facility_id') &&
          storedFacilityId == null;
      final isPlatformLikeUser =
          effectiveRole == 'platform_admin' || hasStoredNullFacility;

      if (isPlatformLikeUser) {
        for (final facility in facilities) {
          try {
            final rooms = await ApiService.getRooms(
              facilityId: facility.facilityId,
            );
            rows.addAll(
              rooms.map(
                (room) => _RoomRow(room: room, facilityName: facility.name),
              ),
            );
          } catch (_) {
            // Continue with other facilities even if one request fails.
          }
        }
      } else {
        List<RoomResponse> rooms;
        try {
          rooms = await ApiService.getRooms();
        } catch (e) {
          // Some sessions may carry a platform token but a mismatched role string.
          // If backend returns 400 for bare /rooms, fall back to facility-scoped pulls.
          final errorText = e.toString();
          if (errorText.contains('400') && facilities.isNotEmpty) {
            final fallbackRows = <_RoomRow>[];
            for (final facility in facilities) {
              try {
                final scopedRooms = await ApiService.getRooms(
                  facilityId: facility.facilityId,
                );
                fallbackRows.addAll(
                  scopedRooms.map(
                    (room) => _RoomRow(room: room, facilityName: facility.name),
                  ),
                );
              } catch (_) {
                // Continue loading from other facilities.
              }
            }
            if (!mounted) return;
            setState(() {
              _allRows = fallbackRows;
              _facilityMapById = facilityMap;
            });
            return;
          }
          rethrow;
        }
        rows.addAll(
          rooms.map(
            (room) => _RoomRow(
              room: room,
              facilityName:
                  facilityMap[room.facilityId] ??
                  'Facility #${room.facilityId}',
            ),
          ),
        );
      }

      if (!mounted) return;
      setState(() {
        _allRows = rows;
        _facilityMapById = facilityMap;
        _effectiveUserRole = resolvedRole;
        _effectiveUserName = resolvedName;
        _effectiveUserSpecialty =
            resolvedSpecialty != null && resolvedSpecialty.isNotEmpty
                ? resolvedSpecialty
                : widget.userSpecialty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage =
            'Failed to load rooms. Check connectivity and access permissions.';
      });
    } finally {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _isRefreshing = false;
      });
    }
  }

  List<String> get _facilityOptions {
    final values =
        _allRows.map((row) => row.facilityName).toSet().toList()..sort();
    return ['All', ...values];
  }

  List<_RoomRow> get _filtered {
    return _allRows.where((row) {
      final room = row.room;

      if (_statusFilter != 'All' &&
          room.status.toLowerCase() != _statusFilter) {
        return false;
      }

      if (_facilityFilter != 'All' && row.facilityName != _facilityFilter) {
        return false;
      }

      if (_searchQuery.trim().isNotEmpty) {
        final query = _searchQuery.trim().toLowerCase();
        final matches =
            room.roomName.toLowerCase().contains(query) ||
            room.roomType.toLowerCase().contains(query) ||
            row.facilityName.toLowerCase().contains(query) ||
            room.status.toLowerCase().contains(query);
        if (!matches) return false;
      }

      return true;
    }).toList();
  }

  String _statusLabel(String value) {
    final normalized = value.trim().toLowerCase();
    if (normalized.isEmpty) return 'Unknown';
    return normalized[0].toUpperCase() + normalized.substring(1);
  }

  String _statusFilterLabel(String value) {
    return value == 'All' ? 'Filter' : 'Filter ${_statusLabel(value)}';
  }

  String _facilityFilterLabel(String value) {
    return value == 'All' ? 'Filter' : 'Filter $value';
  }

  void _onSidebarMenuSelected(String item) {
    if (item == 'Rooms') return;

    final routeRole =
        _effectiveUserRole.trim().isEmpty
            ? widget.userRole
            : _effectiveUserRole;
    final routeName =
        _effectiveUserName.trim().isEmpty
            ? widget.userName
            : _effectiveUserName;

    switch (item) {
      case 'Users':
        Navigator.of(context).pushReplacementNamed(
          '/admin-users',
          arguments: {'userRole': routeRole, 'userName': routeName},
        );
        break;
      case 'Facilities':
        Navigator.of(context).pushReplacementNamed(
          '/facilities',
          arguments: {'userRole': routeRole, 'userName': routeName},
        );
        break;
      case 'Doctors':
        Navigator.of(context).pushReplacementNamed(
          '/all-doctors',
          arguments: {'userRole': routeRole, 'userName': routeName},
        );
        break;
    }
  }

  Future<void> _showAddRoomDialog() async {
    if (_isDoctorView) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final typeCtrl = TextEditingController();
    final floorCtrl = TextEditingController();
    final capacityCtrl = TextEditingController(text: '1');

    int? selectedFacilityId;
    if (_allRows.isNotEmpty) {
      selectedFacilityId = _allRows.first.room.facilityId;
    } else if (_facilityMapById.isNotEmpty) {
      selectedFacilityId = _facilityMapById.keys.first;
    }

    bool submitting = false;
    String? modalError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text(
                'Add Room',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (modalError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            modalError!,
                            style: const TextStyle(color: _accentGold),
                          ),
                        ),
                      _field(nameCtrl, 'Room Name', validator: _required),
                      const SizedBox(height: 10),
                      _field(typeCtrl, 'Room Type', validator: _required),
                      const SizedBox(height: 10),
                      _field(
                        floorCtrl,
                        'Floor (optional)',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        capacityCtrl,
                        'Capacity',
                        keyboardType: TextInputType.number,
                        validator: _required,
                      ),
                      const SizedBox(height: 10),
                      DropdownButtonFormField<int>(
                        value: selectedFacilityId,
                        decoration: _inputDecoration('Facility'),
                        items:
                            _facilityMapById.entries
                                .map(
                                  (entry) => DropdownMenuItem<int>(
                                    value: entry.key,
                                    child: Text(entry.value),
                                  ),
                                )
                                .toList(),
                        onChanged:
                            _normalizedEffectiveUserRole == 'hospital_admin'
                                ? null
                                : (value) => setModalState(
                                  () => selectedFacilityId = value,
                                ),
                        validator: (value) {
                          if (value == null) return 'Facility is required.';
                          return null;
                        },
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(foregroundColor: _primaryGreen),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      submitting
                          ? null
                          : () async {
                            if (!formKey.currentState!.validate()) return;
                            final facilityId = selectedFacilityId;
                            if (facilityId == null) return;

                            setModalState(() {
                              submitting = true;
                              modalError = null;
                            });

                            try {
                              final floor =
                                  floorCtrl.text.trim().isEmpty
                                      ? null
                                      : int.parse(floorCtrl.text.trim());
                              final capacity = int.parse(
                                capacityCtrl.text.trim(),
                              );

                              final message =
                                  await ApiService.requestRoomCreate(
                                    facilityId: facilityId,
                                    roomName: nameCtrl.text.trim(),
                                    roomType: typeCtrl.text.trim(),
                                    floorNumber: floor,
                                    capacity: capacity,
                                  );

                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              _fetch(showLoader: false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: _primaryGreen,
                                ),
                              );
                            } catch (e) {
                              setModalState(() {
                                submitting = false;
                                modalError = e.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                );
                              });
                            }
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.black,
                  ),
                  child:
                      submitting
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _showEditRoomDialog(_RoomRow row) async {
    if (_isDoctorView) return;

    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: row.room.roomName);
    final typeCtrl = TextEditingController(text: row.room.roomType);
    final floorCtrl = TextEditingController(
      text: row.room.floorNumber?.toString() ?? '',
    );
    final capacityCtrl = TextEditingController(
      text: row.room.capacity.toString(),
    );

    bool submitting = false;
    String? modalError;

    await showDialog<void>(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (ctx, setModalState) {
            return AlertDialog(
              backgroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              title: const Text(
                'Edit Room',
                style: TextStyle(
                  color: Colors.black,
                  fontWeight: FontWeight.w700,
                ),
              ),
              content: SizedBox(
                width: 520,
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (modalError != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: Text(
                            modalError!,
                            style: const TextStyle(color: _accentGold),
                          ),
                        ),
                      _field(nameCtrl, 'Room Name', validator: _required),
                      const SizedBox(height: 10),
                      _field(typeCtrl, 'Room Type', validator: _required),
                      const SizedBox(height: 10),
                      _field(
                        floorCtrl,
                        'Floor (optional)',
                        keyboardType: TextInputType.number,
                      ),
                      const SizedBox(height: 10),
                      _field(
                        capacityCtrl,
                        'Capacity',
                        keyboardType: TextInputType.number,
                        validator: _required,
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: submitting ? null : () => Navigator.of(ctx).pop(),
                  style: TextButton.styleFrom(foregroundColor: _primaryGreen),
                  child: const Text('Cancel'),
                ),
                ElevatedButton(
                  onPressed:
                      submitting
                          ? null
                          : () async {
                            if (!formKey.currentState!.validate()) return;
                            setModalState(() {
                              submitting = true;
                              modalError = null;
                            });
                            try {
                              final updates = <String, dynamic>{
                                'room_name': nameCtrl.text.trim(),
                                'room_type': typeCtrl.text.trim(),
                                'capacity': int.parse(capacityCtrl.text.trim()),
                              };
                              if (floorCtrl.text.trim().isEmpty) {
                                updates['floor_number'] = null;
                              } else {
                                updates['floor_number'] = int.parse(
                                  floorCtrl.text.trim(),
                                );
                              }

                              final message =
                                  await ApiService.requestRoomUpdate(
                                    row.room.roomId,
                                    updates,
                                  );

                              if (!mounted) return;
                              Navigator.of(ctx).pop();
                              _fetch(showLoader: false);
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text(message),
                                  backgroundColor: _primaryGreen,
                                ),
                              );
                            } catch (e) {
                              setModalState(() {
                                submitting = false;
                                modalError = e.toString().replaceFirst(
                                  'Exception: ',
                                  '',
                                );
                              });
                            }
                          },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _primaryGreen,
                    foregroundColor: Colors.black,
                  ),
                  child:
                      submitting
                          ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                          : const Text('Submit'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _deleteRoom(_RoomRow row) async {
    if (_isDoctorView) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (ctx) => AlertDialog(
            backgroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            title: const Text('Delete Room'),
            content: Text('Delete ${row.room.roomName}?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(false),
                style: TextButton.styleFrom(foregroundColor: _primaryGreen),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _primaryGreen,
                  foregroundColor: Colors.black,
                ),
                child: const Text('Confirm'),
              ),
            ],
          ),
    );

    if (confirmed != true) return;

    try {
      final message = await ApiService.requestRoomDelete(row.room.roomId);
      if (!mounted) return;
      _fetch(showLoader: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message), backgroundColor: _primaryGreen),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _accentGold,
        ),
      );
    }
  }

  Future<void> _toggleRoomStatus(_RoomRow row) async {
    if (_isDoctorView) return;

    final current = row.room.status.toLowerCase();
    final target = current == 'active' ? 'inactive' : 'active';

    try {
      await ApiService.updateRoomStatus(
        roomId: row.room.roomId,
        status: target,
      );
      if (!mounted) return;
      _fetch(showLoader: false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Room marked ${_statusLabel(target)}.'),
          backgroundColor: _primaryGreen,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(e.toString().replaceFirst('Exception: ', '')),
          backgroundColor: _accentGold,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final rows = _filtered;

    final content = Column(
      children: [
        AppNavBar(
          currentUserName:
              _effectiveUserName.trim().isEmpty
                  ? widget.userName
                  : _effectiveUserName,
          currentUserRole:
              _effectiveUserRole.trim().isEmpty
                  ? widget.userRole
                  : _effectiveUserRole,
          currentUserSpecialty: _effectiveUserSpecialty ?? widget.userSpecialty,
          navItems:
              _isDoctorView
                  ? [
                    NavBarItem(
                      label: 'All Patients',
                      onTap: () => _goToAllPatients(),
                    ),
                    NavBarItem(label: 'Rooms', onTap: () {}),
                  ]
                  : const [],
          activeItem: 'Rooms',
          onSettingsTap: () {},
          onPatientTap: (id) {
            final role = _effectiveUserRole.trim().isEmpty
                ? widget.userRole
                : _effectiveUserRole;
            final name = _effectiveUserName.trim().isEmpty
                ? widget.userName
                : _effectiveUserName;
            Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => PatientDetailPage(
                  userRole: role,
                  userName: name,
                  userSpecialty: _effectiveUserSpecialty ?? widget.userSpecialty,
                  initialPatientId: id,
                ),
              ),
            );
          },
        ),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 26),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Rooms',
                            style: TextStyle(
                              fontSize: 28,
                              fontWeight: FontWeight.w700,
                              color: Colors.black,
                            ),
                          ),
                          SizedBox(height: 6),
                          Text(
                            'All rooms with the hospital that owns each room.',
                            style: TextStyle(fontSize: 14, color: Colors.black),
                          ),
                        ],
                      ),
                    ),
                    OutlinedButton.icon(
                      onPressed:
                          _isLoading ? null : () => _fetch(showLoader: false),
                      icon: const Icon(Icons.refresh, size: 18),
                      label: const Text('Refresh'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _primaryGreen,
                        side: const BorderSide(color: _primaryGreen),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    if (!_isDoctorView)
                      ElevatedButton.icon(
                        onPressed: _showAddRoomDialog,
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Add Room'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _primaryGreen,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 12,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 20),
                _filterBar(),
                if (_isRefreshing)
                  const Padding(
                    padding: EdgeInsets.only(top: 10),
                    child: LinearProgressIndicator(
                      minHeight: 2,
                      color: _primaryGreen,
                    ),
                  ),
                const SizedBox(height: 20),
                if (_isLoading)
                  _loadingState()
                else if (_errorMessage != null)
                  _errorState()
                else
                  _table(rows),
              ],
            ),
          ),
        ),
      ],
    );

    return Scaffold(
      backgroundColor: Colors.white,
      body:
          _isDoctorView
              ? content
              : Row(
                children: [
                  AdminSidebar(
                    activeItem: 'Rooms',
                    onItemSelected: _onSidebarMenuSelected,
                  ),
                  Expanded(child: content),
                ],
              ),
    );
  }

  void _goToAllPatients() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (_) => const AllPatientsPage()),
    );
  }

  Widget _filterBar() {
    return Row(
      children: [
        Expanded(
          flex: 4,
          child: AdminSearchField(
            controller: _searchController,
            hintText: 'Search rooms or hospitals...',
            onChanged: (value) => setState(() => _searchQuery = value),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 2,
          child: _dropdownFilter(
            value: _statusFilter,
            icon: Icons.filter_alt_outlined,
            items: _statusOptions,
            itemLabel: _statusLabel,
            selectedLabelBuilder: _statusFilterLabel,
            onChanged: (value) {
              if (value != null) setState(() => _statusFilter = value);
            },
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          flex: 3,
          child: _dropdownFilter(
            value: _facilityFilter,
            icon: Icons.local_hospital_outlined,
            items: _facilityOptions,
            selectedLabelBuilder: _facilityFilterLabel,
            onChanged: (value) {
              if (value != null) setState(() => _facilityFilter = value);
            },
          ),
        ),
      ],
    );
  }

  Widget _dropdownFilter({
    required String value,
    required IconData icon,
    required List<String> items,
    required ValueChanged<String?> onChanged,
    String Function(String item)? itemLabel,
    String Function(String item)? selectedLabelBuilder,
  }) {
    return AdminDropdownFilter(
      value: value,
      items: items,
      icon: icon,
      onChanged: onChanged,
      itemLabel: itemLabel,
      selectedLabelBuilder: selectedLabelBuilder,
    );
  }

  Widget _loadingState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 70),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: const Center(
        child: CircularProgressIndicator(
          valueColor: AlwaysStoppedAnimation<Color>(_primaryGreen),
        ),
      ),
    );
  }

  Widget _errorState() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 42, horizontal: 24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey[200]!, width: 1),
      ),
      child: Column(
        children: [
          const Icon(Icons.error_outline, size: 42, color: _accentGold),
          const SizedBox(height: 12),
          Text(
            _errorMessage ?? 'Something went wrong.',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: Colors.black),
          ),
          const SizedBox(height: 16),
          ElevatedButton(
            onPressed: () => _fetch(showLoader: true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _primaryGreen,
              foregroundColor: Colors.black,
            ),
            child: const Text('Retry'),
          ),
        ],
      ),
    );
  }

  String _fmtDate(DateTime? dt) {
    if (dt == null) return '—';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${dt.day} ${months[dt.month - 1]} ${dt.year}';
  }

  Widget _table(List<_RoomRow> rows) {
    final actionLabel = _isDoctorView ? 'Access' : 'Action';

    return AdminTableShell(
      minWidth: 1360,
      child: Table(
        columnWidths: const {
          0: FlexColumnWidth(2.2),
          1: FlexColumnWidth(1.6),
          2: FlexColumnWidth(2.4),
          3: FlexColumnWidth(1.1),
          4: FlexColumnWidth(1.1),
          5: FlexColumnWidth(1.5),
          6: FlexColumnWidth(1.3),
          7: FlexColumnWidth(2.0),
        },
        border: TableBorder(
          horizontalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(40),
            width: 1,
          ),
          verticalInside: BorderSide(
            color: AdminUi.chrome.withAlpha(24),
            width: 1,
          ),
        ),
        children: [
          TableRow(
            decoration: const BoxDecoration(color: AdminUi.tableHeader),
            children: [
              const _HeaderCell('Room'),
              const _HeaderCell('Type'),
              const _HeaderCell('Hospital'),
              const _HeaderCell('Floor'),
              const _HeaderCell('Capacity'),
              const _HeaderCell('Added On'),
              const _HeaderCell('Status'),
              _HeaderCell(actionLabel),
            ],
          ),
          ...rows.map(
            (row) => TableRow(
              children: [
                _dataCell(row.room.roomName, fontWeight: FontWeight.w600),
                _dataCell(row.room.roomType),
                _dataCell(row.facilityName),
                _dataCell(row.room.floorNumber?.toString() ?? '—'),
                _dataCell(row.room.capacity.toString()),
                _dataCell(_fmtDate(row.room.createdAt)),
                _statusBadge(row.room.status),
                _actionCell(row),
              ],
            ),
          ),
          if (rows.isEmpty)
            TableRow(
              children: List.generate(
                8,
                (index) =>
                    index == 2
                        ? _dataCell(
                          'No rooms found for the current filters.',
                          align: TextAlign.center,
                        )
                        : _dataCell(''),
              ),
            ),
        ],
      ),
    );
  }

  Widget _dataCell(
    String text, {
    TextAlign align = TextAlign.start,
    FontWeight fontWeight = FontWeight.w500,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      child: Text(
        text,
        textAlign: align,
        style: TextStyle(
          fontSize: 13,
          color: AdminUi.primaryText,
          fontWeight: fontWeight,
        ),
      ),
    );
  }

  Widget _statusBadge(String status) {
    final isActive = status.toLowerCase() == 'active';
    final color = isActive ? _primaryGreen : _accentGold;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: color.withAlpha(22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Text(
          _statusLabel(status),
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ),
    );
  }

  Widget _actionCell(_RoomRow row) {
    if (_isDoctorView) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Text(
          'View only',
          style: TextStyle(
            fontSize: 13,
            color: AdminUi.primaryText,
            fontWeight: FontWeight.w600,
          ),
        ),
      );
    }

    final canToggle = _canToggleRoomStatus;
    final currentStatus = row.room.status.toLowerCase();
    final toggleLabel =
        currentStatus == 'active' ? 'Set Inactive' : 'Set Active';

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          AdminActionIconButton(
            tooltip: 'Edit',
            icon: Icons.edit_outlined,
            backgroundColor: AdminUi.editAction,
            onTap: () => _showEditRoomDialog(row),
          ),
          AdminActionIconButton(
            tooltip: 'Delete',
            icon: Icons.delete_outline,
            backgroundColor: AdminUi.deleteAction,
            onTap: () => _deleteRoom(row),
          ),
          if (canToggle)
            TextButton(
              onPressed: () => _toggleRoomStatus(row),
              style: TextButton.styleFrom(
                foregroundColor: _primaryGreen,
                backgroundColor: _primaryGreen.withAlpha(18),
                textStyle: const TextStyle(fontWeight: FontWeight.w700),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 10,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                  side: BorderSide(color: _primaryGreen.withAlpha(120)),
                ),
              ),
              child: Text(toggleLabel),
            ),
        ],
      ),
    );
  }

  static String? _required(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }

  static InputDecoration _inputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primaryGreen),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: _primaryGreen, width: 1.4),
      ),
      fillColor: Colors.white,
      filled: true,
      labelStyle: const TextStyle(color: Colors.black),
    );
  }

  static Widget _field(
    TextEditingController controller,
    String label, {
    TextInputType? keyboardType,
    bool obscureText = false,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      obscureText: obscureText,
      validator: validator,
      decoration: _inputDecoration(label),
    );
  }
}

class _HeaderCell extends StatelessWidget {
  final String label;

  const _HeaderCell(this.label);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Text(
        label,
        style: const TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: AdminUi.primaryText,
        ),
      ),
    );
  }
}
