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

String parseString(dynamic value, {required String fieldName}) {
  if (value == null) {
    throw StateError('Missing required string field: $fieldName');
  }

  if (value is String) {
    return value;
  }

  throw StateError(
    'Invalid type for string field $fieldName: ${value.runtimeType}',
  );
}

String? parseNullableString(dynamic value, {required String fieldName}) {
  if (value == null) {
    return null;
  }
  return parseString(value, fieldName: fieldName);
}

DateTime parseDateTime(dynamic value, {required String fieldName}) {
  if (value == null) {
    throw StateError('Missing required datetime field: $fieldName');
  }

  if (value is DateTime) {
    return value;
  }

  if (value is String) {
    return DateTime.parse(value);
  }

  throw StateError(
    'Invalid type for datetime field $fieldName: ${value.runtimeType}',
  );
}

DateTime? parseNullableDateTime(dynamic value, {required String fieldName}) {
  if (value == null) {
    return null;
  }
  return parseDateTime(value, fieldName: fieldName);
}

double? parseNullableDouble(dynamic value, {required String fieldName}) {
  if (value == null) {
    return null;
  }
  if (value is num) {
    return value.toDouble();
  }
  if (value is String) {
    final parsed = double.tryParse(value);
    if (parsed != null) {
      return parsed;
    }
  }
  throw StateError(
    'Invalid type for double field $fieldName: ${value.runtimeType}',
  );
}
