import 'dart:async';
import 'package:flutter/material.dart';
import '../services/api_service.dart';

class AppNavBar extends StatefulWidget {
  final String? currentUserName;
  final String? currentUserRole;
  final String? currentUserSpecialty;
  final VoidCallback? onSettingsTap;
  final VoidCallback? onLogout;
  final List<NavBarItem> navItems;
  final String? activeItem;
  final void Function(int patientId)? onPatientTap;

  const AppNavBar({
    Key? key,
    this.currentUserName,
    this.currentUserRole,
    this.currentUserSpecialty,
    this.onSettingsTap,
    this.onLogout,
    this.navItems = const [],
    this.activeItem,
    this.onPatientTap,
  }) : super(key: key);

  @override
  State<AppNavBar> createState() => _AppNavBarState();
}

class _AppNavBarState extends State<AppNavBar> {
  String? _storedName;
  String? _storedRole;

  final TextEditingController _searchCtrl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final LayerLink _layerLink = LayerLink();
  OverlayEntry? _overlayEntry;
  Timer? _debounce;
  List<PatientListItem> _searchResults = [];
  bool _isSearching = false;

  @override
  void initState() {
    super.initState();
    _loadStoredUser();
    _searchFocus.addListener(_onFocusChange);
  }

  void _onFocusChange() {
    if (!_searchFocus.hasFocus) {
      Future.delayed(const Duration(milliseconds: 150), _removeOverlay);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _searchFocus.removeListener(_onFocusChange);
    _searchFocus.dispose();
    _removeOverlay();
    super.dispose();
  }

  Future<void> _loadStoredUser() async {
    final info = await ApiService.getUserInfo();
    if (!mounted || info == null) return;
    setState(() {
      _storedName = info['full_name'] as String?;
      _storedRole = info['role'] as String?;
    });
  }

  String get _effectiveName {
    final passed = widget.currentUserName?.trim() ?? '';
    if (passed.isNotEmpty) return passed;
    return _storedName?.trim() ?? '';
  }

  String get _effectiveRole {
    final passed = widget.currentUserRole?.trim() ?? '';
    if (passed.isNotEmpty) return passed;
    return _storedRole?.trim() ?? '';
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return '?';
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) {
      final word = parts[0];
      return word.length >= 2
          ? word.substring(0, 2).toUpperCase()
          : word[0].toUpperCase();
    }
    return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
  }

  String _getRoleLabel(String? role, String? specialty) {
    if (role == 'doctor') {
      if (specialty != null && specialty.trim().isNotEmpty)
        return specialty.trim();
      return 'Doctor';
    }
    if (role == 'hospital_admin') return 'Hospital Admin';
    if (role == 'platform_admin') return 'Platform Admin';
    return role ?? '';
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    if (q.trim().isEmpty) {
      _removeOverlay();
      if (mounted) setState(() { _searchResults = []; _isSearching = false; });
      return;
    }
    if (mounted) setState(() => _isSearching = true);
    _debounce = Timer(
      const Duration(milliseconds: 400),
      () => _doSearch(q.trim()),
    );
  }

  Future<void> _doSearch(String q) async {
    try {
      final results = await ApiService.getPatients(search: q);
      if (!mounted) return;
      setState(() {
        _searchResults = results.take(7).toList();
        _isSearching = false;
      });
      _showOverlay();
    } catch (_) {
      if (!mounted) return;
      setState(() { _searchResults = []; _isSearching = false; });
    }
  }

