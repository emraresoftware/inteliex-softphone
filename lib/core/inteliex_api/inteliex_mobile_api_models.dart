const inteliexMobileApiRequestType = '87514ce9015fa31c7161dfb9c2aaaf97';
const inteliexMobileApiDefaultOffset = 0;
const inteliexMobileApiDefaultRecordPerPage = 50;

enum InteliexMobileApiAction {
  extList,
  phoneBook,
  personalPhoneBook,
  personalPhoneBookSearch,
  personalPhoneBookAdd,
  personalPhoneBookUpdate,
  personalPhoneBookDelete,
  shortCodes,
  voiceMail,
  voiceMailDelete,
}

extension InteliexMobileApiActionWireName on InteliexMobileApiAction {
  String get wireName {
    return switch (this) {
      InteliexMobileApiAction.extList => 'ext_list',
      InteliexMobileApiAction.phoneBook => 'phone_book',
      InteliexMobileApiAction.personalPhoneBook => 'personal_phone_book',
      InteliexMobileApiAction.personalPhoneBookSearch =>
        'personal_phone_book_search',
      InteliexMobileApiAction.personalPhoneBookAdd => 'personal_phone_book_add',
      InteliexMobileApiAction.personalPhoneBookUpdate =>
        'personal_phone_book_update',
      InteliexMobileApiAction.personalPhoneBookDelete =>
        'personal_phone_book_delete',
      InteliexMobileApiAction.shortCodes => 'short_codes',
      InteliexMobileApiAction.voiceMail => 'voice_mail',
      InteliexMobileApiAction.voiceMailDelete => 'voice_mail_delete',
    };
  }

  String get successStatus => 'ok-$wireName';
}

enum InteliexMobileApiFailure {
  authFail,
  userNotFound,
  requiredFields,
  unknown,
}

InteliexMobileApiFailure? inteliexMobileApiFailureFromStatus(String? value) {
  final status = (value ?? '').trim();
  if (status.isEmpty || status.startsWith('ok-')) {
    return null;
  }

  return switch (status) {
    'auth_fail' => InteliexMobileApiFailure.authFail,
    'user_not_found' => InteliexMobileApiFailure.userNotFound,
    'required_fields' => InteliexMobileApiFailure.requiredFields,
    _ => InteliexMobileApiFailure.unknown,
  };
}

class InteliexMobileApiAuth {
  const InteliexMobileApiAuth({
    required this.user,
    required this.password,
    this.fcmToken,
  });

  final String user;
  final String password;
  final String? fcmToken;

  Map<String, Object?> toJson() {
    return {
      'user': user,
      'password': password,
      if (fcmToken != null && fcmToken!.trim().isNotEmpty)
        'fcmtoken': fcmToken,
    };
  }
}

class InteliexMobileApiRequestEnvelope<T extends InteliexMobileApiRequestData> {
  const InteliexMobileApiRequestEnvelope({
    required this.auth,
    required this.request,
  });

  final InteliexMobileApiAuth auth;
  final T request;

  Map<String, Object?> toJson() {
    return {
      'auth': auth.toJson(),
      'request': request.toJson(),
    };
  }
}

abstract class InteliexMobileApiRequestData {
  const InteliexMobileApiRequestData(this.action);

  final InteliexMobileApiAction action;

  Map<String, Object?> toJson();
}

abstract class InteliexOffsetRequestData extends InteliexMobileApiRequestData {
  const InteliexOffsetRequestData(
    super.action, {
    this.offset = inteliexMobileApiDefaultOffset,
    this.recordPerPage = inteliexMobileApiDefaultRecordPerPage,
  });

  final int offset;
  final int recordPerPage;

  @override
  Map<String, Object?> toJson() {
    return {
      'action': action.wireName,
      'page': offset,
      'record_per_page': recordPerPage,
    };
  }
}

class InteliexExtListRequest extends InteliexOffsetRequestData {
  const InteliexExtListRequest({
    super.offset,
    super.recordPerPage,
  }) : super(InteliexMobileApiAction.extList);
}

class InteliexPhoneBookRequest extends InteliexOffsetRequestData {
  const InteliexPhoneBookRequest({
    super.offset,
    super.recordPerPage,
  }) : super(InteliexMobileApiAction.phoneBook);
}

class InteliexPersonalPhoneBookRequest extends InteliexOffsetRequestData {
  const InteliexPersonalPhoneBookRequest({
    super.offset,
    super.recordPerPage,
  }) : super(InteliexMobileApiAction.personalPhoneBook);
}

