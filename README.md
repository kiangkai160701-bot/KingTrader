# KingTrader Gold Terminal

Thai-language responsive gold-market dashboard with a paper trading journal.

## Run locally

1. Install Node.js (LTS).
2. Run `npm install`, then `npm run dev`.
3. The chart, quotes, sentiment and top-ten headlines are clearly marked demo data. Add a licensed live data provider before presenting them as current market information.

## Supabase

1. In Supabase SQL Editor, run `supabase/schema.sql`.
2. Copy `.env.example` to `.env.local`. The project URL is prefilled; set `VITE_SUPABASE_ANON_KEY` to the project's publishable key.
3. Run `supabase/schema.sql` once in the Supabase SQL Editor. Enable **Allow anonymous sign-ins** under Authentication → Sign In / Providers. The app uses an anonymous Supabase account and row-level security to keep each paper-trading journal private. Never put a service-role key in browser code.

## GitHub Pages

This repo includes a GitHub Actions workflow that builds and deploys to Pages. Enable Pages in repository settings and choose **GitHub Actions** as the source. Add `VITE_SUPABASE_URL` and `VITE_SUPABASE_ANON_KEY` as repository Actions variables, then push to `main`.
