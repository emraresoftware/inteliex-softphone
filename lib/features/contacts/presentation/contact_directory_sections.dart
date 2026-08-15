import '../../../core/models/contact_entry.dart';

enum ContactDirectoryFilter {
  all,
  extensions,
  shared,
  personal,
}

extension ContactDirectoryFilterLabel on ContactDirectoryFilter {
  String get label {
    return switch (this) {
      ContactDirectoryFilter.all => 'Tumu',
      ContactDirectoryFilter.extensions => 'Dahililer',
      ContactDirectoryFilter.shared => 'Genel Rehber',
      ContactDirectoryFilter.personal => 'Kisisel Rehber',
    };
  }
}

class ContactDirectorySection {
  const ContactDirectorySection({
    required this.title,
    required this.contacts,
  });

  final String title;
  final List<ContactEntry> contacts;
}

List<ContactDirectorySection> buildContactDirectorySections({
  required List<ContactEntry> extensionContacts,
  required List<ContactEntry> sharedContacts,
  required List<ContactEntry> personalContacts,
  required ContactDirectoryFilter filter,
  String query = '',
}) {
  final normalizedQuery = query.trim().toLowerCase();
  final sources = switch (filter) {
    ContactDirectoryFilter.all => <_ContactSource>[
        _ContactSource('Dahililer', extensionContacts),
        _ContactSource('Genel Rehber', sharedContacts),
        _ContactSource('Kisisel Rehber', personalContacts),
      ],
    ContactDirectoryFilter.extensions => <_ContactSource>[
        _ContactSource('Dahililer', extensionContacts),
      ],
    ContactDirectoryFilter.shared => <_ContactSource>[
        _ContactSource('Genel Rehber', sharedContacts),
      ],
    ContactDirectoryFilter.personal => <_ContactSource>[
        _ContactSource('Kisisel Rehber', personalContacts),
      ],
  };

  final sections = <ContactDirectorySection>[];
  for (final source in sources) {
    final filteredContacts = normalizedQuery.isEmpty
        ? source.contacts
        : source.contacts.where(
            (contact) => _matchesContactQuery(contact, normalizedQuery),
          );
    final sectionContacts = List<ContactEntry>.unmodifiable(filteredContacts);
    if (sectionContacts.isEmpty) {
      continue;
    }

    sections.add(
      ContactDirectorySection(
        title: source.title,
        contacts: sectionContacts,
      ),
    );
  }

  return List<ContactDirectorySection>.unmodifiable(sections);
}

bool _matchesContactQuery(ContactEntry contact, String normalizedQuery) {
  final fields = <String>[
    contact.displayName,
    contact.primaryNumber,
    contact.department,
  ];

  for (final field in fields) {
    if (field.toLowerCase().contains(normalizedQuery)) {
      return true;
    }
  }

  return false;
}

class _ContactSource {
  const _ContactSource(this.title, this.contacts);

  final String title;
  final List<ContactEntry> contacts;
}
