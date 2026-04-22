// @ts-ignore
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

// @ts-ignore
declare const Deno: any;

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

const OPENROUTER_TIMEOUT_MS = 35000
const FALLBACK_AI_MESSAGE =
  "I'm sorry, I'm having trouble connecting right now. Please try again in a moment."
const RAG_ITEMS_MARKER = '[[rag_items_json]]'
const COMPACT_HISTORY_MAX_MESSAGES = 4
const COMPACT_HISTORY_MAX_CHARS = 220
const COMPACT_RAG_MAX_ITEMS = 3
const TIMEOUT_RISK_HISTORY_THRESHOLD = 5
const TIMEOUT_RISK_ITEMS_CONTEXT_CHARS = 900
const TIMEOUT_RISK_USER_MESSAGE_CHARS = 180

const ITEM_SEARCH_STOP_WORDS = new Set([
  'a',
  'an',
  'and',
  'are',
  'can',
  'find',
  'for',
  'from',
  'i',
  'in',
  'is',
  'item',
  'items',
  'looking',
  'me',
  'need',
  'of',
  'or',
  'please',
  'show',
  'that',
  'than',
  'the',
  'to',
  'with',
  'price',
  'lower',
  'below',
  'under',
  'above',
  'over',
  'higher',
  'less',
  'more',
])

type PriceConstraint = {
  mode: 'lt' | 'gt'
  value: number
}

function normalizeText(value: string): string {
  return value.toLowerCase().replace(/[^a-z0-9]/g, '')
}

function extractSearchTerms(input: string): string[] {
  const lowered = input.toLowerCase()

  const tokens = lowered
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length >= 3 && !ITEM_SEARCH_STOP_WORDS.has(token))

  const normalizedCollapsed = normalizeText(lowered)
  const baseTerms = new Set<string>()

  for (const token of tokens) {
    baseTerms.add(normalizeText(token))
  }

  if (normalizedCollapsed.length >= 4) {
    baseTerms.add(normalizedCollapsed)
  }

  for (const term of Array.from(baseTerms)) {
    // Add stable prefixes for loose matching in SQL (e.g., macbook -> macb).
    if (term.length >= 5) {
      baseTerms.add(term.slice(0, 4))
    }
  }

  const nonEmptyTerms = Array.from(baseTerms).filter((term) => term.length >= 3)
  return nonEmptyTerms.slice(0, 10)
}

function parsePriceConstraint(input: string): PriceConstraint | null {
  const lower = input.toLowerCase()
  const ltMatch = lower.match(/(?:below|under|less than|lower than)\s*(\d+(?:\.\d+)?)/)
  if (ltMatch?.[1]) {
    const value = Number(ltMatch[1])
    if (Number.isFinite(value)) {
      return { mode: 'lt', value }
    }
  }

  const gtMatch = lower.match(/(?:above|over|more than|higher than)\s*(\d+(?:\.\d+)?)/)
  if (gtMatch?.[1]) {
    const value = Number(gtMatch[1])
    if (Number.isFinite(value)) {
      return { mode: 'gt', value }
    }
  }

  return null
}

function extractPrimarySubject(input: string): string | null {
  const tokens = input
    .toLowerCase()
    .replace(/[^a-z0-9\s]/g, ' ')
    .split(/\s+/)
    .map((token) => token.trim())
    .filter((token) => token.length >= 4 && !ITEM_SEARCH_STOP_WORDS.has(token))

  return tokens.length > 0 ? tokens[0] : null
}

function levenshteinDistance(a: string, b: string): number {
  if (a === b) {
    return 0
  }
  if (a.length === 0) {
    return b.length
  }
  if (b.length === 0) {
    return a.length
  }

  const rows = a.length + 1
  const cols = b.length + 1
  const dp: number[][] = Array.from({ length: rows }, () => Array(cols).fill(0))

  for (let i = 0; i < rows; i++) {
    dp[i][0] = i
  }
  for (let j = 0; j < cols; j++) {
    dp[0][j] = j
  }

  for (let i = 1; i < rows; i++) {
    for (let j = 1; j < cols; j++) {
      const cost = a[i - 1] === b[j - 1] ? 0 : 1
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost
      )
    }
  }

  return dp[a.length][b.length]
}

