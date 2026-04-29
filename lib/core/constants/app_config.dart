class AppConfig {
  AppConfig._();

  static const String supabaseUrl = 'https://ljbrzegwpykjbfwakldf.supabase.co';
  static const String supabaseAnonKey =
      'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImxqYnJ6ZWd3cHlramJmd2FrbGRmIiwicm9sZSI6ImFub24iLCJpYXQiOjE3Nzc0NjU1MjQsImV4cCI6MjA5MzA0MTUyNH0.tP2M2EbfGFS2fWatFKFyLDFKNF_XaoTJkHymPao_y90';
  /// Stripe publishable key (test `pk_test_...`). Pass with:
  /// `flutter run --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_...`
  static const String stripePublishableKey = String.fromEnvironment(
    'STRIPE_PUBLISHABLE_KEY',
    defaultValue: '',
  );

  /// HTTPS endpoint that returns `{"clientSecret":"pi_..._secret_..."}` for
  /// the PaymentIntent amount you send (server must create the PI with the
  /// secret key). Optional; when empty, checkout uses a built-in simulator.
  static const String stripePaymentIntentUrl = String.fromEnvironment(
    'STRIPE_PAYMENT_INTENT_URL',
    defaultValue: '',
  );

  static bool get hasSupabaseConfig =>
      supabaseUrl.trim().isNotEmpty && supabaseAnonKey.trim().isNotEmpty;

  static bool get hasStripePublishableKey =>
      stripePublishableKey.trim().isNotEmpty;

  static bool get hasStripePaymentIntentEndpoint =>
      stripePaymentIntentUrl.trim().isNotEmpty;
}
