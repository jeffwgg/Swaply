import '../models/app_user.dart';
import '../services/supabase_service.dart';

class UsersRepository {
  UsersRepository();

  static const _table = 'users';

  List<Map<String, dynamic>> _requireListOfMaps(
    dynamic response, {
    required String operation,
  }) {
    if (response is! List) {
      throw StateError('Unexpected $operation response: expected List.');
    }

    return response.map<Map<String, dynamic>>((row) {
      if (row is Map<String, dynamic>) {
        return row;
      }
      if (row is Map) {
        return row.map((key, value) => MapEntry(key.toString(), value));
      }
      throw StateError('Unexpected $operation row shape: expected Map.');
    }).toList();
  }

  Map<String, dynamic> _requireMap(
    dynamic response, {
    required String operation,
  }) {
    if (response is Map<String, dynamic>) {
      return response;
    }
    if (response is Map) {
      return response.map((key, value) => MapEntry(key.toString(), value));
    }
    throw StateError('Unexpected $operation response: expected Map.');
  }

  Future<AppUser?> getById(int id) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return AppUser.fromMap(_requireMap(response, operation: 'getById'));
  }

  Future<AppUser?> getByAuthUserId(String authUserId) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('auth_user_id', authUserId)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return AppUser.fromMap(_requireMap(response, operation: 'getByAuthUserId'));
  }

  Future<List<AppUser>> list() async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .order('created_at', ascending: false);

    final rows = _requireListOfMaps(response, operation: 'list');
    return rows.map<AppUser>(AppUser.fromMap).toList();
  }

  Future<void> upsert(AppUser user) async {
    await SupabaseService.client
        .from(_table)
        .upsert(user.toMap(), onConflict: 'auth_user_id');
  }
}
