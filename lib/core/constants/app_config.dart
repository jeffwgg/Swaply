class AppConfig {
  AppConfig._();

  static const String supabaseUrl = 'https://rxcpoebnwtgpwfgkhloo.supabase.co';
  static const String supabaseAnonKey = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InJ4Y3BvZWJud3RncHdmZ2tobG9vIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzQzMjA1MTUsImV4cCI6MjA4OTg5NjUxNX0.AnJimznrr6dUrUdacY2ymD-Np52ol4tc7eWXja7fIAg';

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
