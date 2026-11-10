import { createClient, type Session } from "@supabase/supabase-js";

const url = import.meta.env.VITE_SUPABASE_URL as string | undefined;
const anon = import.meta.env.VITE_SUPABASE_ANON_KEY as string | undefined;

export const supabase = url && anon ? createClient(url, anon, {
  auth: { persistSession: true, autoRefreshToken: true, detectSessionInUrl: true },
  realtime: { params: { eventsPerSecond: 10 } },
}) : null;
export const backendConfigured = Boolean(supabase);

export type CompetitorKind = "individual" | "team";
export type EventStatus = "draft" | "live" | "paused" | "ended";
export type DbEvent = { id: string; name: string; pin: string; status: EventStatus; current_question: number; question_seconds: number; };
export type DbCompetitor = { id: string; display_name: string; kind: CompetitorKind; score: number; solved_count: number; };

function requireClient() {
  if (!supabase) throw new Error("Supabase is not configured. Add VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY.");
  return supabase;
}

export async function signInOrganizer(email: string, password: string) {
  const { data, error } = await requireClient().auth.signInWithPassword({ email, password });
  if (error) throw error;
  return data.session;
}
export async function signOutOrganizer() {
  const { error } = await requireClient().auth.signOut();
  if (error) throw error;
}
export async function getSession(): Promise<Session | null> {
  const { data, error } = await requireClient().auth.getSession();
  if (error) throw error;
  return data.session;
}
export async function createEvent(name: string, pin: string, questionSeconds: number) {
  const { data, error } = await requireClient().rpc("create_event", { p_name: name, p_pin: pin, p_question_seconds: questionSeconds }).single();
  if (error) throw error;
  return data as DbEvent;
}
export async function getEventByPin(pin: string) {
  const { data, error } = await requireClient().rpc("get_live_event_by_pin", { p_pin: pin }).maybeSingle();
  if (error) throw error;
  return data as DbEvent | null;
}
export async function listEventCompetitors(eventId: string) {
  const { data, error } = await requireClient().from("competitors").select("id,display_name,kind,score,solved_count").eq("event_id", eventId).order("score", { ascending: false });
  if (error) throw error;
  return (data ?? []) as DbCompetitor[];
}
export async function enrollCompetitor(pin: string, displayName: string, kind: CompetitorKind, members: string[]) {
  const { data, error } = await requireClient().rpc("join_event", { p_pin: pin, p_display_name: displayName, p_kind: kind, p_members: members });
  if (error) throw error;
  return data as string;
}
export async function setEventState(eventId: string, status: EventStatus) {
  const { error } = await requireClient().rpc("organizer_set_event_status", { p_event_id: eventId, p_status: status });
  if (error) throw error;
}
export async function setCurrentQuestion(eventId: string, questionNumber: number) {
  const { error } = await requireClient().rpc("organizer_set_question", { p_event_id: eventId, p_question: questionNumber });
  if (error) throw error;
}
export async function subscribeToEvent(eventId: string, onChange: () => void) {
  const client = requireClient();
  const channel = client.channel(`error404-event-${eventId}`)
    .on("postgres_changes", { event: "*", schema: "public", table: "competitors", filter: `event_id=eq.${eventId}` }, onChange)
    .on("postgres_changes", { event: "UPDATE", schema: "public", table: "events", filter: `id=eq.${eventId}` }, onChange)
    .subscribe();
  return () => { void client.removeChannel(channel); };
}

export async function checkOrganizer(): Promise<boolean> {
  if (!supabase) return false;
  const { data: { session } } = await supabase.auth.getSession();
  if (!session) return false;
  const { data, error } = await supabase.rpc("is_organizer");
  return !error && data === true;
}
