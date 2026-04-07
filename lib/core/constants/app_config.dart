class AppConfig {
  AppConfig._();

  static const String supabaseUrl = 'https://rxcpoebnwtgpwfgkhloo.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ4Y3BvZWJud3RncHdmZ2tobG9vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzMjA1MTUsImV4cCI6MjA4OTg5NjUxNX0.AnJimznrr6dUrUdacY2ymD-Np52ol4tc7eWXja7fIAg';

  static bool get hasSupabaseConfig =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;
}
