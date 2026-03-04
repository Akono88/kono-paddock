// supabase/functions/generate-insights/index.ts
// ============================================================
// MARTA ENGINE — AI Insight Generator
// Supabase Edge Function that calls Claude API to analyze
// recent activity and generate proactive suggestions.
//
// Deploy: supabase functions deploy generate-insights
// ============================================================

import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { serve } from 'https://deno.land/std@0.168.0/http/server.ts'

const ANTHROPIC_API_KEY = Deno.env.get('ANTHROPIC_API_KEY')!
const SUPABASE_URL = Deno.env.get('SUPABASE_URL')!
const SUPABASE_SERVICE_KEY = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!

const corsHeaders = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
}

serve(async (req: Request) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  try {
    const supabase = createClient(SUPABASE_URL, SUPABASE_SERVICE_KEY)

    // Determine user from JWT or service key context
    const authHeader = req.headers.get('Authorization') || ''
    const token = authHeader.replace('Bearer ', '')

    let userId: string | null = null

    // If called from GitHub Actions with service key, process all users
    // If called from browser with user JWT, process that user only
    const { data: { user } } = await supabase.auth.getUser(token)
    userId = user?.id || null

    // ── Gather Recent Context ─────────────────────────────────
    const sevenDaysAgo = new Date(Date.now() - 7 * 24 * 60 * 60 * 1000).toISOString()

    // Recent entries
    let entriesQuery = supabase
      .from('entries')
      .select('content, domain, priority, created_at, resolved, tags')
      .gte('created_at', sevenDaysAgo)
      .order('created_at', { ascending: false })
      .limit(30)

    if (userId) entriesQuery = entriesQuery.eq('user_id', userId)

    const { data: recentEntries } = await entriesQuery

    // Upcoming deadlines
    let deadlinesQuery = supabase
      .from('legal_deadlines')
      .select('title, deadline_date, completed, priority')
      .eq('completed', false)
      .order('deadline_date', { ascending: true })
      .limit(10)

    if (userId) deadlinesQuery = deadlinesQuery.eq('user_id', userId)

    const { data: upcomingDeadlines } = await deadlinesQuery

    // Open financial flags
    let flagsQuery = supabase
      .from('financial_flags')
      .select('title, flag_type, amount, vendor, status')
      .eq('status', 'pending')
      .limit(10)

    if (userId) flagsQuery = flagsQuery.eq('user_id', userId)

    const { data: openFlags } = await flagsQuery

    // Pending tasks
    let tasksQuery = supabase
      .from('tasks')
      .select('title, domain, priority, status, due_date')
      .in('status', ['pending', 'in_progress'])
      .limit(15)

    if (userId) tasksQuery = tasksQuery.eq('user_id', userId)

    const { data: pendingTasks } = await tasksQuery

    // ── Build Claude Prompt ───────────────────────────────────
    const contextPayload = {
      recent_entries: recentEntries || [],
      upcoming_deadlines: upcomingDeadlines || [],
      open_financial_flags: openFlags || [],
      pending_tasks: pendingTasks || [],
      current_date: new Date().toISOString(),
    }

    const systemPrompt = `You are an operations analyst for a freight brokerage (MC# 971343) 
and the founder's personal command center. You analyze recent activity data and generate 
actionable insights. The business domains are: legal (custody case, contract disputes, 
bond claims), financial (QuickBooks-TMS reconciliation, duplicate payments, audit), 
operations (freight loads, carriers, temperature-controlled shipments), hr (employee 
onboarding, documentation), and personal (family, custody scheduling).

Generate 1-3 proactive insights. Each insight must be:
- Specific to the data patterns you observe
- Actionable with a clear next step
- Categorized by type: deadline_warning, pattern, suggestion, or anomaly
- Assigned a severity: critical, high, medium, or low

Respond ONLY with a JSON array of insight objects:
[
  {
    "insight_type": "pattern|deadline_warning|suggestion|anomaly",
    "title": "Short title",
    "content": "Detailed actionable insight (2-3 sentences max)",
    "severity": "critical|high|medium|low",
    "domain": "legal|financial|operations|hr|personal|general"
  }
]`

    // ── Call Claude API ───────────────────────────────────────
    const claudeResponse = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01',
      },
      body: JSON.stringify({
        model: 'claude-sonnet-4-20250514',
        max_tokens: 1024,
        system: systemPrompt,
        messages: [
          {
            role: 'user',
            content: `Analyze this operational data from the last 7 days and generate proactive insights:\n\n${JSON.stringify(contextPayload, null, 2)}`
          }
        ]
      })
    })

    if (!claudeResponse.ok) {
      const errText = await claudeResponse.text()
      throw new Error(`Claude API error: ${claudeResponse.status} - ${errText}`)
    }

    const claudeData = await claudeResponse.json()
    const responseText = claudeData.content
      .filter((block: any) => block.type === 'text')
      .map((block: any) => block.text)
      .join('')

    // Parse insights from Claude's response
    const insights = JSON.parse(responseText.replace(/```json|```/g, '').trim())

    // ── Store Insights in Supabase ────────────────────────────
    const insightsToInsert = insights.map((insight: any) => ({
      user_id: userId,
      domain: insight.domain || 'general',
      insight_type: insight.insight_type,
      title: insight.title,
      content: insight.content,
      severity: insight.severity || 'medium',
      acknowledged: false,
      metadata: { source: 'claude-api', generated_at: new Date().toISOString() },
    }))

    const { data: insertedInsights, error: insertError } = await supabase
      .from('ai_insights')
      .insert(insightsToInsert)
      .select()

    if (insertError) {
      console.error('Insert error:', insertError)
      throw insertError
    }

    return new Response(
      JSON.stringify({
        success: true,
        insights_generated: insightsToInsert.length,
        insights: insertedInsights,
      }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 200,
      }
    )
  } catch (error) {
    console.error('Edge function error:', error)
    return new Response(
      JSON.stringify({ error: error.message }),
      {
        headers: { ...corsHeaders, 'Content-Type': 'application/json' },
        status: 500,
      }
    )
  }
})
