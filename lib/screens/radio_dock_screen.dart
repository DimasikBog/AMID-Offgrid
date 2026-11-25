import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';

import '../models/data.dart';
import '../models/mesh_wire.dart';
import '../services/radio_dock.dart';
import '../services/store.dart';
import '../widgets/common.dart';

class RadioDockScreen extends StatefulWidget {
  const RadioDockScreen({
    super.key,
    required this.service,
    required this.store,
  });
  final RadioDockService service;
  final AppStore store;
  @override
  State<RadioDockScreen> createState() => _RadioDockScreenState();
}

class _RadioDockScreenState extends State<RadioDockScreen>
    with WidgetsBindingObserver {
  final _text = TextEditingController(), _destination = TextEditingController();
  bool _broadcast = false, _antennaReady = false;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      unawaited(widget.service.stop());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(widget.service.stop());
    _text.dispose();
    _destination.dispose();
    super.dispose();
  }

  Future<void> _coordinate() async {
    final pins = List<Pin>.of(widget.store.pins);
    if (pins.isEmpty) {
      toast(context, 'Спочатку збережи точку на карті.');
      return;
    }
    final pin = await showModalBottomSheet<Pin>(
      context: context,
      isScrollControlled: true,
      builder: (context) => SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * .65,
          child: ListView.builder(
            itemCount: pins.length + 1,
            itemBuilder: (context, i) {
              if (i == 0) {
                return const ListTile(
                  title: Text('Вибери координати для повідомлення'),
                );
              }
              final pin = pins[i - 1];
              return ListTile(
                title: Text(pin.name),
                subtitle: Text(
                  '${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}',
                ),
                onTap: () => Navigator.pop(context, pin),
              );
            },
          ),
        ),
      ),
    );
    if (!mounted || pin == null) return;
    final value =
        '${_text.text}${_text.text.isEmpty ? '' : '\n'}${pin.latitude.toStringAsFixed(5)}, ${pin.longitude.toStringAsFixed(5)}';
    if (utf8.encode(value).length > meshTextLimit) {
      toast(context, 'Скороти текст, щоб координати помістилися у 200 байтів.');
      return;
    }
    setState(() => _text.text = value);
  }

  Future<void> _send() => guarded(context, () async {
    final value = _text.text;
    final to = _broadcast
        ? meshBroadcast
        : checkedMeshDestination(_destination.text.trim());
    await widget.service.sendText(value, to: to);
    if (mounted && _text.text == value) setState(_text.clear);
  });
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([widget.service, widget.store]),
    builder: (context, _) {
      final radio = widget.service, transport = radio.transport;
      final bytes = utf8.encode(_text.text).length;
      final inbox = widget.store.messages
          .where((m) => m.direction == 'in' && m.id.startsWith('mesh-'))
          .toList()
          .reversed
          .take(20);
      return Scaffold(
        appBar: AppBar(
          title: const Text(
            'Радіочохол LoRa',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Pill(
                'Технічний прототип · фізичний тест попереду',
                warning: true,
              ),
              const SizedBox(height: 12),
              Panel(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      radio.ready
                          ? radio.status
                          : transport.scanning || !radio.busy
                          ? transport.status
                          : radio.status,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Телефон → Bluetooth → власний LoRa-модуль → інший сумісний радіовузол. Антена підключається до модуля. Інтернет потребує окремого шлюзу.',
                    ),
                    const SizedBox(height: 12),
                    if (!radio.supported)
                      const Text(
                        'Підключення модуля — у встановленому Android/iPhone застосунку. Вебверсія показує цей екран без доступу до радіо.',
                      )
                    else
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          FilledButton.tonalIcon(
                            onPressed: radio.busy || transport.connected
                                ? null
                                : () => guarded(context, radio.scan),
                            icon: const Icon(Icons.bluetooth_searching),
                            label: const Text('Знайти модуль'),
                          ),
                          OutlinedButton(
                            onPressed: () => guarded(context, radio.stop),
                            child: const Text('Від’єднати'),
                          ),
                        ],
                      ),
                    for (final device in transport.devices)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(device.name),
                        subtitle: Text('BLE RSSI ${device.rssi} dBm'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: radio.busy || radio.ready
                            ? null
                            : () => guarded(
                                context,
                                () => radio.connect(device.id),
                              ),
                      ),
                  ],
                ),
              ),
              const Section('Підготовка модуля'),
              const Text(
                'Перший варіант: LILYGO T3-S3 + SX1262 868 MHz, Meshtastic 2.7.26. Перед увімкненням підключи антену. В офіційному клієнті налаштуй EU868, однаковий modem preset на обох вузлах і власний випадковий 32-байтовий ключ каналу. Вимкни MQTT uplink. Закрий інший BLE-клієнт і підтвердь PIN з екрана модуля.',
              ),
              if (radio.ready) ...[
                const Section('Стан радіо'),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    Pill(meshNodeId(radio.localNode)),
                    Pill('FW ${radio.firmware}'),
                    if (radio.lastRadioRssi != null)
                      Pill('LoRa RSSI ${radio.lastRadioRssi} dBm'),
                    if (radio.lastRadioSnr != null)
                      Pill(
                        'LoRa SNR ${radio.lastRadioSnr!.toStringAsFixed(1)} dB',
                      ),
                    Pill(
                      radio.region == 3 ? 'EU868' : 'Регіон ${radio.region}',
                      warning: radio.region != 3,
                    ),
                    Pill(
                      radio.txEnabled ? 'TX увімкнено' : 'TX вимкнено',
                      warning: !radio.txEnabled,
                    ),
                    if (radio.ownNode?.battery != null)
                      Pill(
                        radio.ownNode!.battery! > 100
                            ? 'Зовнішнє живлення'
                            : 'Батарея ${radio.ownNode!.battery}%',
                      ),
                  ],
                ),
                const SizedBox(height: 12),
                InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Канал радіомодуля',
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      value: radio.channels.containsKey(radio.selectedChannel)
                          ? radio.selectedChannel
                          : null,
                      items: radio.channels.values
                          .map(
                            (c) => DropdownMenuItem(
                              value: c.index,
                              child: Text(
                                '${c.index}: ${c.name.isEmpty ? 'Без назви' : c.name}',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          )
                          .toList(),
                      onChanged: radio.sending
                          ? null
                          : (v) {
                              if (v != null) radio.chooseChannel(v);
                            },
                    ),
                  ),
                ),
                if (!radio.canSend && !radio.sending)
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Text(
                      'Передавання потребує EU868, TX, Meshtastic 2.7 та власного 32-байтового ключа без MQTT uplink. Ключі не зберігаються в AMID.',
                    ),
                  ),
              ],
              const Section('Коротке повідомлення'),
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                value: _antennaReady,
                onChanged: (v) => setState(() => _antennaReady = v ?? false),
                title: const Text('Антена підключена й розкладена'),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _broadcast,
                onChanged: radio.sending
                    ? null
                    : (v) => setState(() => _broadcast = v),
                title: const Text('Усім у вибраному каналі'),
                subtitle: const Text(
                  'Для розсилки немає підтвердження кожного адресата.',
                ),
              ),
              if (!_broadcast)
                TextField(
                  key: const ValueKey('radio-destination'),
                  controller: _destination,
                  decoration: const InputDecoration(
                    labelText: 'Адреса радіовузла',
                    hintText: '!1234abcd',
                  ),
                  maxLength: 9,
                ),
              const SizedBox(height: 12),
              TextField(
                key: const ValueKey('radio-message'),
                controller: _text,
                minLines: 2,
                maxLines: 5,
                maxLength: 200,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: 'Текст для LoRa',
                  helperText: '$bytes / 200 байтів UTF-8',
                  errorText: bytes > meshTextLimit
                      ? 'Скороти текст; кирилиця потребує більше байтів.'
                      : null,
                ),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  OutlinedButton.icon(
                    onPressed: _coordinate,
                    icon: const Icon(Icons.location_on_outlined),
                    label: const Text('Додати координати'),
                  ),
                  FilledButton.icon(
                    onPressed:
                        radio.canSend &&
                            _antennaReady &&
                            bytes > 0 &&
                            bytes <= meshTextLimit
                        ? _send
                        : null,
                    icon: const Icon(Icons.send),
                    label: const Text('Надіслати через LoRa'),
                  ),
                ],
              ),
              const Section('Вузли за останніми даними'),
              if (radio.nodes.isEmpty)
                const Text(
                  'Вузлів ще немає. Список не гарантує поточної радіодосяжності.',
                ),
              for (final node in radio.nodes.values.take(20))
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(
                    node.name.isEmpty ? meshNodeId(node.number) : node.name,
                  ),
                  subtitle: Text(
                    '${meshNodeId(node.number)}${node.viaMqtt ? ' · через MQTT' : ''}${node.latitude == null ? '' : '\n${node.latitude!.toStringAsFixed(5)}, ${node.longitude!.toStringAsFixed(5)}'}',
                  ),
                  onTap: node.number == radio.localNode
                      ? null
                      : () => setState(() {
                          _destination.text = meshNodeId(node.number);
                          _broadcast = false;
                        }),
                  trailing: node.latitude == null
                      ? null
                      : IconButton(
                          tooltip: 'Зберегти точку радіовузла',
                          icon: const Icon(Icons.add_location_alt_outlined),
                          onPressed: () => guarded(
                            context,
                            () => widget.store.savePin(
                              Pin(
                                'radio-${node.number}',
                                node.name.isEmpty
                                    ? meshNodeId(node.number)
                                    : boundedText(node.name, 100),
                                node.latitude!,
                                node.longitude!,
                              ),
                            ),
                          ),
                        ),
                ),
              if (radio.transmissions.isNotEmpty) ...[
                const Section('Передавання цього сеансу'),
                for (final sent in radio.transmissions.take(10))
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: Text(
                      sent.text,
                      maxLines: 3,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${sent.to == meshBroadcast ? 'Канал ${sent.channel}' : meshNodeId(sent.to)}\n${sent.state.label}',
                    ),
                  ),
              ],
              if (inbox.isNotEmpty) ...[
                const Section('Отримано через LoRa'),
                for (final message in inbox)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    title: SelectableText(message.body),
                    subtitle: Text(message.id),
                  ),
              ],
              const SizedBox(height: 12),
              const Text(
                'Короткі тексти й координати залишаються на цьому пристрої та входять у його резервну копію. Учасники зі спільним ключем можуть читати канал. Закриття екрана або згортання застосунку від’єднує AMID; власні передачі прошивки радіо налаштовуються окремо.',
              ),
            ],
          ),
        ),
      );
    },
  );
}
