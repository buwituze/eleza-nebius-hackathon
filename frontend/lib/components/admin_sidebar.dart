import 'package:flutter/material.dart';

class AdminSidebar extends StatelessWidget {
  final String activeItem;
  final ValueChanged<String>? onItemSelected;

  const AdminSidebar({Key? key, required this.activeItem, this.onItemSelected})
    : super(key: key);

  static const Color _activeGreen = Color(0xFF8B9E3A);

  static const List<_AdminMenuItem> _menuItems = [
    _AdminMenuItem(label: 'Users', icon: Icons.people_alt_outlined),
    _AdminMenuItem(label: 'Facilities', icon: Icons.local_hospital_outlined),
    _AdminMenuItem(label: 'Doctors', icon: Icons.medical_services_outlined),
    _AdminMenuItem(label: 'Rooms', icon: Icons.meeting_room_outlined),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 250,
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(
          right: BorderSide(
            color: const Color.fromARGB(255, 129, 129, 129),
            width: 0.8,
          ),
        ),
      ),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(16, 36, 16, 16),
              decoration: BoxDecoration(
                border: Border(
                  bottom: BorderSide(color: Colors.grey.shade100, width: 1),
                ),
              ),
              child: const Text(
                'Eleza Admin Panel',
                style: TextStyle(
                  color: Colors.black,
                  fontSize: 18,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(height: 28),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 4, 12, 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ..._menuItems.map((item) {
                      final isActive = item.label == activeItem;
                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Material(
                          color: isActive ? _activeGreen : Colors.transparent,
                          borderRadius: BorderRadius.circular(10),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(10),
                            onTap: () => onItemSelected?.call(item.label),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 11,
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    item.icon,
                                    size: 20,
                                    color: isActive ? Colors.black : Colors.black54,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    item.label,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight:
                                          isActive
                                              ? FontWeight.w700
                                              : FontWeight.w500,
                                      color: isActive ? Colors.black : Colors.black87,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AdminMenuItem {
  final String label;
  final IconData icon;

  const _AdminMenuItem({required this.label, required this.icon});
}
