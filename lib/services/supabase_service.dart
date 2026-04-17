import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/constants/app_config.dart';

class SupabaseService {
  SupabaseService._();

  static Future<void> initialize() async {
    if (!AppConfig.hasSupabaseConfig) {
      return;
    }

    await Supabase.initialize(
      url: AppConfig.supabaseUrl,
      anonKey: AppConfig.supabaseAnonKey,
      authOptions: const FlutterAuthClientOptions(
        authFlowType: AuthFlowType.pkce,
      ),
    );
  }

  static bool get isConfigured => AppConfig.hasSupabaseConfig;

  static SupabaseClient get client {
    if (!isConfigured) {
      throw StateError(
        'Supabase is not configured. Provide SUPABASE_URL and SUPABASE_ANON_KEY using --dart-define.',
      );
    }
    return Supabase.instance.client;
  }
  static Future<void> logout() async {
    await client.auth.signOut();
  }
}
