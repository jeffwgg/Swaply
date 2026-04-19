// @ts-ignore
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// @ts-ignore
declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

Deno.serve(async (req: Request) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabaseClient = createClient(
      Deno.env.get('SUPABASE_URL') ?? '',
      Deno.env.get('SUPABASE_ANON_KEY') ?? '',
      { global: { headers: { Authorization: req.headers.get('Authorization')! } } }
    )

    const { data: { user } } = await supabaseClient.auth.getUser()
    if (!user?.id) {
      return new Response(JSON.stringify({ error: 'Unauthorized' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 401,
      })
    }

    const userId = user.id

    const { message } = await req.json()

    if (!message) {
      return new Response(JSON.stringify({ error: 'Message is required' }), {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 400,
      })
    }

    // 1. Fetch user's previous AI messages for context (skip the one they just sent if it hit DB already)
    const { data: historyData, error: historyError } = await supabaseClient
      .from('ai_messages')
      .select('content, is_ai')
      .eq('user_id', userId)
      .order('created_at', { ascending: false })
      .limit(10)

    if (historyError) {
      console.error('Error fetching history:', historyError)
    }

    // 2. Format history for OpenRouter
    const historyMessages = (historyData || []).reverse().map((msg: any) => ({
      role: msg.is_ai ? 'assistant' : 'user',
      content: msg.content
    }))

    // To prevent omitting the current requested message (due to race condition with client insert), 
    // we ensure the latest message in context matches what was passed in.
    if (historyMessages.length === 0 || historyMessages[historyMessages.length - 1].content !== message) {
      historyMessages.push({ role: 'user', content: message })
    }

const systemMessage = {
  role: 'system',
  content: `You are "Swaply Buddy", a friendly and helpful AI assistant for a mobile marketplace app called Swaply.

-----------------------
PERSONALITY
-----------------------
- Friendly, clear, and helpful
- Slightly conversational but professional
- Patient with new users

-----------------------
PRIMARY ROLE
-----------------------
Your main role is to help users understand and use Swaply:
- Selling items
- Trading items
- Sending transaction requests
- Chatting with other users
- Managing listings and profiles

-----------------------
BEHAVIOR RULES
-----------------------
1. Prioritize helping users with Swaply-related tasks.
2. If the user asks a simple general question (e.g., math, greeting, joke), answer briefly and naturally.
3. After answering general questions, gently guide the user back to app-related help when appropriate.
4. If the question is unrelated AND complex, politely decline and redirect to Swaply usage.
5. Do not make up information. Ask if unsure.
6. Keep answers clear and actionable.

-----------------------
RESPONSE STYLE
-----------------------
- Keep responses short (3–6 lines)
- Use simple language
- Use steps when explaining processes
- Avoid technical jargon
- Do not use emojis or special symbols

-----------------------
GOAL
-----------------------
Help users quickly understand and use Swaply while maintaining a natural and user-friendly interaction.`
}

    // Call OpenRouter API
    const openrouterResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Authorization': `Bearer ${Deno.env.get('OPENROUTER_API_KEY')}`,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        model: 'nvidia/nemotron-3-super-120b-a12b:free',
        messages: [systemMessage, ...historyMessages]
      })
    })

    if (!openrouterResponse.ok) {
        const errorText = await openrouterResponse.text()
        console.error('OpenRouter error', errorText)
        throw new Error('Failed to get response from AI: ' + errorText)
    }

    const aiData = await openrouterResponse.json()
    const aiMessageText = aiData.choices[0].message.content

    // Use service role for inserting the AI's response if necessary, or the current user's client
    // Depending on RLS, the user should be able to insert this as their own chat message since RLS just checks user_id
    const { error: insertError } = await supabaseClient
      .from('ai_messages')
      .insert({
        user_id: userId,
        content: aiMessageText,
        is_ai: true
      })

    if (insertError) {
      console.error('Insert error', insertError)
      throw new Error('Failed to save AI response')
    }

    return new Response(JSON.stringify({ success: true, ai_message: aiMessageText }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 200,
    })

  } catch (error: any) {
    console.error(error)
    return new Response(JSON.stringify({ error: error.message }), {
      headers: { ...corsHeaders, 'Content-Type': 'application/json' },
      status: 500,
    })
  }
})