  void _showOverlay() {
    _removeOverlay();
    if (_searchResults.isEmpty) return;
    _overlayEntry = OverlayEntry(
      builder: (_) => Positioned(
        width: 300,
        child: CompositedTransformFollower(
          link: _layerLink,
          offset: const Offset(0, 46),
          child: Material(
            elevation: 12,
            borderRadius: BorderRadius.circular(14),
            shadowColor: Colors.black26,
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade100),
              ),
              constraints: const BoxConstraints(maxHeight: 360),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
                    child: Text(
                      'Patients',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.grey[500],
                        letterSpacing: 0.5,
                      ),
                    ),
                  ),
                  Flexible(
                    child: ListView.separated(
                      shrinkWrap: true,
                      padding: const EdgeInsets.only(bottom: 6),
                      itemCount: _searchResults.length,
                      separatorBuilder: (_, __) =>
                          Divider(height: 1, color: Colors.grey.shade100, indent: 14, endIndent: 14),
                      itemBuilder: (_, i) => _SearchResultTile(
                        patient: _searchResults[i],
                        onTap: () {
                          final id = _searchResults[i].patientId;
                          _searchCtrl.clear();
                          _removeOverlay();
                          _searchFocus.unfocus();
                          if (mounted) setState(() { _searchResults = []; _isSearching = false; });
                          widget.onPatientTap?.call(id);
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    Overlay.of(context).insert(_overlayEntry!);
  }

  void _removeOverlay() {
    _overlayEntry?.remove();
    _overlayEntry = null;
  }

  @override
  Widget build(BuildContext context) {
    final displayName = _effectiveName;
    final displayRole = _effectiveRole;
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: 0.95,
          child: Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(40),
              border: Border.all(
                color: const Color.fromARGB(255, 129, 129, 129),
                width: 0.8,
              ),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 2),
            child: Row(
              children: [
                Image.asset(
                  'assets/images/navbar logo.png',
                  height: 40,
                  fit: BoxFit.contain,
                ),
                const SizedBox(width: 16),

                // Global search bar
                CompositedTransformTarget(
                  link: _layerLink,
                  child: SizedBox(
                    width: 240,
                    child: TextField(
                      controller: _searchCtrl,
                      focusNode: _searchFocus,
                      onChanged: _onSearchChanged,
                      style: const TextStyle(fontSize: 13),
                      decoration: InputDecoration(
                        hintText: 'Search patients...',
                        hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
                        prefixIcon: Icon(
                          Icons.search_rounded,
                          size: 18,
                          color: Colors.grey[500],
                        ),
                        suffixIcon: _isSearching
                            ? Padding(
                                padding: const EdgeInsets.all(12),
                                child: SizedBox(
                                  width: 14,
                                  height: 14,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 1.5,
                                    valueColor: const AlwaysStoppedAnimation<Color>(
                                      Color(0xFF8B9E3A),
                                    ),
                                  ),
                                ),
                              )
                            : _searchCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: Icon(Icons.close_rounded, size: 16, color: Colors.grey[400]),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      _removeOverlay();
                                      if (mounted) setState(() => _searchResults = []);
                                    },
                                  )
                                : null,
                        contentPadding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
                        isDense: true,
                        filled: true,
                        fillColor: const Color(0xFFF7F7F7),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: BorderSide(color: Colors.grey.shade300, width: 0.8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20),
                          borderSide: const BorderSide(color: Color(0xFF8B9E3A), width: 1),
                        ),
                      ),
                    ),
                  ),
                ),

                // Spacer pushes everything else to the right
                const Spacer(),

                // Navigation items
                ...widget.navItems.map((item) {
                  final isActive = widget.activeItem == item.label;
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                    child: MouseRegion(
                      cursor: SystemMouseCursors.click,
                      child: GestureDetector(
                        onTap: item.onTap,
                        child: Text(
                          item.label,
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight:
                                isActive ? FontWeight.w600 : FontWeight.w500,
                            color:
                                isActive
                                    ? const Color.fromARGB(255, 59, 71, 5)
                                    : Colors.grey[700],
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                const SizedBox(width: 20),

                // User info container
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 5,
                  ),
                  decoration: const BoxDecoration(color: Colors.white),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircleAvatar(
                        radius: 16,
                        backgroundColor: const Color(0xFF8B9E3A),
                        child: Text(
                          _getInitials(displayName),
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      if (displayName.isNotEmpty)
                        Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: const TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Colors.black,
                              ),
                            ),
                            Text(
                              _getRoleLabel(
                                displayRole.isNotEmpty ? displayRole : null,
                                widget.currentUserSpecialty,
                              ),
                              style: TextStyle(
                                fontSize: 13,
                                color: Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),

                const SizedBox(width: 20),

                // Dropdown menu for Profile and Logout
                PopupMenuButton<String>(
                  onSelected: (value) async {
                    if (value == 'Logout') {
                      if (widget.onLogout != null) {
                        widget.onLogout!();
                      } else {
                        await ApiService.logout();
                        if (context.mounted) {
                          Navigator.of(context).pushNamedAndRemoveUntil(
                            '/login',
                            (route) => false,
                          );
                        }
                      }
                    }
                  },
                  offset: const Offset(0, 40),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                  color: Colors.white,
                  itemBuilder: (BuildContext context) {
                    return [
                      PopupMenuItem<String>(
                        value: 'Profile',
                        child: Row(
                          children: [
                            Icon(
                              Icons.person_outline,
                              color: Colors.black,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Profile',
                              style: TextStyle(fontSize: 14),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuItem<String>(
                        value: 'Logout',
                        child: Row(
                          children: [
                            Icon(
                              Icons.logout_outlined,
                              color: Colors.redAccent,
                              size: 20,
                            ),
                            const SizedBox(width: 10),
                            const Text(
                              'Logout',
                              style: TextStyle(
                                fontSize: 14,
                                color: Colors.redAccent,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ];
                  },
                  icon: const Icon(
                    Icons.arrow_drop_down_outlined,
                    color: Colors.black,
                    size: 24,
                  ),
                ),

                const SizedBox(width: 20),

                // Settings icon
                MouseRegion(
                  cursor: SystemMouseCursors.click,
                  child: GestureDetector(
                    onTap: widget.onSettingsTap,
                    child: Icon(
                      Icons.settings_outlined,
                      color: Colors.grey[600],
                      size: 22,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _SearchResultTile extends StatelessWidget {
  final PatientListItem patient;
  final VoidCallback onTap;

  const _SearchResultTile({required this.patient, required this.onTap});

  Color _priorityColor(String? p) {
    switch (p?.toLowerCase()) {
      case 'high':
        return const Color(0xFFDC2626);
      case 'medium':
        return const Color(0xFFD97706);
      case 'low':
        return const Color(0xFF16A34A);
      default:
        return Colors.grey;
    }
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    final w = parts[0];
    return w.length >= 2 ? w.substring(0, 2).toUpperCase() : w[0].toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: const Color(0xFF8B9E3A).withOpacity(0.12),
              child: Text(
                _initials(patient.fullName),
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF8B9E3A),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    patient.fullName,
                    style: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: Colors.black87,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      if (patient.age != null) ...[
                        Text(
                          'Age ${patient.age}',
                          style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                        ),
                        const SizedBox(width: 8),
                      ],
                      if (patient.priority != null)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: _priorityColor(patient.priority).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            patient.priority!,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: _priorityColor(patient.priority),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 11, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }
}

class NavBarItem {
  final String label;
  final VoidCallback onTap;

  NavBarItem({required this.label, required this.onTap});
}
