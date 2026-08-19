import 'package:flutter/foundation.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/contact_entry.dart';

/// Telefonun kendi rehberi (cihaz kisileri).
///
/// Santral rehberinden bagimsiz, tamamen opsiyonel bir kaynaktir: kullanici
/// acikca acmadan izin istenmez ve kayit okunmaz. Kayitlar yalnizca uygulama
/// icinde gosterilir; hicbir yere gonderilmez.
class DeviceContactsService {
  DeviceContactsService();

  static const _enabledKey = 'inteliex.device_contacts.enabled.v1';

  /// Kullanici telefon rehberini acmis mi?
  Future<bool> isEnabled() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(_enabledKey) ?? false;
    } catch (error) {
      debugPrint('Telefon rehberi tercihi okunamadi: $error');
      return false;
    }
  }

  Future<void> setEnabled(bool value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_enabledKey, value);
    } catch (error) {
      debugPrint('Telefon rehberi tercihi kaydedilemedi: $error');
    }
  }

  /// Izin ister. Kullanici reddederse false doner (uygulama akisi bozulmaz).
  Future<bool> requestPermission() async {
    try {
      return await FlutterContacts.requestPermission(readonly: true);
    } catch (error) {
      debugPrint('Telefon rehberi izni alinamadi: $error');
      return false;
    }
  }

  /// Cihaz kisilerini okur. Izin yoksa bos liste doner.
  Future<List<ContactEntry>> fetchContacts() async {
    try {
      final granted = await FlutterContacts.requestPermission(readonly: true);
      if (!granted) {
        return const <ContactEntry>[];
      }

      final contacts = await FlutterContacts.getContacts(
        withProperties: true,
        deduplicateProperties: true,
      );

      final entries = <ContactEntry>[];
      for (final contact in contacts) {
        final number = contact.phones
            .map((phone) => phone.number.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');
        if (number.isEmpty) {
          continue;
        }
        final name = contact.displayName.trim().isEmpty
            ? number
            : contact.displayName.trim();
        entries.add(
          ContactEntry(
            id: 'device-${contact.id}',
            displayName: name,
            primaryNumber: number,
            department: 'Telefon Rehberi',
          ),
        );
      }

      entries.sort(
        (a, b) => a.displayName.toLowerCase().compareTo(
              b.displayName.toLowerCase(),
            ),
      );
      return List<ContactEntry>.unmodifiable(entries);
    } catch (error) {
      debugPrint('Telefon rehberi okunamadi: $error');
      return const <ContactEntry>[];
    }
  }
}