class InteliexPersonalPhoneBookSearchRequest extends InteliexOffsetRequestData {
  const InteliexPersonalPhoneBookSearchRequest({
    required this.query,
    super.offset,
    super.recordPerPage,
  }) : super(InteliexMobileApiAction.personalPhoneBookSearch);

  final String query;

  @override
  Map<String, Object?> toJson() {
    return {
      ...super.toJson(),
      'seach': query,
    };
  }
}

class InteliexPhoneBookDraft {
  const InteliexPhoneBookDraft({
    required this.nameCompany,
    required this.registerName,
    this.phoneNumber = '',
    this.phoneNumber2 = '',
    this.phoneNumber3 = '',
    this.mobilePhone = '',
    this.mobilePhone2 = '',
    this.faxNumber = '',
    this.comment = '',
    this.email = '',
    this.email2 = '',
    this.address = '',
  });

  final String nameCompany;
  final String registerName;
  final String phoneNumber;
  final String phoneNumber2;
  final String phoneNumber3;
  final String mobilePhone;
  final String mobilePhone2;
  final String faxNumber;
  final String comment;
  final String email;
  final String email2;
  final String address;

  Map<String, Object?> toRequestJson() {
    return {
      'name_company': nameCompany,
      'register_name': registerName,
      'phone_number': phoneNumber,
      'phone_number2': phoneNumber2,
      'phone_number3': phoneNumber3,
      'mobile_phone': mobilePhone,
      'mobile_phone2': mobilePhone2,
      'fax_number': faxNumber,
      'comment': comment,
      'email': email,
      'email2': email2,
      'address': address,
    };
  }
}

class InteliexPersonalPhoneBookAddRequest extends InteliexMobileApiRequestData {
  const InteliexPersonalPhoneBookAddRequest({required this.entry})
    : super(InteliexMobileApiAction.personalPhoneBookAdd);

  final InteliexPhoneBookDraft entry;

  @override
  Map<String, Object?> toJson() {
    return {
      'action': action.wireName,
      ...entry.toRequestJson(),
    };
  }
}

class InteliexPersonalPhoneBookUpdateRequest extends InteliexMobileApiRequestData {
  const InteliexPersonalPhoneBookUpdateRequest({
    required this.recordId,
    required this.entry,
  }) : super(InteliexMobileApiAction.personalPhoneBookUpdate);

  final String recordId;
  final InteliexPhoneBookDraft entry;

  @override
  Map<String, Object?> toJson() {
    return {
      'action': action.wireName,
      'recordid': recordId,
      ...entry.toRequestJson(),
    };
  }
}

abstract class InteliexRecordIdRequestData extends InteliexMobileApiRequestData {
  const InteliexRecordIdRequestData(super.action, {required this.recordId});

  final String recordId;

  @override
  Map<String, Object?> toJson() {
    return {
      'action': action.wireName,
      'recordid': recordId,
    };
  }
}

class InteliexPersonalPhoneBookDeleteRequest extends InteliexRecordIdRequestData {
  const InteliexPersonalPhoneBookDeleteRequest({required super.recordId})
    : super(InteliexMobileApiAction.personalPhoneBookDelete);
}

class InteliexShortCodesRequest extends InteliexMobileApiRequestData {
  const InteliexShortCodesRequest() : super(InteliexMobileApiAction.shortCodes);

  @override
  Map<String, Object?> toJson() {
    return {'action': action.wireName};
  }
}

class InteliexVoiceMailRequest extends InteliexMobileApiRequestData {
  const InteliexVoiceMailRequest() : super(InteliexMobileApiAction.voiceMail);

  @override
  Map<String, Object?> toJson() {
    return {'action': action.wireName};
  }
}

class InteliexVoiceMailDeleteRequest extends InteliexRecordIdRequestData {
  const InteliexVoiceMailDeleteRequest({required super.recordId})
    : super(InteliexMobileApiAction.voiceMailDelete);
}

abstract class InteliexMobileApiResponseEnvelope {
  const InteliexMobileApiResponseEnvelope({required this.status});

  final String status;

  bool get isSuccess => status.startsWith('ok-');

  InteliexMobileApiFailure? get failure =>
      inteliexMobileApiFailureFromStatus(status);
}

abstract class InteliexPaginatedResponse<T>
    extends InteliexMobileApiResponseEnvelope {
  const InteliexPaginatedResponse({
    required super.status,
    required this.pageCount,
    required this.results,
  });

  final int pageCount;
  final List<T> results;
}

class InteliexExtensionEntry {
  const InteliexExtensionEntry({
    required this.name,
    required this.extension,
  });

  final String name;
  final String extension;

