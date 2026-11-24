const preparationItems = <String, String>{
  'water': 'Вода та особисті речі',
  'battery': 'Заряджений телефон і павербанк',
  'light': 'Ліхтар і запас живлення',
  'documents': 'Документи та важливі контакти',
  'offline': 'Потрібні матеріали завантажені',
  'backup': 'Резервну копію збережено окремо',
};

double checkedReaderScale(Object? value) {
  if (value is! num || !value.isFinite || value < .8 || value > 1.8) {
    throw const FormatException('Некоректний масштаб читання.');
  }
  return value.toDouble();
}

Set<String> checkedPreparation(Object? value) {
  if (value is! List ||
      value.length > preparationItems.length ||
      value.any((v) => v is! String || !preparationItems.containsKey(v)) ||
      value.toSet().length != value.length) {
    throw const FormatException('Некоректний особистий список підготовки.');
  }
  return value.cast<String>().toSet();
}
