import '../models/app_user.dart';
import '../services/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'dart:developer';

class UsersRepository {

  static final UsersRepository _instance = UsersRepository._internal();
  factory UsersRepository() => _instance;
  UsersRepository._internal();

  static const _table = 'users';
  final _client = SupabaseService.client; 

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

  Future<AppUser?> getById(String id) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();

    log('log $response');
    if (response == null) {
      return null;
    }

    return AppUser.fromMap(_requireMap(response, operation: 'getById'));
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
        .upsert(user.toInsertMap(), onConflict: 'id');
  }

  //change password screen
  Future<bool> isUsernameTaken(String username, String userId) async {
    final res = await _client
        .from('users')
        .select('id')
        .eq('username', username)
        .neq('id', userId)
        .maybeSingle();

    return res != null;
  }

  Future<bool> isPhoneTaken(String phone, String userId) async {
    final res = await _client
        .from(_table)
        .select('id')
        .eq('phone', phone)
        .neq('id', userId)
        .maybeSingle();

    return res != null;
  }
  Future<bool> isPhoneTakenForCreate(String phone) async {
    final res = await _client
        .from(_table)
        .select('id')
        .eq('phone', phone)
        .maybeSingle();

    return res != null;
  }

  Future<void> updateUser(String userId, Map<String, dynamic> data) async {
    await _client
        .from(_table)
        .update(data)
        .eq('id', userId);
  }

  Future<void> updateUsernameFlag() async {
    await _client.auth.updateUser(
      UserAttributes(data: {'username_changed': true}),
    );
  }

  Future<void> changePassword({
    required String email,
    required String currentPassword,
    required String newPassword,
  }) async {
    await _client.auth.signInWithPassword(
      email: email,
      password: currentPassword,
    );

    await _client.auth.updateUser(
      UserAttributes(password: newPassword),
    );
  }
  Future<void> insertUser(Map<String, dynamic> data) async {
    await _client.from('users').insert(data);
  }

}
