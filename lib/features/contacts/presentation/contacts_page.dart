import 'package:flutter/material.dart';

import '../../../app/app_state_scope.dart';
import '../../../core/models/contact_entry.dart';
import 'contact_directory_sections.dart';

class ContactsPage extends StatefulWidget {
  const ContactsPage({super.key});

  @override
  State<ContactsPage> createState() => _ContactsPageState();
}

class _ContactsPageState extends State<ContactsPage>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  late final TextEditingController _searchController;
  ContactDirectoryFilter _selectedFilter = ContactDirectoryFilter.all;
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(
      length: ContactDirectoryFilter.values.length,
      vsync: this,
    );
    _searchController = TextEditingController();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);
    final theme = Theme.of(context);
    final sections = buildContactDirectorySections(
      extensionContacts: controller.extensionContacts,
      sharedContacts: controller.sharedContacts,
      personalContacts: controller.personalContacts,
      filter: _selectedFilter,
      query: _searchQuery,
    );
    final visibleContactCount = sections.fold<int>(
      0,
      (total, section) => total + section.contacts.length,
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child:
                    Text('Kisi rehberi', style: theme.textTheme.headlineMedium),
              ),
              IconButton(
                onPressed: controller.isLoadingDirectory
                    ? null
                    : () async {
                        await controller.refreshContactDirectory();
                      },
                icon: controller.isLoadingDirectory
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.refresh_rounded),
                tooltip: 'Yenile',
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _searchController,
            onChanged: (value) {
              setState(() {
                _searchQuery = value;
              });
            },
            decoration: InputDecoration(
              hintText: 'Isim, numara veya departman ara',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _searchQuery.isEmpty
                  ? null
                  : IconButton(
                      onPressed: () {
                        _searchController.clear();
                        setState(() {
                          _searchQuery = '';
                        });
                      },
                      icon: const Icon(Icons.close_rounded),
                      tooltip: 'Aramayi temizle',
                    ),
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TabBar(
            controller: _tabController,
            isScrollable: true,
            onTap: (index) {
              final nextFilter = ContactDirectoryFilter.values[index];
              if (_selectedFilter == nextFilter) {
                return;
              }

              setState(() {
                _selectedFilter = nextFilter;
              });
            },
            tabs: [
              for (final filter in ContactDirectoryFilter.values)
                Tab(text: filter.label),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _buildResultsSummary(visibleContactCount),
            style: theme.textTheme.bodySmall,
          ),
          const SizedBox(height: 8),
          Expanded(
            child: RefreshIndicator(
              onRefresh: controller.refreshContactDirectory,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  if (sections.isEmpty) ...[
                    const SizedBox(height: 120),
                    Center(
                      child: Text(
                        _buildEmptyStateMessage(controller.isLoadingDirectory),
                        style: theme.textTheme.bodyLarge,
                      ),
                    ),
                  ],
                  for (final section in sections) ...[
                    Text(section.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 10),
                    for (final contact in section.contacts) ...[
                      _ContactTile(contact: contact),
                      const SizedBox(height: 12),
                    ],
                    const SizedBox(height: 10),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _buildResultsSummary(int visibleContactCount) {
    if (_searchQuery.trim().isEmpty &&
        _selectedFilter == ContactDirectoryFilter.all) {
      return '$visibleContactCount kayit gosteriliyor';
    }

    final filterLabel = _selectedFilter.label;
    if (_searchQuery.trim().isEmpty) {
      return '$filterLabel sekmesinde $visibleContactCount kayit gosteriliyor';
    }

    return '"${_searchQuery.trim()}" icin $visibleContactCount kayit bulundu';
  }

  String _buildEmptyStateMessage(bool isLoadingDirectory) {
    if (isLoadingDirectory) {
      return 'Inteliex rehberi yukleniyor...';
    }

    if (_searchQuery.trim().isNotEmpty) {
      return 'Arama kriterine uyan rehber kaydi bulunamadi.';
    }

    return 'Bu sekmede gosterilecek rehber kaydi bulunamadi.';
  }
}

class _ContactTile extends StatelessWidget {
  const _ContactTile({required this.contact});

  final ContactEntry contact;

  @override
  Widget build(BuildContext context) {
    final controller = AppStateScope.of(context);
    final theme = Theme.of(context);

    return Card(
      child: ListTile(
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
        leading: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            color: const Color(0xFFDFEFEA),
            borderRadius: BorderRadius.circular(16),
          ),
          alignment: Alignment.center,
          child: Text(
            contact.displayName.trim().isEmpty
                ? '?'
                : contact.displayName.trim().characters.first,
            style: theme.textTheme.titleLarge?.copyWith(
              color: const Color(0xFF16332E),
            ),
          ),
        ),
        title: Text(contact.displayName),
        subtitle: Text('${contact.department}  -  ${contact.primaryNumber}'),
        trailing: Wrap(
          spacing: 8,
          children: [
            IconButton.filledTonal(
              onPressed: () =>
                  controller.fillDialedNumber(contact.primaryNumber),
              icon: const Icon(Icons.dialpad_rounded),
            ),
            IconButton.filled(
              onPressed: () =>
                  controller.startOutgoingCall(contact.primaryNumber),
              icon: const Icon(Icons.call_rounded),
            ),
          ],
        ),
      ),
    );
  }
}