  factory InteliexExtensionEntry.fromJson(Map<String, dynamic> json) {
    return InteliexExtensionEntry(
      name: _readString(json, const ['name']),
      extension: _readString(json, const ['extens', 'extension', 'exten']),
    );
  }
}

class InteliexExtListResponse extends InteliexPaginatedResponse<InteliexExtensionEntry> {
  const InteliexExtListResponse({
    required super.status,
    required super.pageCount,
    required super.results,
  });

  factory InteliexExtListResponse.fromJson(Map<String, dynamic> json) {
    return InteliexExtListResponse(
      status: _readString(json, const ['status']),
      pageCount: _readInt(json['page_count']),
      results: _decodeList(json['results'], InteliexExtensionEntry.fromJson),
    );
  }
}

class InteliexPhoneBookEntry {
  const InteliexPhoneBookEntry({
    required this.recordId,
    required this.nameCompany,
    required this.registerName,
    required this.phoneNumber,
    required this.phoneNumber2,
    required this.phoneNumber3,
    required this.mobilePhone,
    required this.mobilePhone2,
    required this.faxNumber,
    required this.comment,
    required this.email,
    required this.email2,
    required this.address,
    required this.speedDial,
    required this.speedDialChoice,
    required this.speedDial2,
    required this.speedDialChoice2,
  });

  final String recordId;
  final String nameCompany;
  final String registerName;
  final String phoneNumber;
  final String phoneNumber2;
  final String phoneNumber3;
  final String mobilePhone;
  final String mobilePhone2;
  final String faxNumber;
  final String comment;
  final String email;
  final String email2;
  final String address;
  final String speedDial;
  final String speedDialChoice;
  final String speedDial2;
  final String speedDialChoice2;

  factory InteliexPhoneBookEntry.fromJson(Map<String, dynamic> json) {
    return InteliexPhoneBookEntry(
      recordId: _readString(json, const ['recordid']),
      nameCompany: _readString(json, const ['name_company']),
      registerName: _readString(json, const ['register_name']),
      phoneNumber: _readString(json, const ['phone_number']),
      phoneNumber2: _readString(json, const ['phone_number2']),
      phoneNumber3: _readString(json, const ['phone_number3']),
      mobilePhone: _readString(json, const ['mobile_phone', 'mobilephone']),
      mobilePhone2: _readString(json, const [
        'mobile_phone2',
        'mobilephone2',
      ]),
      faxNumber: _readString(json, const ['fax_number']),
      comment: _readString(json, const ['comment', 'coment']),
      email: _readString(json, const ['email']),
      email2: _readString(json, const ['email2']),
      address: _readString(json, const ['address']),
      speedDial: _readString(json, const ['speed_dial']),
      speedDialChoice: _readString(json, const ['speed_dial_choice']),
      speedDial2: _readString(json, const ['speed_dial_2']),
      speedDialChoice2: _readString(json, const ['speed_dial_choice_2']),
    );
  }
}

class InteliexPhoneBookResponse extends InteliexPaginatedResponse<InteliexPhoneBookEntry> {
  const InteliexPhoneBookResponse({
    required super.status,
    required super.pageCount,
    required super.results,
  });

  factory InteliexPhoneBookResponse.fromJson(Map<String, dynamic> json) {
    return InteliexPhoneBookResponse(
      status: _readString(json, const ['status']),
      pageCount: _readInt(json['page_count']),
      results: _decodeList(json['results'], InteliexPhoneBookEntry.fromJson),
    );
  }
}

class InteliexPersonalPhoneBookResponse
    extends InteliexPaginatedResponse<InteliexPhoneBookEntry> {
  const InteliexPersonalPhoneBookResponse({
    required super.status,
    required super.pageCount,
    required super.results,
  });

  factory InteliexPersonalPhoneBookResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return InteliexPersonalPhoneBookResponse(
      status: _readString(json, const ['status']),
      pageCount: _readInt(json['page_count']),
      results: _decodeList(json['results'], InteliexPhoneBookEntry.fromJson),
    );
  }
}

class InteliexPersonalPhoneBookSearchResponse
    extends InteliexPaginatedResponse<InteliexPhoneBookEntry> {
  const InteliexPersonalPhoneBookSearchResponse({
    required super.status,
    required super.pageCount,
    required super.results,
  });

  factory InteliexPersonalPhoneBookSearchResponse.fromJson(
    Map<String, dynamic> json,
  ) {
    return InteliexPersonalPhoneBookSearchResponse(
      status: _readString(json, const ['status']),
      pageCount: _readInt(json['page_count']),
      results: _decodeList(json['results'], InteliexPhoneBookEntry.fromJson),
    );
  }
}

