enum EmergencyRegion { czechia, europeanUnion }

enum EmergencyService { all, police, fire, medical }

enum EmergencyAction { call, sms }

enum ConfirmationLanguage { ukrainian, czech, english }

String emergencyNumber(EmergencyRegion region, EmergencyService service) =>
    region == EmergencyRegion.europeanUnion
    ? '112'
    : switch (service) {
        EmergencyService.all => '112',
        EmergencyService.police => '158',
        EmergencyService.fire => '150',
        EmergencyService.medical => '155',
      };

const emergencyNumbers = {'112', '150', '155', '158'};

class EmergencyFix {
  EmergencyFix(
    this.latitude,
    this.longitude,
    this.accuracy,
    DateTime measuredAt,
  ) : measuredAt = measuredAt.toUtc() {
    if (!latitude.isFinite ||
        latitude.abs() > 90 ||
        !longitude.isFinite ||
        longitude.abs() > 180 ||
        !accuracy.isFinite ||
        accuracy < 0 ||
        accuracy > 1000000) {
      throw const FormatException('Некоректна GPS-позиція.');
    }
  }
  final double latitude, longitude, accuracy;
  final DateTime measuredAt;
  String get coordinates =>
      '${latitude.toStringAsFixed(6)}, ${longitude.toStringAsFixed(6)}';
  bool fresh(DateTime now) =>
      now.difference(measuredAt) >= const Duration(seconds: -5) &&
      now.difference(measuredAt) <= const Duration(minutes: 2);
}

String emergencyMessage({
  required EmergencyService service,
  EmergencyFix? fix,
  String description = '',
  String place = '',
  String name = '',
  int? people,
  bool cannotSpeak = false,
  DateTime? createdAt,
}) {
  if (people != null && (people < 1 || people > 999)) {
    throw const FormatException('Кількість людей: 1–999.');
  }
  String clean(String value, int limit) => String.fromCharCodes(
    value.replaceAll(RegExp(r'[\x00-\x1f\x7f]'), ' ').trim().runes.take(limit),
  );
  final kind = switch (service) {
    EmergencyService.all => 'IZS',
    EmergencyService.police => 'policie',
    EmergencyService.fire => 'hasici',
    EmergencyService.medical => 'zdravotni pomoc',
  };
  return [
    'SOS. Potrebuji pomoc nyni: $kind.',
    'Zprava pripravena UTC: ${(createdAt ?? DateTime.now()).toUtc().toIso8601String()}.',
    if (fix != null)
      'GPS WGS84: ${fix.coordinates}. ${fix.accuracy > 0 ? 'Presnost +/-${fix.accuracy.ceil()} m.' : 'Presnost neni znama.'} Poloha zjistena UTC: ${fix.measuredAt.toIso8601String()}.',
    if (fix == null) 'GPS nedostupne. Doplnte misto.',
    if (place.trim().isNotEmpty) 'Misto: ${clean(place, 150)}.',
    if (description.trim().isNotEmpty) 'Udalost: ${clean(description, 200)}.',
    if (people != null) 'Osob: $people.',
    if (name.trim().isNotEmpty) 'Jmeno: ${clean(name, 80)}.',
    if (cannotSpeak) 'Nemohu mluvit. Odpovidejte prosim SMS.',
  ].join(' ');
}

String confirmationPhrase(
  EmergencyAction action,
  ConfirmationLanguage language,
) => switch ((action, language)) {
  (EmergencyAction.call, ConfirmationLanguage.ukrainian) =>
    'Підтверджую виклик допомоги',
  (EmergencyAction.sms, ConfirmationLanguage.ukrainian) =>
    'Підтверджую екстрене повідомлення',
  (EmergencyAction.call, ConfirmationLanguage.czech) =>
    'Potvrzuji volání pomoci',
  (EmergencyAction.sms, ConfirmationLanguage.czech) =>
    'Potvrzuji nouzovou zprávu',
  (EmergencyAction.call, ConfirmationLanguage.english) =>
    'Confirm emergency call',
  (EmergencyAction.sms, ConfirmationLanguage.english) =>
    'Confirm emergency message',
};
String normalizedConfirmation(String value) => value
    .toLowerCase()
    .replaceAll(RegExp(r'''[.,!?:;"'«»]'''), '')
    .trim()
    .replaceAll(RegExp(r'\s+'), ' ');

class EmergencyTicket {
  EmergencyTicket(
    this.action,
    this.number,
    this.message,
    this.training,
    this.language,
    this.expiresAt,
  );
  final EmergencyAction action;
  final String number, message;
  final bool training;
  final ConfirmationLanguage language;
  final DateTime expiresAt;
  String get phrase => confirmationPhrase(action, language);
}

/// One foreground, explicit activation; no ambient listening or fuzzy matching.
class EmergencyConfirmation {
  EmergencyTicket? current;
  EmergencyTicket arm({
    required EmergencyAction action,
    required String number,
    required String message,
    required bool training,
    required ConfirmationLanguage language,
    required DateTime now,
  }) {
    if (!emergencyNumbers.contains(number) || message.length > 2000) {
      throw const FormatException('Некоректна екстрена дія.');
    }
    return current = EmergencyTicket(
      action,
      number,
      message,
      training,
      language,
      now.add(const Duration(minutes: 1)),
    );
  }

  bool valid(EmergencyTicket ticket, DateTime now) =>
      identical(current, ticket) && !now.isAfter(ticket.expiresAt);
  bool consume(
    EmergencyTicket ticket,
    DateTime now, {
    String? spoken,
    bool finalResult = true,
  }) {
    if (!valid(ticket, now)) return false;
    if (spoken != null &&
        (!finalResult ||
            normalizedConfirmation(spoken) !=
                normalizedConfirmation(ticket.phrase))) {
      return false;
    }
    current = null;
    return true;
  }

  void cancel() {
    current = null;
  }
}
