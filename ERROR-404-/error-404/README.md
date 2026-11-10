# ERROR-404 — Debugging competition platform

React + TypeScript + Vite frontend (Supabase backend) for an organizer-led Python / JavaScript debugging event.

## Local development

```bash
npm install
cp .env.example .env.local   # fill in your two Supabase values
npm run dev
```

## Deploy to Vercel

1. Set up Supabase first (see [supabase/README.md](./supabase/README.md)) and run `supabase/schema.sql`.
2. Push this folder to a GitHub/GitLab repo (`.env.local` is git-ignored; never commit keys).
3. In Vercel: **Add New → Project → Import** the repo. Vercel detects Vite automatically (settings are also in `vercel.json`).
4. Under **Settings → Environment Variables**, add for Production (and Preview if you want):
   - `VITE_SUPABASE_URL`
   - `VITE_SUPABASE_ANON_KEY`
5. Click **Deploy**. Vite reads these variables at build time, so after changing them you must **Redeploy**.
6. In Supabase: **Authentication → URL Configuration** → set **Site URL** to your Vercel URL (e.g. `https://error-404.vercel.app`) and add it (plus `https://*-yourteam.vercel.app` for previews) to **Redirect URLs**. Organizer sign-in will misbehave if this is skipped.

CLI alternative:

```bash
npm i -g vercel
vercel            # preview deploy
vercel --prod     # production deploy
vercel env add VITE_SUPABASE_URL
vercel env add VITE_SUPABASE_ANON_KEY
```

Only the Supabase URL and anon/publishable key belong in frontend variables. Never expose a service-role key. Code execution and score calculation require a separate trusted sandbox/backend; the browser must not decide accepted submissions or award points.

## Build

```bash
npm run build   # outputs to dist/
```

## Organizer privacy

- The organizer dashboard is **not linked anywhere**. Open it at `https://YOUR-SITE/#organizer`; it shows a login screen and only opens for accounts on the `organizers` allow-list.
- Setup (once): in Supabase **Authentication → Users** create the organizer account(s), run `supabase/organizer_lockdown.sql`, then run the commented `insert into public.organizers ...` line with your email.
- In Supabase **Authentication → Sign In / Providers**, turn **off "Allow new users to sign up"** so nobody else can create an account.
- Without Supabase configured, the dashboard stays locked (there is no demo bypass).
