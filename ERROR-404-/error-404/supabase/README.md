# Supabase setup for ERROR-404

1. Create a Supabase project.
2. In **Project Settings → API**, copy the Project URL and `anon` / publishable key.
3. Copy `.env.example` to `.env.local` and fill in those two values. Never put a `service_role` key in a browser app.
4. Open **SQL Editor → New query**, paste all of `supabase/schema.sql`, and run it.
5. In **Authentication → Users**, create the organizer account. The organizer signs in with that email and password.
6. Restart Vite after changing `.env.local` (`npm run dev`). For Vercel, add the same two variables under Project → Settings → Environment Variables, redeploy, and add your Vercel URL to Authentication → URL Configuration (Site URL and Redirect URLs).

The SQL enables RLS and exposes only safe published-question fields through `public_questions`. Event creation and organizer controls are authenticated RPCs. Participants join a live event with its PIN through `join_event`. Scores must only be updated by a trusted server-side evaluator; never grant browser clients permission to update score columns or expose the service-role key.
