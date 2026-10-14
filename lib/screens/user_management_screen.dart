import 'package:flutter/material.dart';
import '../models/app_user.dart';
import '../services/auth_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_snackbar.dart';

class UserManagementScreen extends StatefulWidget {
  const UserManagementScreen({super.key});

  @override
  State<UserManagementScreen> createState() => _UserManagementScreenState();
}

class _UserManagementScreenState extends State<UserManagementScreen> {
  List<AppUser> _users = [];
  bool _isLoading = true;
  String _searchQuery = '';
  String _selectedRoleFilter = 'Semua';

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    setState(() => _isLoading = true);
    final users = await AuthService.getAllUsers();
    if (mounted) {
      setState(() {
        _users = users;
        _isLoading = false;
      });
    }
  }

  List<AppUser> get _filteredUsers {
    return _users.where((u) {
      final matchesSearch = u.name.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          u.username.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          u.email.toLowerCase().contains(_searchQuery.toLowerCase());

      if (_selectedRoleFilter == 'Semua') return matchesSearch;
      if (_selectedRoleFilter == 'Admin') return matchesSearch && u.isAdmin;
      if (_selectedRoleFilter == 'Pemantau') return matchesSearch && !u.isAdmin;
      return matchesSearch;
    }).toList();
  }

  void _showAddUserModal() {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController();
    final usernameCtrl = TextEditingController();
    final passwordCtrl = TextEditingController();
    final emailCtrl = TextEditingController();
    String selectedRole = 'viewer';

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Row(
                            children: [
                              CircleAvatar(
                                backgroundColor: AppTheme.primaryLight,
                                child: Icon(Icons.person_add_alt_1, color: AppTheme.primary),
                              ),
                              SizedBox(width: 12),
                              Text(
                                'Tambah User Baru',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama Lengkap',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: usernameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Username',
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Username wajib diisi' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: passwordCtrl,
                        obscureText: true,
                        decoration: const InputDecoration(
                          labelText: 'Password',
                          prefixIcon: Icon(Icons.lock_outline),
                        ),
                        validator: (v) => v == null || v.length < 6 ? 'Password minimal 6 karakter' : null,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Pilih Role User:',
                        style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Pemantau (Viewer)')),
                              selected: selectedRole == 'viewer',
                              selectedColor: AppTheme.primaryLight,
                              labelStyle: TextStyle(
                                color: selectedRole == 'viewer' ? AppTheme.primary : AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) => setModalState(() => selectedRole = 'viewer'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Administrator')),
                              selected: selectedRole == 'admin',
                              selectedColor: Colors.amber.shade100,
                              labelStyle: TextStyle(
                                color: selectedRole == 'admin' ? Colors.amber.shade900 : AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) => setModalState(() => selectedRole = 'admin'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final success = await AuthService.createUser(
                                username: usernameCtrl.text.trim(),
                                password: passwordCtrl.text.trim(),
                                name: nameCtrl.text.trim(),
                                role: selectedRole,
                                email: emailCtrl.text.trim(),
                              );
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                if (success) {
                                  AppSnackBar.success(context, 'User baru berhasil ditambahkan!');
                                  _fetchUsers();
                                }
                              }
                            }
                          },
                          child: const Text('Simpan User Baru'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _showEditUserModal(AppUser user) {
    final formKey = GlobalKey<FormState>();
    final nameCtrl = TextEditingController(text: user.name);
    final emailCtrl = TextEditingController(text: user.email);
    String selectedRole = user.role;
    String selectedStatus = user.status;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Container(
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: EdgeInsets.only(
                left: 24,
                right: 24,
                top: 24,
                bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
              ),
              child: SingleChildScrollView(
                child: Form(
                  key: formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              const CircleAvatar(
                                backgroundColor: AppTheme.primaryLight,
                                child: Icon(Icons.edit, color: AppTheme.primary),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                'Edit User (@${user.username})',
                                style: const TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold,
                                  color: AppTheme.textPrimary,
                                ),
                              ),
                            ],
                          ),
                          IconButton(
                            icon: const Icon(Icons.close),
                            onPressed: () => Navigator.pop(ctx),
                          ),
                        ],
                      ),
                      if (user.createdAt.isNotEmpty) ...[
                        const SizedBox(height: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            color: AppTheme.background,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: AppTheme.border.withValues(alpha: 0.6)),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.calendar_today_outlined, size: 14, color: AppTheme.textSecondary),
                              const SizedBox(width: 8),
                              Text(
                                'Terdaftar Sejak: ${user.formattedCreatedAt}',
                                style: const TextStyle(fontSize: 12, color: AppTheme.textSecondary, fontWeight: FontWeight.w500),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: nameCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama Lengkap',
                          prefixIcon: Icon(Icons.badge_outlined),
                        ),
                        validator: (v) => v == null || v.trim().isEmpty ? 'Nama wajib diisi' : null,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: emailCtrl,
                        keyboardType: TextInputType.emailAddress,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          prefixIcon: Icon(Icons.email_outlined),
                        ),
                      ),
                      const SizedBox(height: 16),
                      const Text('Role Akses:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Pemantau')),
                              selected: selectedRole == 'viewer',
                              selectedColor: AppTheme.primaryLight,
                              onSelected: (_) => setModalState(() => selectedRole = 'viewer'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Administrator')),
                              selected: selectedRole == 'admin',
                              selectedColor: Colors.amber.shade100,
                              onSelected: (_) => setModalState(() => selectedRole = 'admin'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Text('Status Akun:', style: TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Aktif')),
                              selected: selectedStatus == 'Aktif',
                              selectedColor: AppTheme.successBg,
                              labelStyle: TextStyle(
                                color: selectedStatus == 'Aktif' ? AppTheme.success : AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) => setModalState(() => selectedStatus = 'Aktif'),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: ChoiceChip(
                              label: const Center(child: Text('Nonaktif')),
                              selected: selectedStatus == 'Nonaktif',
                              selectedColor: AppTheme.dangerBg,
                              labelStyle: TextStyle(
                                color: selectedStatus == 'Nonaktif' ? AppTheme.danger : AppTheme.textSecondary,
                                fontWeight: FontWeight.bold,
                              ),
                              onSelected: (_) => setModalState(() => selectedStatus = 'Nonaktif'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton(
                          onPressed: () async {
                            if (formKey.currentState!.validate()) {
                              final updated = AppUser(
                                id: user.id,
                                username: user.username,
                                name: nameCtrl.text.trim(),
                                role: selectedRole,
                                email: emailCtrl.text.trim(),
                                status: selectedStatus,
                              );
                              await AuthService.updateUser(updated);
                              if (context.mounted) {
                                Navigator.pop(ctx);
                                AppSnackBar.success(context, 'Data user diperbarui!');
                                _fetchUsers();
                              }
                            }
                          },
                          child: const Text('Update Data User'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  void _confirmDeleteUser(AppUser user) {
    if (user.username == 'admin') {
      AppSnackBar.warning(context, 'Akun Utama Super Admin tidak boleh dihapus!');
      return;
    }

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Hapus Akun User?'),
        content: Text('Apakah Anda yakin ingin menghapus akun ${user.name} (@${user.username})?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: AppTheme.danger),
            onPressed: () async {
              if (user.id != null) {
                await AuthService.deleteUser(user.id!);
              }
              if (mounted) {
                Navigator.pop(ctx);
                AppSnackBar.deleted(context, 'Akun user telah dihapus.');
                _fetchUsers();
              }
            },
            child: const Text('Hapus Akun', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final adminCount = _users.where((u) => u.isAdmin).length;
    final viewerCount = _users.where((u) => !u.isAdmin).length;

    return Scaffold(
      backgroundColor: AppTheme.background,
      body: RefreshIndicator(
        color: AppTheme.primary,
        backgroundColor: Colors.white,
        onRefresh: _fetchUsers,
        child: SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(20),
          child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 1000),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Summary Header Card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    gradient: AppTheme.primaryGradient,
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: AppTheme.softShadow,
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isMobile = constraints.maxWidth < 600;
                      final addBtn = ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: AppTheme.primary,
                          elevation: 2,
                          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('Tambah User'),
                        onPressed: _showAddUserModal,
                      );

                      final textInfo = Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: const Text(
                              'Role Admin & Akses',
                              style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ),
                          const SizedBox(height: 10),
                          const Text(
                            'Kelola Pengguna Sistem',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            'Atur hak akses pemantauan, tambah akun petugas baru, dan reset kata sandi.',
                            style: TextStyle(color: Colors.white.withValues(alpha: 0.85), fontSize: 12),
                          ),
                        ],
                      );

                      if (isMobile) {
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            textInfo,
                            const SizedBox(height: 16),
                            addBtn,
                          ],
                        );
                      }

                      return Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          Expanded(child: textInfo),
                          const SizedBox(width: 16),
                          addBtn,
                        ],
                      );
                    },
                  ),
                ),

                const SizedBox(height: 20),

                // Stat Cards Row
                LayoutBuilder(
                  builder: (context, constraints) {
                    final isMobile = constraints.maxWidth < 600;

                    final cardTotal = _buildStatBadge(
                      title: 'Total Pengguna',
                      value: '${_users.length}',
                      icon: Icons.people_alt,
                      color: AppTheme.primary,
                      bgColor: AppTheme.primaryLight,
                    );
                    final cardAdmin = _buildStatBadge(
                      title: 'Administrator',
                      value: '$adminCount',
                      icon: Icons.admin_panel_settings,
                      color: Colors.amber.shade800,
                      bgColor: Colors.amber.shade50,
                    );
                    final cardViewer = _buildStatBadge(
                      title: 'Petugas Pemantau',
                      value: '$viewerCount',
                      icon: Icons.visibility,
                      color: AppTheme.success,
                      bgColor: AppTheme.successBg,
                    );

                    if (isMobile) {
                      return Column(
                        children: [
                          cardTotal,
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(child: cardAdmin),
                              const SizedBox(width: 10),
                              Expanded(child: cardViewer),
                            ],
                          ),
                        ],
                      );
                    }

                    return Row(
                      children: [
                        Expanded(child: cardTotal),
                        const SizedBox(width: 12),
                        Expanded(child: cardAdmin),
                        const SizedBox(width: 12),
                        Expanded(child: cardViewer),
                      ],
                    );
                  },
                ),

                const SizedBox(height: 24),

                // Search Bar and Filters
                Card(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                onChanged: (v) => setState(() => _searchQuery = v),
                                decoration: InputDecoration(
                                  hintText: 'Cari berdasarkan nama, username, atau email...',
                                  prefixIcon: const Icon(Icons.search, color: AppTheme.primary),
                                  suffixIcon: _searchQuery.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.clear),
                                          onPressed: () => setState(() => _searchQuery = ''),
                                        )
                                      : null,
                                  filled: true,
                                  fillColor: AppTheme.background,
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(14),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Row(
                          children: [
                            const Icon(Icons.tune_rounded, size: 18, color: AppTheme.textSecondary),
                            const SizedBox(width: 8),
                            const Text('Filter Role:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: AppTheme.textSecondary)),
                            const SizedBox(width: 10),
                            Expanded(
                              child: InkWell(
                                onTap: _showRoleFilterModal,
                                borderRadius: BorderRadius.circular(10),
                                child: Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                  decoration: BoxDecoration(
                                    color: _selectedRoleFilter == 'Semua' ? AppTheme.background : AppTheme.primaryLight,
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(
                                      color: _selectedRoleFilter == 'Semua'
                                          ? AppTheme.border
                                          : AppTheme.primary.withValues(alpha: 0.3),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                    children: [
                                      Flexible(
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            if (_selectedRoleFilter != 'Semua') ...[
                                              Icon(
                                                _selectedRoleFilter == 'Admin' ? Icons.admin_panel_settings_outlined : Icons.visibility_outlined,
                                                size: 14,
                                                color: _selectedRoleFilter == 'Admin' ? Colors.amber.shade900 : AppTheme.primary,
                                              ),
                                              const SizedBox(width: 6),
                                            ],
                                            Flexible(
                                              child: Text(
                                                _selectedRoleFilter == 'Semua' ? 'Semua Role' : 'Role $_selectedRoleFilter',
                                                style: TextStyle(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: _selectedRoleFilter == 'Semua'
                                                      ? AppTheme.textPrimary
                                                      : (_selectedRoleFilter == 'Admin' ? Colors.amber.shade900 : AppTheme.primary),
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 18,
                                        color: _selectedRoleFilter == 'Semua' ? AppTheme.textSecondary : AppTheme.primary,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                            if (_selectedRoleFilter != 'Semua') ...[
                              const SizedBox(width: 6),
                              IconButton(
                                tooltip: 'Reset Filter',
                                icon: const Icon(Icons.close_rounded, size: 18, color: AppTheme.textMuted),
                                onPressed: () => setState(() => _selectedRoleFilter = 'Semua'),
                              ),
                            ],
                            const SizedBox(width: 6),
                            IconButton(
                              tooltip: 'Refresh Data',
                              icon: const Icon(Icons.refresh_rounded, color: AppTheme.primary),
                              onPressed: _fetchUsers,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),

                const SizedBox(height: 20),

                // Users List
                _isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(40),
                        child: Center(child: CircularProgressIndicator()),
                      )
                    : _filteredUsers.isEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(40),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(20),
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.person_search_outlined, size: 64, color: Colors.grey.shade300),
                                const SizedBox(height: 12),
                                const Text(
                                  'User Tidak Ditemukan',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textSecondary),
                                ),
                                const SizedBox(height: 4),
                                const Text('Coba ubah kata kunci pencarian atau filter role.', style: TextStyle(color: AppTheme.textMuted, fontSize: 13)),
                              ],
                            ),
                          )
                        : ListView.separated(
                            shrinkWrap: true,
                            physics: const NeverScrollableScrollPhysics(),
                            itemCount: _filteredUsers.length,
                            separatorBuilder: (_, __) => const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final user = _filteredUsers[index];
                              return Card(
                                elevation: 0,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  side: BorderSide(color: AppTheme.border.withValues(alpha: 0.8)),
                                ),
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Row(
                                    children: [
                                      CircleAvatar(
                                        radius: 22,
                                        backgroundColor: user.isAdmin ? Colors.amber.shade100 : AppTheme.primaryLight,
                                        child: Text(
                                          user.name.isNotEmpty ? user.name[0].toUpperCase() : 'U',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                            color: user.isAdmin ? Colors.amber.shade900 : AppTheme.primary,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Wrap(
                                              crossAxisAlignment: WrapCrossAlignment.center,
                                              spacing: 6,
                                              runSpacing: 4,
                                              children: [
                                                Text(
                                                  user.name,
                                                  style: const TextStyle(
                                                    fontWeight: FontWeight.bold,
                                                    fontSize: 15,
                                                    color: AppTheme.textPrimary,
                                                  ),
                                                ),
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: user.isAdmin ? Colors.amber.shade100 : AppTheme.primaryLight,
                                                    borderRadius: BorderRadius.circular(8),
                                                  ),
                                                  child: Text(
                                                    user.isAdmin ? 'ADMIN' : 'PEMANTAU',
                                                    style: TextStyle(
                                                      fontSize: 10,
                                                      fontWeight: FontWeight.bold,
                                                      color: user.isAdmin ? Colors.amber.shade900 : AppTheme.primary,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              '@${user.username} ${user.email.isNotEmpty ? '• ${user.email}' : ''}',
                                              style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: user.status == 'Aktif' ? AppTheme.successBg : AppTheme.dangerBg,
                                          borderRadius: BorderRadius.circular(10),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            CircleAvatar(
                                              radius: 3,
                                              backgroundColor: user.status == 'Aktif' ? AppTheme.success : AppTheme.danger,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              user.status,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.bold,
                                                color: user.status == 'Aktif' ? AppTheme.success : AppTheme.danger,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      PopupMenuButton<String>(
                                        padding: EdgeInsets.zero,
                                        icon: const Icon(Icons.more_vert, color: AppTheme.textSecondary, size: 20),
                                        onSelected: (val) {
                                          if (val == 'edit') {
                                            _showEditUserModal(user);
                                          } else if (val == 'delete') {
                                            _confirmDeleteUser(user);
                                          }
                                        },
                                        itemBuilder: (ctx) => [
                                          const PopupMenuItem(
                                            value: 'edit',
                                            child: Row(
                                              children: [
                                                Icon(Icons.edit, size: 18, color: AppTheme.primary),
                                                SizedBox(width: 8),
                                                Text('Edit User'),
                                              ],
                                            ),
                                          ),
                                          const PopupMenuItem(
                                            value: 'delete',
                                            child: Row(
                                              children: [
                                                Icon(Icons.delete_outline, size: 18, color: AppTheme.danger),
                                                SizedBox(width: 8),
                                                Text('Hapus User', style: TextStyle(color: AppTheme.danger)),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}

  Widget _buildStatBadge({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required Color bgColor,
  }) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: const BorderSide(color: AppTheme.border),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 12),
        child: Row(
          children: [
            CircleAvatar(
              radius: 18,
              backgroundColor: bgColor,
              child: Icon(icon, color: color, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      value,
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: color),
                    ),
                  ),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(
                      title,
                      style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
                      maxLines: 1,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _showRoleFilterModal() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        return SafeArea(
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Container(
              constraints: BoxConstraints(
                maxHeight: MediaQuery.of(ctx).size.height * 0.85,
                maxWidth: 600,
              ),
              decoration: const BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Row(
                      children: [
                        Icon(Icons.tune_rounded, color: AppTheme.primary, size: 20),
                        SizedBox(width: 8),
                        Text(
                          'Pilih Filter Role Pengguna',
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppTheme.textPrimary),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _buildRoleFilterOptionModal(
                      label: 'Semua Role',
                      subtitle: 'Tampilkan seluruh pengguna tanpa filter',
                      value: 'Semua',
                      icon: Icons.people_alt_rounded,
                      iconColor: AppTheme.primary,
                      bgColor: AppTheme.primaryLight,
                    ),
                    const SizedBox(height: 6),
                    _buildRoleFilterOptionModal(
                      label: 'Administrator (Admin)',
                      subtitle: 'Akses penuh kontrol, user management, dan setelan',
                      value: 'Admin',
                      icon: Icons.admin_panel_settings_rounded,
                      iconColor: Colors.amber.shade900,
                      bgColor: Colors.amber.shade50,
                    ),
                    const SizedBox(height: 6),
                    _buildRoleFilterOptionModal(
                      label: 'Petugas Pemantau (Viewer)',
                      subtitle: 'Akses melihat status sensor live dan riwayat deteksi',
                      value: 'Pemantau',
                      icon: Icons.visibility_rounded,
                      iconColor: AppTheme.primary,
                      bgColor: AppTheme.primaryLight,
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRoleFilterOptionModal({
    required String label,
    required String subtitle,
    required String value,
    required IconData icon,
    required Color iconColor,
    required Color bgColor,
  }) {
    final isSelected = _selectedRoleFilter == value;

    return InkWell(
      onTap: () {
        setState(() => _selectedRoleFilter = value);
        Navigator.pop(context);
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isSelected ? bgColor.withValues(alpha: 0.6) : AppTheme.background,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? iconColor.withValues(alpha: 0.6) : AppTheme.border,
            width: isSelected ? 1.5 : 1,
          ),
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 16,
              backgroundColor: bgColor,
              child: Icon(icon, color: iconColor, size: 16),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                      color: isSelected ? iconColor : AppTheme.textPrimary,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: const TextStyle(fontSize: 11, color: AppTheme.textSecondary),
                  ),
                ],
              ),
            ),
            if (isSelected)
              Icon(Icons.check_circle_rounded, color: iconColor, size: 18),
          ],
        ),
      ),
    );
  }
}
