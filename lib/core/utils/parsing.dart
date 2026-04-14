int parseInt(dynamic value, {required String fieldName}) {
  if (value == null) {
    throw StateError('Missing required integer field: $fieldName');
  }

  if (value is int) {
    return value;
  }

  if (value is num) {
    final asInt = value.toInt();
    if (asInt.toDouble() != value.toDouble()) {
      throw StateError('Invalid integer value for $fieldName: $value');
    }
    return asInt;
  }

  if (value is String) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      throw StateError('Invalid integer string for $fieldName: $value');
    }
    return parsed;
  }

  throw StateError(
    'Invalid type for integer field $fieldName: ${value.runtimeType}',
  );
}

int? parseNullableInt(dynamic value, {required String fieldName}) {
  if (value == null) {
    return null;
  }
  return parseInt(value, fieldName: fieldName);
}