function isSoftMatch(term: string, candidate: string): boolean {
  if (term.length === 0 || candidate.length === 0) {
    return false
  }

  if (term === candidate) {
    return true
  }

  if (term.includes(candidate) || candidate.includes(term)) {
    return Math.min(term.length, candidate.length) >= 3
  }

  const minPrefix = Math.min(4, term.length, candidate.length)
  if (minPrefix >= 3 && term.slice(0, minPrefix) === candidate.slice(0, minPrefix)) {
    return true
  }

  const maxLen = Math.max(term.length, candidate.length)
  if (maxLen <= 4) {
    return false
  }

  const threshold = maxLen <= 6 ? 1 : 2
  return levenshteinDistance(term, candidate) <= threshold
}

function collectNormalizedCandidates(row: any): string[] {
  const fields = [
    typeof row?.title === 'string' ? row.title : '',
    typeof row?.name === 'string' ? row.name : '',
    typeof row?.description === 'string' ? row.description : '',
    typeof row?.category === 'string' ? row.category : '',
  ]

  const candidates = new Set<string>()

  for (const field of fields) {
    const collapsed = normalizeText(field)
    if (collapsed.length >= 3) {
      candidates.add(collapsed)
    }

    const tokens = field
      .toLowerCase()
      .replace(/[^a-z0-9\s]/g, ' ')
      .split(/\s+/)
      .map((token: string) => normalizeText(token))
      .filter((token: string) => token.length >= 3)

    for (const token of tokens) {
      candidates.add(token)
    }
  }

  return Array.from(candidates)
}

function inferListingIntent(input: string): 'sell' | 'trade' | null {
  const lower = input.toLowerCase()
  const asksTrade = lower.includes('trade') || lower.includes('swap')
  const asksBuy =
    lower.includes('buy') ||
    lower.includes('purchase') ||
    lower.includes('price') ||
    lower.includes('for sale')

  if (asksTrade && !asksBuy) {
    return 'trade'
  }
  if (asksBuy && !asksTrade) {
    return 'sell'
  }
  return null
}

function normalizeItemsForPrompt(rows: any[]): any[] {
  return rows
    .map((row: any) => {
      const id = row?.id
      const title =
        typeof row?.title === 'string' && row.title.trim().length > 0
          ? row.title.trim()
          : typeof row?.name === 'string' && row.name.trim().length > 0
          ? row.name.trim()
          : null

      if (id == null || !title) {
        return null
      }

      const price =
        typeof row?.price === 'number' || typeof row?.price === 'string'
          ? String(row.price)
          : null

      return {
        id,
        title,
        price,
        listing_type:
          typeof row?.listing_type === 'string' ? row.listing_type : null,
        condition: typeof row?.condition === 'string' ? row.condition : null,
        category: typeof row?.category === 'string' ? row.category : null,
      }
    })
    .filter((item: any) => item !== null)
}

function buildKeywordClauses(
  keywords: string[],
  options: { includeTitle: boolean; includeName: boolean }
): string[] {
  const clauses: string[] = []

  for (const keyword of keywords) {
    const safeKeyword = normalizeText(keyword).replace(/[%_]/g, '')
    if (safeKeyword.length < 2) {
      continue
    }

    if (options.includeTitle) {
      clauses.push(`title.ilike.%${safeKeyword}%`)
    }
    if (options.includeName) {
      clauses.push(`name.ilike.%${safeKeyword}%`)
    }
    clauses.push(`description.ilike.%${safeKeyword}%`)
    clauses.push(`category.ilike.%${safeKeyword}%`)
  }

  return clauses
}

function matchesAnyKeyword(row: any, keywords: string[]): boolean {
  if (keywords.length === 0) {
    return true
  }

  const candidates = collectNormalizedCandidates(row)
  if (candidates.length === 0) {
    return false
  }

  return keywords.some((keyword) => {
    const normalizedKeyword = normalizeText(keyword)
    if (normalizedKeyword.length < 3) {
      return false
    }
    return candidates.some((candidate) => isSoftMatch(normalizedKeyword, candidate))
  })
}

