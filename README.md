# MARTA_ — Command Center

**US Cargo Brokers Operations Engine** · MC# 971343

A single-file command center that unifies legal tracking, financial controls, HR management, and freight operations into one real-time dashboard — with AI-powered proactive insights via Claude API.

---

## 10-Minute Deploy Guide

### 1. Supabase Setup (3 min)

1. Create a project at [supabase.com](https://supabase.com)
2. Go to **SQL Editor** → paste the contents of `schema.sql` → Run
3. Copy your **Project URL** and **anon/public key** from Settings → API

### 2. Configure the App (1 min)

Open `index.html` and update the `CONFIG` block near the bottom:

```javascript
const CONFIG = {
  SUPABASE_URL:      'https://YOUR-PROJECT.supabase.co',
  SUPABASE_ANON_KEY: 'eyJ...',
  AI_FUNCTION_URL:   'https://YOUR-PROJECT.supabase.co/functions/v1/generate-insights'
};
```

### 3. Deploy to GitHub Pages (3 min)

```bash
git init marta-engine && cd marta-engine
cp /path/to/index.html .
cp -r /path/to/.github .
git add -A
git commit -m "🚀 MARTA Engine — initial deploy"
git remote add origin git@github.com:YOUR-USERNAME/marta-engine.git
git push -u origin main
```

Then go to repo **Settings → Pages → Source: GitHub Actions**.

### 4. GitHub Secrets (2 min)

Add these in repo **Settings → Secrets → Actions**:

| Secret | Value |
|--------|-------|
| `SUPABASE_URL` | Your Supabase project URL |
| `SUPABASE_SERVICE_KEY` | Service role key (from Settings → API) |

### 5. Edge Function (1 min)

```bash
supabase functions deploy generate-insights
supabase secrets set ANTHROPIC_API_KEY=sk-ant-...
```

---

## Architecture

```
┌─────────────────────────────────────────────────────┐
│                   GitHub Pages                       │
│                  index.html (SPA)                    │
│  ┌──────────┐ ┌──────────┐ ┌──────────┐            │
│  │  Quick    │ │Dashboard │ │   AI     │            │
│  │ Capture   │ │  Stats   │ │ Insights │            │
│  └────┬─────┘ └────┬─────┘ └────┬─────┘            │
│       │             │            │                   │
└───────┼─────────────┼────────────┼───────────────────┘
        │             │            │
        ▼             ▼            ▼
┌─────────────────────────────────────────────────────┐
│              Supabase (Backend)                      │
│  ┌──────────────────────────────────────────┐       │
│  │         PostgreSQL + RLS                  │       │
│  │  entries │ legal_* │ financial_* │ tasks  │       │
│  └──────────────────────────────────────────┘       │
│  ┌──────────────┐  ┌────────────────────┐           │
│  │  Realtime     │  │  Edge Functions    │           │
│  │  (WebSocket)  │  │  (Claude API)      │           │
│  └──────────────┘  └────────────────────┘           │
└─────────────────────────────────────────────────────┘
        ▲
        │  Nightly via GitHub Actions
┌───────┴─────────────────────────────────────────────┐
│  .github/workflows/sync.yml                          │
│  • Auto-deploy on push                               │
│  • Nightly data backup → backups/latest.json         │
│  • Daily AI insight generation trigger               │
└─────────────────────────────────────────────────────┘
```

---

## Domain Map

| Domain | Color | Tracks |
|--------|-------|--------|
| ⚖ Legal | Amber | Custody case, attorney comms, deadlines, GAL activity |
| $ Financial | Green | Duplicate payments, bond claims, QB-TMS reconciliation |
| ◈ Operations | Blue | Load status, carrier issues, client account reviews |
| ◉ HR | Purple | Employee onboarding, separation, documentation |
| ♦ Personal | Pink | Kaleesi scheduling, property, personal items |

---

## Keyboard Shortcuts

| Shortcut | Action |
|----------|--------|
| `Ctrl+K` | Focus Quick Capture input |
| `Ctrl+I` | Generate AI Insight |
| `Enter`  | Submit capture entry |