class InteliexMutationResponse extends InteliexMobileApiResponseEnvelope {
  const InteliexMutationResponse({
    required super.status,
    this.expectedAction,
  });

  final InteliexMobileApiAction? expectedAction;

  bool get isExpectedSuccess {
    if (expectedAction == null) {
      return isSuccess;
    }

    return status == expectedAction!.successStatus;
  }

  factory InteliexMutationResponse.fromJson(
    Map<String, dynamic> json, {
    InteliexMobileApiAction? expectedAction,
  }) {
    return InteliexMutationResponse(
      status: _readString(json, const ['status']),
      expectedAction: expectedAction,
    );
  }
}

class InteliexShortCodes {
  const InteliexShortCodes({
    required this.outboundPrefix,
    required this.pickupExtension,
    required this.blindTransfer,
  });

  final String outboundPrefix;
  final String pickupExtension;
  final String blindTransfer;

  factory InteliexShortCodes.fromJson(Map<String, dynamic> json) {
    return InteliexShortCodes(
      outboundPrefix: _readString(json, const ['outbound_prefix']),
      pickupExtension: _readString(json, const ['pickup_exten']),
      blindTransfer: _readString(json, const ['blindxfer']),
    );
  }
}

class InteliexShortCodesResponse extends InteliexMobileApiResponseEnvelope {
  const InteliexShortCodesResponse({
    required super.status,
    required this.shortCodes,
  });

  final InteliexShortCodes shortCodes;

  factory InteliexShortCodesResponse.fromJson(Map<String, dynamic> json) {
    return InteliexShortCodesResponse(
      status: _readString(json, const ['status']),
      shortCodes: InteliexShortCodes.fromJson(_readMap(json['results'])),
    );
  }
}

class InteliexVoiceMailEntry {
  const InteliexVoiceMailEntry({
    required this.caller,
    required this.dateLabel,
    required this.recordedAt,
    required this.durationSeconds,
    required this.audioUrl,
    required this.recordId,
  });

  final String caller;
  final String dateLabel;
  final DateTime? recordedAt;
  final int durationSeconds;
  final String audioUrl;
  final String recordId;

  factory InteliexVoiceMailEntry.fromJson(Map<String, dynamic> json) {
    final dateLabel = _readString(json, const ['date']);

    return InteliexVoiceMailEntry(
      caller: _readString(json, const ['caller']),
      dateLabel: dateLabel,
      recordedAt: _parseDateTimeLabel(dateLabel),
      durationSeconds: _readInt(json['duration']),
      audioUrl: _readString(json, const ['audio_url']),
      recordId: _readString(json, const ['recordid']),
    );
  }
}

class InteliexVoiceMailResponse extends InteliexMobileApiResponseEnvelope {
  const InteliexVoiceMailResponse({
    required super.status,
    required this.results,
  });

  final List<InteliexVoiceMailEntry> results;

  factory InteliexVoiceMailResponse.fromJson(Map<String, dynamic> json) {
    return InteliexVoiceMailResponse(
      status: _readString(json, const ['status']),
      results: _decodeList(json['results'], InteliexVoiceMailEntry.fromJson),
    );
  }
}

String _readString(Map<String, dynamic> json, List<String> keys) {
  var sawEmptyValue = false;

  for (final key in keys) {
    final value = json[key];
    if (value == null) {
      continue;
    }

    final normalizedValue = value.toString().trim();
    if (normalizedValue.isNotEmpty) {
      return normalizedValue;
    }

    sawEmptyValue = true;
  }

  return sawEmptyValue ? '' : '';
}

int _readInt(Object? value, {int fallback = 0}) {
  if (value is int) {
    return value;
  }

  if (value is num) {
    return value.toInt();
  }

  if (value == null) {
    return fallback;
  }

  return int.tryParse(value.toString().trim()) ?? fallback;
}

Map<String, dynamic> _readMap(Object? value) {
  if (value is Map) {
    return Map<String, dynamic>.from(value);
  }

  return <String, dynamic>{};
}

List<T> _decodeList<T>(
  Object? value,
  T Function(Map<String, dynamic> json) decoder,
) {
  if (value is! List) {
    return <T>[];
  }

  final results = <T>[];
  for (final item in value) {
    if (item is! Map) {
      continue;
    }

    results.add(decoder(Map<String, dynamic>.from(item)));
  }

  return List<T>.unmodifiable(results);
}

DateTime? _parseDateTimeLabel(String value) {
  final trimmedValue = value.trim();
  if (trimmedValue.isEmpty) {
    return null;
  }

  return DateTime.tryParse(trimmedValue.replaceFirst(' ', 'T'));
}