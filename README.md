# Swaply

A Flutter marketplace app for listing items, discovering products, chatting with other users, and completing swap or purchase transactions.

## Features

### User Management Module
- Authentication (Login, Sign Up, Forgot Password)
- Profile management with camera capture
- Home screen with swipe card interface

### Item & Post Management Module
- Item CRUD with camera capture
- Item drafts and search history
- Favorite items and your listings (Supabase & SQLite)
- OpenStreetMap integration with current location detection
- Location search using Nominatim

### Messaging & Chat Module
- Real-time messaging with chat history
- RAG-based AI chatbot assistant

### Inbox & Notification Module
- Push notifications and inbox

### Payment & Transaction Module
- Stripe payment integration
- Transaction history
- QR code functionality

### Configuration Module
- Help Center
- About App

## Tech Stack

- **Flutter** - Cross-platform mobile app
- **Supabase** - Backend, authentication, and database
- **Stripe** - Payment processing
- **Google Maps** - Location features

## Getting Started

### Prerequisites

- Flutter SDK (Dart `^3.10.7`)
- Android Studio or Xcode

### Installation

1. Install dependencies:

```bash
flutter pub get
```

2. Configure Supabase in `lib/core/constants/app_config.dart`:

```dart
SUPABASE_URL=https://YOUR_PROJECT_REF.supabase.co
SUPABASE_ANON_KEY=YOUR_SUPABASE_ANON_KEY
```

3. Run the app:

```bash
flutter run
```

### Optional: Stripe Configuration

For payment testing, pass Stripe keys when running:

```bash
flutter run \
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_... \
  --dart-define=STRIPE_PAYMENT_INTENT_URL=https://YOUR_HOST/create-payment-intent
```

Without Stripe configuration, the app uses a demo payment simulator.
