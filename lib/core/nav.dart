import 'package:flutter/material.dart';

Future<T?> pushScreen<T>(BuildContext context, Widget screen) {
  return Navigator.of(context).push<T>(MaterialPageRoute(builder: (_) => screen));
}
