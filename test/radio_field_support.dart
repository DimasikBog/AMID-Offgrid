import 'package:amid_offgrid/models/radio_field_test.dart';

RadioFieldSession session({
  String id = '00000000-0000-4000-8000-000000000000',
  int Function()? elapsed,
}) => RadioFieldSession(
  id: id,
  createdAt: '2026-11-25T12:00:00.000Z',
  appVersion: '0.8.1',
  firmware: '2.7.26.test',
  region: 3,
  elapsedMs: elapsed ?? () => 100,
);
