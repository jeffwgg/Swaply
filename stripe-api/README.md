# Swaply Stripe endpoint

This folder is a tiny Node.js API that creates a Stripe **PaymentIntent** and returns its **client secret** for Flutter Stripe **PaymentSheet**.

## 1) Set your Stripe secret key (server-only)

Get your **test** secret key from Stripe dashboard and set it as an environment variable.

PowerShell:

```powershell
$env:STRIPE_SECRET_KEY="sk_test_..."
```

## 2) Run locally

```powershell
cd stripe-api
npm install
npm run dev
```

Endpoint:
- `POST http://localhost:3000/create-payment-intent`

Body example:

```json
{ "amount": 13000, "currency": "myr" }
```

Response:

```json
{ "clientSecret": "pi_..._secret_..." }
```

## 3) Point Flutter to this endpoint

When deployed over **HTTPS**, run Flutter with:

```bash
flutter run ^
  --dart-define=STRIPE_PUBLISHABLE_KEY=pk_test_... ^
  --dart-define=STRIPE_PAYMENT_INTENT_URL=https://YOUR_HOST/create-payment-intent
```

Important:
- Never put `sk_test_...` / `sk_live_...` in Flutter code.