function passesIntent(row: any, listingIntent: 'sell' | 'trade' | null): boolean {
  if (listingIntent == null) {
    return true
  }

  const listingType =
    typeof row?.listing_type === 'string' ? row.listing_type.toLowerCase() : ''

  if (listingIntent === 'sell') {
    return listingType === 'sell' || listingType === 'both'
  }
  return listingType === 'trade' || listingType === 'both'
}

function stripStoredRagPayload(content: string): string {
  const markerIndex = content.indexOf(RAG_ITEMS_MARKER)
  if (markerIndex === -1) {
    return content
  }
  return content.substring(0, markerIndex).trimRight()
}

function formatMatchedSummaryForUser(items: any[]): string {
  if (items.length === 0) {
    return ''
  }

  const n = items.length
  const templates = [
    `I found ${n} item${n > 1 ? 's' : ''} for you.`,
    `I found ${n} option${n > 1 ? 's' : ''} that match what you are looking for.`,
    `I found ${n} relevant listing${n > 1 ? 's' : ''} for you.`,
  ]
  const selected = templates[Math.floor(Math.random() * templates.length)]
  return `${selected}\n\nTap the item below to check it out.`
}

function trimGuidance(text: string): string {
  return text
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .slice(0, 4)
    .join('\n')
}

function sanitizeGuidance(text: string, hasMatches: boolean): string {
  const trimmed = trimGuidance(text)
  if (trimmed.length === 0) {
    return ''
  }

  // Prefer structural guard over brittle phrase lists.
  if (hasMatches && trimmed.length < 20) {
    return ''
  }

  const singleStepLines = trimmed
    .split('\n')
    .map((line) => line.trim())
    .filter((line) => line.length > 0)

  const constrained = hasMatches
    ? singleStepLines.slice(0, 1).join(' ')
    : singleStepLines.slice(0, 2).join('\n')

  return constrained
    .replace(/item\s*id\s*[:#-]?\s*\d+/gi, '')
    .replace(/\bid\s*[:#-]?\s*\d+\b/gi, '')
    .replace(/\n{2,}/g, '\n')
    .trim()
}

function compactContentForModel(input: string, maxChars: number): string {
  const normalized = input.replace(/\s+/g, ' ').trim()
  if (normalized.length <= maxChars) {
    return normalized
  }
  return `${normalized.slice(0, Math.max(0, maxChars - 3))}...`
}

function compactHistoryForTimeoutRisk(
  historyMessages: Array<{ role: string; content: string }>
): Array<{ role: string; content: string }> {
  return historyMessages
    .slice(-COMPACT_HISTORY_MAX_MESSAGES)
    .map((entry) => ({
      role: entry.role,
      content: compactContentForModel(entry.content, COMPACT_HISTORY_MAX_CHARS),
    }))
}

function buildItemsContext(items: any[], maxItems: number): string {
  if (items.length === 0) {
    return 'No matched items found.'
  }

  return items
    .slice(0, maxItems)
    .map((item, index) => {
      const priceLabel = item.price ?? 'N/A'
      return `${index + 1}. ${item.title} | price: ${priceLabel} | type: ${item.listing_type ?? 'unknown'} | category: ${item.category ?? 'unknown'}`
    })
    .join('\n')
}

function isHighTimeoutRisk(params: {
  userMessage: string
  historyCount: number
  itemsContextLength: number
}): boolean {
  return (
    params.userMessage.length >= TIMEOUT_RISK_USER_MESSAGE_CHARS ||
    params.historyCount >= TIMEOUT_RISK_HISTORY_THRESHOLD ||
    params.itemsContextLength >= TIMEOUT_RISK_ITEMS_CONTEXT_CHARS
  )
}

function parsePrice(value: unknown): number | null {
  if (typeof value === 'number' && Number.isFinite(value)) {
    return value
  }
  if (typeof value === 'string') {
    const normalized = value.replace(/[^0-9.]/g, '')
    const parsed = Number(normalized)
    return Number.isFinite(parsed) ? parsed : null
  }
  return null
}

function extractRagItemsFromContent(content: string): any[] {
  const markerIndex = content.indexOf(RAG_ITEMS_MARKER)
  if (markerIndex === -1) {
    return []
  }

  const raw = content.substring(markerIndex + RAG_ITEMS_MARKER.length).trim()
  if (raw.length === 0) {
    return []
  }

  try {
    const parsed = JSON.parse(raw)
    return Array.isArray(parsed) ? parsed : []
  } catch (_) {
    return []
  }
}

function wantsCheaperRefinement(input: string): boolean {
  const lower = input.toLowerCase()
  return (
    lower.includes('cheaper') ||
    lower.includes('lower price') ||
    lower.includes('budget') ||
    lower.includes('less expensive')
  )
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
      .limit(6)

    if (historyError) {
      console.error('Error fetching history:', historyError)
    }

    // 2. Format history for OpenRouter
    const historyMessages = (historyData || []).reverse().map((msg: any) => ({
      role: msg.is_ai ? 'assistant' : 'user',
      content: stripStoredRagPayload(typeof msg.content === 'string' ? msg.content : '')
    }))

    // To prevent omitting the current requested message (due to race condition with client insert), 
    // we ensure the latest message in context matches what was passed in.
    if (historyMessages.length === 0 || historyMessages[historyMessages.length - 1].content !== message) {
      historyMessages.push({ role: 'user', content: message })
    }

    // 3. Retrieve matching marketplace items for simple RAG context.
    const listingIntent = inferListingIntent(message)
    const keywords = extractSearchTerms(message)
    const priceConstraint = parsePriceConstraint(message)
    const primarySubject = extractPrimarySubject(message)

    const hasKeywordFilters = keywords.length > 0

    const runItemsQuery = async (options: {
      selectClause: string
      includeTitle: boolean
      includeName: boolean
    }) => {
      let query = supabaseClient
        .from('items')
        .select(options.selectClause)
        .eq('status', 'available')
        .order('created_at', { ascending: false })
        .limit(5)

      if (listingIntent === 'sell') {
        query = query.or('listing_type.eq.sell,listing_type.eq.both')
      } else if (listingIntent === 'trade') {
        query = query.or('listing_type.eq.trade,listing_type.eq.both')
      }

      if (hasKeywordFilters) {
        const searchClauses = buildKeywordClauses(keywords, {
          includeTitle: options.includeTitle,
          includeName: options.includeName,
        })
        if (searchClauses.length > 0) {
          query = query.or(searchClauses.join(','))
        }
      }

      return await query
    }

    let itemRows: any[] = []
    let retrievalPath = 'query'
    let itemsResult = await runItemsQuery({
      selectClause:
        'id,title,name,description,price,listing_type,status,category',
      includeTitle: true,
      includeName: true,
    })

    if (itemsResult.error) {
      const errorMessage = (itemsResult.error.message || '').toLowerCase()
      if (errorMessage.includes('column items.name does not exist')) {
        retrievalPath = 'query_fallback_title'
        itemsResult = await runItemsQuery({
          selectClause:
            'id,title,description,price,listing_type,status,category',
          includeTitle: true,
          includeName: false,
        })
      } else if (errorMessage.includes('column items.title does not exist')) {
        retrievalPath = 'query_fallback_name'
        itemsResult = await runItemsQuery({
          selectClause:
            'id,name,description,price,listing_type,status,category',
          includeTitle: false,
          includeName: true,
        })
      }
    }

    if (itemsResult.error) {
      console.error('Error retrieving item matches:', itemsResult.error)
    } else {
      itemRows = Array.isArray(itemsResult.data) ? itemsResult.data : []
    }

    // Safety-net retrieval: if server-side filtered query found nothing,
    // fetch recent available items and match in-memory.
    if (itemRows.length === 0 && hasKeywordFilters) {
      let broadRows: any[] = []
      const broadResult = await supabaseClient
        .from('items')
        .select('id,title,name,description,price,listing_type,status,category,created_at')
        .eq('status', 'available')
        .order('created_at', { ascending: false })
        .limit(120)

      if (broadResult.error) {
        const broadErrorMessage = (broadResult.error.message || '').toLowerCase()
        if (broadErrorMessage.includes('column items.title does not exist')) {
          const broadNameResult = await supabaseClient
            .from('items')
            .select('id,name,description,price,listing_type,status,category,created_at')
            .eq('status', 'available')
            .order('created_at', { ascending: false })
            .limit(120)
          if (!broadNameResult.error) {
            broadRows = Array.isArray(broadNameResult.data) ? broadNameResult.data : []
          }
        } else if (broadErrorMessage.includes('column items.name does not exist')) {
          const broadTitleResult = await supabaseClient
            .from('items')
            .select('id,title,description,price,listing_type,status,category,created_at')
            .eq('status', 'available')
            .order('created_at', { ascending: false })
            .limit(120)
          if (!broadTitleResult.error) {
            broadRows = Array.isArray(broadTitleResult.data) ? broadTitleResult.data : []
          }
        }
      } else {
        broadRows = Array.isArray(broadResult.data) ? broadResult.data : []
      }

      if (broadRows.length > 0) {
        itemRows = broadRows
          .filter((row) => passesIntent(row, listingIntent))
          .filter((row) => matchesAnyKeyword(row, keywords))
          .slice(0, 5)
        if (itemRows.length > 0) {
          retrievalPath = 'broad_in_memory_fallback'
        }
      }
    }

    // Lightweight refinement: if user asks for cheaper, narrow using previous AI RAG prices.
    const cheaperRefinement = wantsCheaperRefinement(message)
    let cheaperReferencePrice: number | null = null
    if (cheaperRefinement && Array.isArray(historyData)) {
      for (const msg of historyData) {
        if (!msg?.is_ai || typeof msg?.content !== 'string') {
          continue
        }
        const previousItems = extractRagItemsFromContent(msg.content)
        if (previousItems.length === 0) {
          continue
        }

        const prices = previousItems
          .map((item: any) => parsePrice(item?.price))
          .filter((price: number | null): price is number => price != null)

        if (prices.length > 0) {
          cheaperReferencePrice = Math.min(...prices)
          break
        }
      }
    }

    if (cheaperRefinement && cheaperReferencePrice != null) {
      itemRows = itemRows.filter((row) => {
        const price = parsePrice(row?.price)
        return price != null && price < cheaperReferencePrice!
      })
      retrievalPath = `${retrievalPath}_cheaper_refinement`
    }

    if (priceConstraint != null) {
      itemRows = itemRows.filter((row) => {
        const price = parsePrice(row?.price)
        if (price == null) {
          return false
        }
        return priceConstraint.mode === 'lt'
          ? price < priceConstraint.value
          : price > priceConstraint.value
      })
      retrievalPath = `${retrievalPath}_price_filter`
    }

    const matchedItems = normalizeItemsForPrompt(itemRows)
    const itemsContext = buildItemsContext(matchedItems, 5)
    const highTimeoutRisk = isHighTimeoutRisk({
      userMessage: String(message),
      historyCount: historyMessages.length,
      itemsContextLength: itemsContext.length,
    })

const fullSystemMessage = {
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
7. If ITEM_RESULTS is provided, use it as the source of truth for item recommendations.
8. Do not invent item IDs, prices, or listing details.
9. If there are no matches, explicitly say that and ask 1 short follow-up preference question.
10. When matches exist, give only ONE clear next step. Do not list multiple choices.

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

    const compactSystemMessage = {
      role: 'system',
      content:
        'You are Swaply Buddy. Be concise and accurate. Use ITEM_RESULTS as source of truth for recommendations. Do not invent item details. If matches exist, provide one short next step. If none, say no matches and ask one short follow-up preference question.',
    }

    const modelSystemMessage = highTimeoutRisk
      ? compactSystemMessage
      : fullSystemMessage

    const modelHistoryMessages = highTimeoutRisk
      ? compactHistoryForTimeoutRisk(historyMessages)
      : historyMessages

    const retrievalItemsContext = highTimeoutRisk
      ? buildItemsContext(matchedItems, COMPACT_RAG_MAX_ITEMS)
      : itemsContext

    const retrievalMessage = {
      role: 'system',
      content: `ITEM_RESULTS:\n${retrievalItemsContext}`,
    }

    const openRouterApiKey = Deno.env.get('OPENROUTER_API_KEY')
    let aiMessageText = FALLBACK_AI_MESSAGE
    let usedFallback = false
    let fallbackReason: string | null = null

    if (!openRouterApiKey) {
      usedFallback = true
      fallbackReason = 'missing_api_key'
      console.error('Missing OPENROUTER_API_KEY. Using fallback AI response.')
    } else {
      try {
        const timeoutSignal = AbortSignal.timeout(OPENROUTER_TIMEOUT_MS)
        const openrouterResponse = await fetch(
          'https://openrouter.ai/api/v1/chat/completions',
          {
            method: 'POST',
            headers: {
              'Authorization': `Bearer ${openRouterApiKey}`,
              'Content-Type': 'application/json',
            },
            body: JSON.stringify({
              model: 'nvidia/nemotron-3-super-120b-a12b:free',
              messages: [modelSystemMessage, retrievalMessage, ...modelHistoryMessages]
            }),
            signal: timeoutSignal,
          }
        )

        if (!openrouterResponse.ok) {
          const errorText = await openrouterResponse.text()
          console.error('OpenRouter error', errorText)
          usedFallback = true
          fallbackReason = `openrouter_http_${openrouterResponse.status}`
        } else {
          const aiData = await openrouterResponse.json()
          const candidate = aiData?.choices?.[0]?.message?.content
          if (typeof candidate == 'string' && candidate.trim().length > 0) {
            aiMessageText = candidate.trim()
          } else {
            console.error('OpenRouter response missing assistant content:', aiData)
            usedFallback = true
            fallbackReason = 'empty_model_response'
          }
        }
      } catch (openRouterError) {
        console.error('OpenRouter request failed:', openRouterError)
        usedFallback = true
        const rawMessage =
          openRouterError instanceof Error
            ? openRouterError.message
            : String(openRouterError)
        const normalizedMessage = rawMessage.toLowerCase()
        fallbackReason =
          normalizedMessage.includes('timeout') ||
              normalizedMessage.includes('aborted')
          ? 'openrouter_timeout'
          : 'openrouter_request_failed'
      }
    }

    // Backend is the source of truth for availability. AI output is guidance-only.
    const guidanceText = sanitizeGuidance(aiMessageText, matchedItems.length > 0)
    const hasMatches = matchedItems.length > 0
    const noMatchText =
      guidanceText.length > 0
        ? guidanceText
        : (() => {
            const target = primarySubject == null
              ? 'matching items'
              : `${primarySubject} listings`
            if (priceConstraint != null) {
              const bound = `${priceConstraint.mode === 'lt' ? 'under' : 'above'} ${priceConstraint.value}`
              return `I could not find any ${target} ${bound} right now. Want to try another ${primarySubject ?? 'item'} price range?`
            }
            return `I could not find any ${target} right now. You can refine by model, budget, or category.`
          })()

    const finalUserMessage = hasMatches
      ? (guidanceText.length > 0
          ? guidanceText
          : formatMatchedSummaryForUser(matchedItems))
      : noMatchText

    // Use service role for inserting the AI's response if necessary, or the current user's client
    // Depending on RLS, the user should be able to insert this as their own chat message since RLS just checks user_id
    const persistedAiContent = matchedItems.length > 0
      ? `${finalUserMessage}\n\n${RAG_ITEMS_MARKER}${JSON.stringify(matchedItems)}`
      : finalUserMessage

    const { error: insertError } = await supabaseClient
      .from('ai_messages')
      .insert({
        user_id: userId,
        content: persistedAiContent,
        is_ai: true
      })

    if (insertError) {
      console.error('Insert error', insertError)
      throw new Error('Failed to save AI response')
    }

    return new Response(JSON.stringify({
      success: true,
      ai_message: finalUserMessage,
      fallback: usedFallback,
      fallback_reason: fallbackReason,
      rag_debug: {
        listing_intent: listingIntent,
        keywords,
        matched_count: matchedItems.length,
        retrieval_path: retrievalPath,
        cheaper_refinement: cheaperRefinement,
        cheaper_reference_price: cheaperReferencePrice,
        price_constraint_mode: priceConstraint?.mode ?? null,
        price_constraint_value: priceConstraint?.value ?? null,
        primary_subject: primarySubject,
        high_timeout_risk: highTimeoutRisk,
      },
    }), {
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