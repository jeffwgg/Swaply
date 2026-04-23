import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "GET, OPTIONS",
};

serve(async (req) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }

  if (req.method !== "GET") {
    return new Response(JSON.stringify({ error: "Method not allowed" }), {
      status: 405,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }

  try {
    const stripeSecretKey = Deno.env.get("STRIPE_SECRET_KEY");
    if (!stripeSecretKey) {
      return new Response(JSON.stringify({ error: "Missing STRIPE_SECRET_KEY" }), {
        status: 500,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const url = new URL(req.url);
    const paymentIntentId = url.searchParams.get("payment_intent_id") ?? "";
    if (!paymentIntentId.trim()) {
      return new Response(JSON.stringify({ error: "Missing payment_intent_id" }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const resp = await fetch(
      `https://api.stripe.com/v1/payment_intents/${encodeURIComponent(paymentIntentId)}?expand[]=latest_charge`,
      {
        method: "GET",
        headers: {
          Authorization: `Bearer ${stripeSecretKey}`,
        },
      },
    );

    const data = await resp.json();
    if (!resp.ok) {
      return new Response(JSON.stringify({ error: data }), {
        status: 400,
        headers: { ...corsHeaders, "Content-Type": "application/json" },
      });
    }

    const latest = data.latest_charge;
    const typeFromLatest = latest?.payment_method_details?.type ?? null;
    const typeFromTypes = Array.isArray(data.payment_method_types) && data.payment_method_types.length
      ? data.payment_method_types[0]
      : null;

    const paymentMethod = typeFromLatest ?? typeFromTypes ?? null;

    return new Response(
      JSON.stringify({
        paymentMethod,
        status: data.status ?? null,
      }),
      { headers: { ...corsHeaders, "Content-Type": "application/json" } },
    );
  } catch (e) {
    return new Response(JSON.stringify({ error: String(e) }), {
      status: 500,
      headers: { ...corsHeaders, "Content-Type": "application/json" },
    });
  }
});

