class AppearancePreset {
  const AppearancePreset(
    this.id,
    this.name,
    this.description,
    this.seed,
    this.darkSurface,
    this.lightSurface,
    this.darkAccent,
    this.lightAccent, {
    this.radius = 14,
  });
  final String id, name, description;
  final int seed, darkSurface, lightSurface, darkAccent, lightAccent;
  final double radius;
}

const appearancePresets = [
  AppearancePreset(
    'forest',
    'AMID · Природа',
    'Спокійні зелені кольори',
    0xff326550,
    0xff101b19,
    0xfff7f8f4,
    0xffb5e6c8,
    0xff265b45,
  ),
  AppearancePreset(
    'cyberpunk',
    'Кіберпанк',
    'Неон, графіт і чіткі кути',
    0xff007f86,
    0xff080e1a,
    0xffedf8fa,
    0xff5df2ed,
    0xff00676d,
    radius: 4,
  ),
  AppearancePreset(
    'classic',
    'Класика',
    'Теплий папір і темне чорнило',
    0xff4d5369,
    0xff1b1b24,
    0xfffaf5ea,
    0xffe3c99b,
    0xff293750,
    radius: 7,
  ),
  AppearancePreset(
    'ocean',
    'Океан',
    'Блакитний простір і свіже повітря',
    0xff1266a0,
    0xff0a1b2a,
    0xfff0f7fd,
    0xff91caff,
    0xff145d91,
  ),
  AppearancePreset(
    'midnight',
    'Опівніч',
    'Глибокий синій і срібло',
    0xff53669c,
    0xff0b1020,
    0xfff1f3fa,
    0xffb4c5ff,
    0xff3d5182,
    radius: 10,
  ),
  AppearancePreset(
    'sand',
    'Пустеля',
    'Пісок, глина й сонячні відтінки',
    0xff8e633a,
    0xff261d15,
    0xfffcf6e9,
    0xffedc38a,
    0xff79502b,
  ),
  AppearancePreset(
    'rose',
    'Сакура',
    'М’які рожеві й теплі сірі',
    0xff9c476c,
    0xff26171f,
    0xfffff3f7,
    0xffffb4cf,
    0xff913559,
    radius: 20,
  ),
  AppearancePreset(
    'mono',
    'Монохром',
    'Мінімум кольору, максимум ясності',
    0xff585858,
    0xff121212,
    0xfffafafa,
    0xffeeeeee,
    0xff252525,
    radius: 6,
  ),
  AppearancePreset(
    'ember',
    'Жар',
    'Теплий помаранчевий і темний метал',
    0xffa64422,
    0xff211612,
    0xfffff4ed,
    0xffffb18a,
    0xff9b3c1b,
    radius: 10,
  ),
  AppearancePreset(
    'lavender',
    'Лаванда',
    'Лілові відтінки й легкі поверхні',
    0xff7255a2,
    0xff1c1629,
    0xfff8f3ff,
    0xffd7baff,
    0xff67448f,
    radius: 18,
  ),
];

bool validThemeStyle(Object? value) =>
    appearancePresets.any((preset) => preset.id == value);

String checkedThemeStyle(Object? value) {
  if (!validThemeStyle(value)) {
    throw const FormatException('Невідомий стиль оформлення.');
  }
  return value as String;
}
