import 'package:flutter_test/flutter_test.dart';
import 'package:inteliex_softphone/core/models/contact_entry.dart';
import 'package:inteliex_softphone/features/contacts/presentation/contact_directory_sections.dart';

void main() {
  const extensionContacts = <ContactEntry>[
    ContactEntry(
      id: 'ext-1',
      displayName: 'Operasyon Desk',
      primaryNumber: '1001',
      department: 'Operasyon',
    ),
  ];

  const sharedContacts = <ContactEntry>[
    ContactEntry(
      id: 'shared-1',
      displayName: 'Acme Lojistik',
      primaryNumber: '02125550000',
      department: 'Genel Rehber',
    ),
  ];

  const personalContacts = <ContactEntry>[
    ContactEntry(
      id: 'personal-1',
      displayName: 'Mehmet Kaya',
      primaryNumber: '05320000000',
      department: 'Kisisel Rehber',
    ),
  ];

  group('buildContactDirectorySections', () {
    test('returns all non-empty sections for all filter', () {
      final sections = buildContactDirectorySections(
        extensionContacts: extensionContacts,
        sharedContacts: sharedContacts,
        personalContacts: personalContacts,
        filter: ContactDirectoryFilter.all,
      );

      expect(sections, hasLength(3));
      expect(sections.map((section) => section.title), <String>[
        'Dahililer',
        'Genel Rehber',
        'Kisisel Rehber',
      ]);
    });

    test('limits sections to selected tab', () {
      final sections = buildContactDirectorySections(
        extensionContacts: extensionContacts,
        sharedContacts: sharedContacts,
        personalContacts: personalContacts,
        filter: ContactDirectoryFilter.shared,
      );

      expect(sections, hasLength(1));
      expect(sections.single.title, 'Genel Rehber');
      expect(sections.single.contacts.single.displayName, 'Acme Lojistik');
    });

    test('searches across name, number and department', () {
      final byName = buildContactDirectorySections(
        extensionContacts: extensionContacts,
        sharedContacts: sharedContacts,
        personalContacts: personalContacts,
        filter: ContactDirectoryFilter.all,
        query: 'mehmet',
      );
      final byNumber = buildContactDirectorySections(
        extensionContacts: extensionContacts,
        sharedContacts: sharedContacts,
        personalContacts: personalContacts,
        filter: ContactDirectoryFilter.all,
        query: '1001',
      );
      final byDepartment = buildContactDirectorySections(
        extensionContacts: extensionContacts,
        sharedContacts: sharedContacts,
        personalContacts: personalContacts,
        filter: ContactDirectoryFilter.all,
        query: 'operasyon',
      );

      expect(byName.single.contacts.single.displayName, 'Mehmet Kaya');
      expect(byNumber.single.contacts.single.displayName, 'Operasyon Desk');
      expect(
        byDepartment.single.contacts.single.displayName,
        'Operasyon Desk',
      );
    });

    test('omits empty sections after filtering', () {
      final sections = buildContactDirectorySections(
        extensionContacts: extensionContacts,
        sharedContacts: sharedContacts,
        personalContacts: personalContacts,
        filter: ContactDirectoryFilter.shared,
        query: 'olmayan',
      );

      expect(sections, isEmpty);
    });
  });
}
