import express from 'express';
import Stripe from 'stripe';

const app = express();
app.use(express.json());

// Optional: allow calling from Flutter/web during local testing.
app.use((req, res, next) => {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
  res.setHeader('Access-Control-Allow-Methods', 'GET,POST,OPTIONS');
  if (req.method === 'OPTIONS') {
    return res.status(204).end();
  }
  next();
});

const stripeSecretKey = process.env.STRIPE_SECRET_KEY;
if (!stripeSecretKey) {
  throw new Error('Missing STRIPE_SECRET_KEY env var on server');
}

const stripe = new Stripe(stripeSecretKey);

app.get('/', (req, res) => res.send('OK'));

// POST /create-payment-intent
// Body: { "amount": 13000, "currency": "myr" }
// Returns: { "clientSecret": "pi_..._secret_..." }
app.post('/create-payment-intent', async (req, res) => {
  try {
    const amount = req.body?.amount;
    const currency = (req.body?.currency ?? 'myr').toLowerCase();

    // amount must be integer in minor units (MYR sen). Example RM130.00 => 13000
    if (!Number.isInteger(amount) || amount <= 0) {
      return res
        .status(400)
        .json({ error: 'Invalid amount (must be integer > 0)' });
    }

    // For coursework demo, keep it strict and simple.
    if (currency !== 'myr') {
      return res.status(400).json({ error: "Only currency 'myr' is supported" });
    }

    const intent = await stripe.paymentIntents.create({
      amount,
      currency,
      automatic_payment_methods: { enabled: true },
    });

    return res.json({ clientSecret: intent.client_secret });
  } catch (e) {
    return res.status(500).json({ error: e?.message ?? String(e) });
  }
});

const port = process.env.PORT ?? 3000;
app.listen(port, () => {
  // eslint-disable-next-line no-console
  console.log(`Stripe API listening on http://localhost:${port}`);
});

