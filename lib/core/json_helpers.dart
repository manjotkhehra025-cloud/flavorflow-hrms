Map<String, dynamic> asJsonMap(Object? value) {
  if (value is Map) return Map<String, dynamic>.from(value);
  return <String, dynamic>{};
}

List<Map<String, dynamic>> asJsonList(Object? value) {
  if (value is! List) return <Map<String, dynamic>>[];
  return value.whereType<Map>().map(Map<String, dynamic>.from).toList(growable: false);
}

List<String> asStringList(Object? value) {
  if (value is! List) return <String>[];
  return value.map((item) => item.toString()).toList(growable: false);
}

String stringValue(Object? value, {String fallback = ''}) => value?.toString() ?? fallback;

T? firstOrNone<T>(Iterable<T> values) {
  final iterator = values.iterator;
  return iterator.moveNext() ? iterator.current : null;
}
