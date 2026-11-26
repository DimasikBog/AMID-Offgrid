import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/emergency.dart';
import '../services/emergency_actions.dart';
import '../services/emergency_voice.dart';
import '../widgets/common.dart';
import '../widgets/emergency_confirmation_panel.dart';
import '../widgets/emergency_details.dart';

class EmergencyScreen extends StatefulWidget {
  const EmergencyScreen({
    super.key,
    this.actions,
    this.voice,
    this.initialTraining = false,
  });
  final EmergencyActions? actions;
  final EmergencyVoice? voice;
  final bool initialTraining;
  @override
  State<EmergencyScreen> createState() => _EmergencyScreenState();
}

class _EmergencyScreenState extends State<EmergencyScreen>
    with WidgetsBindingObserver {
  late final _actions = widget.actions ?? EmergencyActions();
  late final _voice = widget.voice ?? EmergencyVoice();
  final _gate = EmergencyConfirmation();
  final _scroll = ScrollController();
  final _description = TextEditingController(),
      _place = TextEditingController(),
      _name = TextEditingController(),
      _people = TextEditingController();
  EmergencyRegion _region = EmergencyRegion.europeanUnion;
  EmergencyService _service = EmergencyService.all;
  ConfirmationLanguage _language = ConfirmationLanguage.ukrainian;
  EmergencyFix? _fix;
  late bool _training = widget.initialTraining;
  bool _foreground = true,
      _locating = false,
      _listening = false,
      _launching = false,
      _cannotSpeak = false;
  int _locationEpoch = 0;
  String _lastDraft = '';
  String _status = '',
      _locationStatus =
          'GPS ще не визначено. Телефонувати можна без координат.';
  Timer? _ticker, _voiceTimer;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    scheduleMicrotask(() {
      if (mounted) unawaited(_refresh(requestPermission: false));
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      final ticket = _gate.current;
      if (ticket != null && !_gate.valid(ticket, DateTime.now())) {
        _cancel();
        _status = 'Час підтвердження минув. Натисни SOS ще раз.';
      }
      if (_fix != null || ticket != null) setState(() {});
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      final wasArmed = _gate.current != null;
      _locationEpoch++;
      _cancel();
      if (wasArmed) {
        setState(
          () => _status = 'Підтвердження скасовано після переривання. Якщо надавався дозвіл, заверши його й натисни SOS повторно.',
        );
      }
    }
  }

  void _cancel() {
    _gate.cancel();
    _voiceTimer?.cancel();
    unawaited(_voice.cancel());
    if (mounted) setState(() => _listening = false);
  }

  void _setTraining(bool value) {
    _cancel();
    setState(() {
      _training = value;
      _lastDraft = '';
      _status = value
          ? 'ТРЕНУВАННЯ ввімкнено. SOS не запускає виклики чи SMS.'
          : 'Тренування вимкнено. Далі — реальні звернення після підтвердження.';
    });
  }

  Future<void> _refresh({bool requestPermission = true}) async {
    if (_locating) return;
    _cancel();
    final epoch = ++_locationEpoch;
    setState(() => _locating = true);
    try {
      final fix = await _actions.locate(
        stillActive: () => mounted && _foreground && epoch == _locationEpoch,
        requestPermission: requestPermission,
      );
      if (mounted && _foreground && epoch == _locationEpoch) {
        setState(() {
          if (_gate.current?.action == EmergencyAction.sms) {
            _cancel();
            _status = 'Координати оновлено. Підтверди SMS з новою позицією.';
          }
          _fix = fix;
          _locationStatus = 'Позицію визначено';
        });
      }
    } catch (_) {
      if (mounted && epoch == _locationEpoch) {
        setState(
          () => _locationStatus = 'GPS не оновлено: перевір дозвіл і геолокацію. Можна телефонувати без GPS.',
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _arm(EmergencyAction action) {
    if (_launching || !_foreground) return;
    final countText = _people.text.trim();
    final count = int.tryParse(countText);
    if (action == EmergencyAction.sms &&
        countText.isNotEmpty &&
        (count == null || count < 1 || count > 999)) {
      toast(
        context,
        'Вкажи кількість людей від 1 до 999 або залиш поле порожнім.',
      );
      return;
    }
    FocusManager.instance.primaryFocus?.unfocus();
    _cancel();
    setState(() {
      _status = '';
      _gate.arm(
        action: action,
        number: action == EmergencyAction.sms
            ? '112'
            : emergencyNumber(_region, _service),
        message: action == EmergencyAction.call
            ? ''
            : emergencyMessage(
                service: _service,
                fix: _fix,
                description: _description.text,
                place: _place.text,
                name: _name.text,
                cannotSpeak: _cannotSpeak,
                people: count,
              ),
        training: _training,
        language: _language,
        now: DateTime.now(),
      );
    });
    if (action == EmergencyAction.sms) _lastDraft = _gate.current!.message;
    if (_scroll.hasClients) _scroll.jumpTo(0);
  }

  Future<void> _confirm(
    EmergencyTicket ticket, {
    String? words,
    bool finalResult = true,
  }) async {
    if (!_foreground ||
        _launching ||
        !_gate.consume(
          ticket,
          DateTime.now(),
          spoken: words,
          finalResult: finalResult,
        )) {
      return;
    }
    _voiceTimer?.cancel();
    unawaited(_voice.cancel());
    setState(() {
      _listening = false;
      _launching = true;
      _status = '';
    });
    try {
      if (ticket.training) {
        setState(
          () =>
              _status = 'ТРЕНУВАННЯ завершено. Виклики та SMS не запускалися.',
        );
      } else {
        final result = await _actions.perform(
          ticket,
          stillActive: () => mounted && _foreground,
        );
        if (mounted) {
          setState(
            () => _status = switch (result) {
              EmergencyHandoff.phoneOpened =>
                'Відкрито телефон. Заверши виклик ${ticket.number} у вікні телефона та дочекайся відповіді оператора. Доставлення координат AMID не підтверджує.',
              EmergencyHandoff.messageOpened => 'Відкрито SMS з текстом. Перевір координати й номер 112, допиши потрібне та натисни «Надіслати». AMID не знає, чи повідомлення доставлено службі.',
              EmergencyHandoff.copiedMessageOpened => 'Текст скопійовано, SMS відкрито. Встав текст, перевір номер 112 та натисни «Надіслати». Доставлення не підтверджено.',
            },
          );
        }
      }
    } catch (_) {
      if (mounted) {
        setState(
          () => _status = ticket.action == EmergencyAction.sms
              ? 'SMS не відкрито. Відкрий повідомлення вручну на 112 (Чехія), встав підготовлений текст і самостійно надішли. Доставлення не підтверджено.'
              : 'Не вдалося відкрити телефон. Набери ${ticket.number} вручну; координати можна скопіювати нижче.',
        );
      }
    } finally {
      if (mounted) setState(() => _launching = false);
    }
  }

  Future<void> _listen(EmergencyTicket ticket) async {
    if (_listening || !_foreground || !_gate.valid(ticket, DateTime.now())) {
      return;
    }
    setState(() => _listening = true);
    _voiceTimer = Timer(const Duration(seconds: 12), () {
      if (mounted && identical(_gate.current, ticket)) {
        unawaited(_voice.cancel());
        setState(() {
          _listening = false;
          _status = 'Голос не підтверджено. Спробуй ще раз або натисни кнопку.';
        });
      }
    });
    final available = await _voice.start(
      ticket.language,
      (words, finalResult) {
        if (mounted && _foreground && identical(_gate.current, ticket)) {
          if (finalResult &&
              normalizedConfirmation(words) !=
                  normalizedConfirmation(ticket.phrase)) {
            _voiceTimer?.cancel();
            unawaited(_voice.cancel());
            setState(() {
              _listening = false;
              _status = 'Фраза не збігається. Повтори її повністю або підтверди кнопкою.';
            });
            return;
          }
          unawaited(_confirm(ticket, words: words, finalResult: finalResult));
        }
      },
      () {
        if (mounted && identical(_gate.current, ticket)) {
          _voiceTimer?.cancel();
          unawaited(_voice.cancel());
          setState(() {
            _listening = false;
            _status =
                'Голос недоступний або фразу не розпізнано. Підтверди кнопкою.';
          });
        }
      },
    );
    if (!available && mounted && identical(_gate.current, ticket)) {
      _voiceTimer?.cancel();
      setState(() {
        _listening = false;
        _status = 'Локальне розпізнавання недоступне або потрібен дозвіл. Підтверди кнопкою; після надання дозволу можна спробувати голос знову.';
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ticker?.cancel();
    _voiceTimer?.cancel();
    _gate.cancel();
    _locationEpoch++;
    unawaited(_voice.cancel());
    _scroll.dispose();
    _description.dispose();
    _place.dispose();
    _name.dispose();
    _people.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final ticket = _gate.current;
    return Scaffold(
      appBar: AppBar(
        actions: [
          IconButton(
            key: const ValueKey('sos-test-mode'),
            tooltip: _training
                ? 'Вийти з тренування SOS'
                : 'Тренування SOS · без зв’язку',
            icon: Icon(_training ? Icons.school : Icons.school_outlined),
            onPressed: _launching ? null : () => _setTraining(!_training),
          ),
        ],
        title: const Text(
          'SOS · Екстрена допомога',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
          child: FilledButton.icon(
            key: ValueKey(ticket == null ? 'sos-call' : 'sos-confirm'),
            style: FilledButton.styleFrom(
              backgroundColor: colors.error,
              foregroundColor: colors.onError,
              padding: const EdgeInsets.all(18),
            ),
            onPressed: _launching
                ? null
                : ticket == null
                ? () => _arm(EmergencyAction.call)
                : () => _confirm(ticket),
            icon: Icon(ticket == null ? Icons.sos : Icons.check),
            label: Text(
              ticket == null
                  ? '${_training ? 'Тренування · ' : ''}SOS · Виклик ${emergencyNumber(_region, _service)}'
                  : ticket.training
                  ? 'Підтвердити тренування'
                  : 'Підтверджую ${ticket.action == EmergencyAction.sms ? 'SMS' : 'виклик'} · ${ticket.number}',
            ),
          ),
        ),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: ListView(
            controller: _scroll,
            padding: const EdgeInsets.all(20),
            children: [
              if (ticket != null)
                EmergencyConfirmationPanel(
                  ticket: ticket,
                  listening: _listening,
                  voice: () => _listen(ticket),
                  cancel: _cancel,
                ),
              if (_status.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Semantics(liveRegion: true, child: Text(_status)),
                ),
              Text(
                _training ? 'Тренування SOS' : 'Допомога поруч',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
              const SizedBox(height: 8),
              const Text(
                'Виклик відкриває телефон. SMS готує координати, але потребує натискання «Надіслати». Не чекай GPS, якщо допомога потрібна негайно.',
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<EmergencyRegion>(
                key: const ValueKey('sos-region'),
                initialValue: _region,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Де ти зараз? Обери країну',
                ),
                items: const [
                  DropdownMenuItem(
                    value: EmergencyRegion.czechia,
                    child: Text('Чехія'),
                  ),
                  DropdownMenuItem(
                    value: EmergencyRegion.europeanUnion,
                    child: Text('ЄС · загальний номер 112'),
                  ),
                ],
                onChanged: _launching
                    ? null
                    : (value) {
                        if (value != null) {
                          _cancel();
                          setState(() => _region = value);
                        }
                      },
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final entry in {
                    EmergencyService.all: 'Усі служби',
                    EmergencyService.police: 'Поліція',
                    EmergencyService.fire: 'Пожежники',
                    EmergencyService.medical: 'Медики',
                  }.entries)
                    ChoiceChip(
                      label: Text(entry.value),
                      selected: _service == entry.key,
                      onSelected: _launching
                          ? null
                          : (_) {
                              _cancel();
                              setState(() => _service = entry.key);
                            },
                    ),
                ],
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                key: const ValueKey('sos-sms'),
                onPressed:
                    _launching ||
                        _region != EmergencyRegion.czechia ||
                        (!_training && !_actions.smsSupported)
                    ? null
                    : () => _arm(EmergencyAction.sms),
                icon: const Icon(Icons.sms_outlined),
                label: const Text('SMS з координатами · 112 · Чехія'),
              ),
              if (_region != EmergencyRegion.czechia)
                const Text(
                  'SMS на 112 тут не пропонується: правила прийому повідомлень різняться між країнами. За межами ЄС перевір місцевий екстрений номер.',
                ),
              const SizedBox(height: 16),
              if (_launching) const LinearProgressIndicator(),
              if (_lastDraft.isNotEmpty && ticket == null) ...[
                SelectableText(_lastDraft),
                TextButton.icon(
                  onPressed: () => guarded(context, () async {
                    await Clipboard.setData(ClipboardData(text: _lastDraft));
                    if (context.mounted) {
                      toast(context, 'Текст SOS скопійовано');
                    }
                  }),
                  icon: const Icon(Icons.copy),
                  label: const Text('Копіювати текст SOS'),
                ),
              ],
              EmergencyLocationPanel(
                fix: _fix,
                status: _locationStatus,
                locating: _locating,
                refresh: _refresh,
              ),
              EmergencyDetailsForm(
                place: _place,
                description: _description,
                name: _name,
                people: _people,
                cannotSpeak: _cannotSpeak,
                changed: _cancel,
                cannotSpeakChanged: (value) {
                  _cancel();
                  setState(() => _cannotSpeak = value);
                },
              ),
              const Section('Підтвердження та тренування'),
              DropdownButtonFormField<ConfirmationLanguage>(
                initialValue: _language,
                isExpanded: true,
                decoration: const InputDecoration(
                  labelText: 'Мова точної голосової фрази',
                ),
                items: const [
                  DropdownMenuItem(
                    value: ConfirmationLanguage.ukrainian,
                    child: Text('Українська'),
                  ),
                  DropdownMenuItem(
                    value: ConfirmationLanguage.czech,
                    child: Text('Čeština'),
                  ),
                  DropdownMenuItem(
                    value: ConfirmationLanguage.english,
                    child: Text('English'),
                  ),
                ],
                onChanged: (value) {
                  if (value != null) {
                    _cancel();
                    setState(() => _language = value);
                  }
                },
              ),
              SwitchListTile(
                key: const ValueKey('sos-training'),
                contentPadding: EdgeInsets.zero,
                title: const Text('Тренування · без викликів і SMS'),
                subtitle: const Text(
                  'Перевір послідовність без звернення до екстрених служб.',
                ),
                value: _training,
                onChanged: _launching ? null : _setTraining,
              ),
              TextButton(
                onPressed: () => launchUrl(
                  Uri.parse(
                    'https://hzscr.gov.cz/tisnova-komunikace-prostrednictvim-sms-2',
                  ),
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('Правила екстрених SMS у Чехії · HZS'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
