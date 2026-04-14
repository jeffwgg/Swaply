import '../models/app_user.dart';
import '../services/supabase_service.dart';

class UsersRepository {
  UsersRepository();

  static const _table = 'users';

  Future<AppUser?> getById(int id) async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .eq('id', id)
        .maybeSingle();

    if (response == null) {
      return null;
    }
    return AppUser.fromMap(response);
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
    return AppUser.fromMap(response);
  }

  Future<List<AppUser>> list() async {
    final response = await SupabaseService.client
        .from(_table)
        .select()
        .order('created_at', ascending: false);

    return response.map<AppUser>(AppUser.fromMap).toList();
  }

  Future<void> upsert(AppUser user) async {
    await SupabaseService.client
        .from(_table)
        .upsert(user.toMap(), onConflict: 'auth_user_id');
  }
}
