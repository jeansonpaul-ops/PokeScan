// PokéScan — cote des cartes en français via Valo (api.valotcg.com)
// La clé Valo reste ici, côté serveur (secret VALO_API_KEY, gratuite en « Sandbox »).
// Le téléphone envoie la carte ; la fonction l'identifie chez Valo puis renvoie :
//  · la cote recommandée (médiane des ventes eBay, sinon offres Cardmarket en français)
//  · l'offre Cardmarket FR la moins chère en Near Mint
//
// Secrets (Supabase → Edge Functions → Secrets) :
//   VALO_API_KEY    (obligatoire)  clé vd_test_… ou vd_live_…
//   ALLOWED_EMAILS  (facultatif)   emails autorisés, séparés par des virgules
// Accès : uniquement les membres acceptés (table profiles, statut « member »)

import { createClient } from "jsr:@supabase/supabase-js@2";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const VALO = "https://api.valotcg.com/data/v1";

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS, "Content-Type": "application/json" } });
}

class ValoError extends Error {
  constructor(message: string, public status: number) { super(message); }
}

// deno-lint-ignore no-explicit-any
async function valo(path: string, key: string): Promise<any> {
  const r = await fetch(VALO + path, { headers: { Authorization: `Bearer ${key}`, Accept: "application/json" } });
  const body = await r.json().catch(() => null);
  if (!r.ok) {
    const msg = body?.error?.message ?? body?.message ?? body?.detail ?? `HTTP ${r.status}`;
    console.error("Valo", r.status, JSON.stringify(body)?.slice(0, 300));
    if (r.status === 401) throw new ValoError("Clé Valo refusée : vérifie le secret VALO_API_KEY.", 502);
    if (r.status === 402 || r.status === 429) throw new ValoError(`Quota Valo atteint : ${msg}`, 429);
    throw new ValoError(`Valo : ${msg}`, 502);
  }
  return body;
}

type Query = { valo_id?: number | null; name?: string; number?: string; set_name?: string; lang?: string; finish?: string };

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  if (req.method !== "POST") return json({ error: "Méthode non autorisée." }, 405);

  // Utilisateur connecté et autorisé
  const token = (req.headers.get("Authorization") ?? "").replace(/^Bearer\s+/i, "");
  const sb = createClient(Deno.env.get("SUPABASE_URL")!, Deno.env.get("SUPABASE_ANON_KEY")!,
    { global: { headers: { Authorization: `Bearer ${token}` } } });
  const { data: { user } } = await sb.auth.getUser(token);
  if (!user) return json({ error: "Connecte-toi pour obtenir la cote FR." }, 401);
  // Seuls les membres acceptés par l'administrateur consomment le quota Valo
  const { data: prof } = await sb.from("profiles").select("status").eq("id", user.id).maybeSingle();
  if (prof?.status !== "member") return json({ error: "Ton accès n'a pas encore été validé." }, 403);
  const allowed = (Deno.env.get("ALLOWED_EMAILS") ?? "").split(",").map((s) => s.trim().toLowerCase()).filter(Boolean);
  if (allowed.length && !allowed.includes((user.email ?? "").toLowerCase())) {
    return json({ error: "Ce compte n'est pas autorisé à utiliser la cote FR." }, 403);
  }

  const key = Deno.env.get("VALO_API_KEY");
  if (!key) return json({ error: "Cote FR pas encore configurée : ajoute le secret VALO_API_KEY dans Supabase.", code: "no_key" }, 503);

  let q: Query;
  try { q = await req.json(); } catch { return json({ error: "Requête illisible." }, 400); }

  try {
    // 1. Identification (1 crédit), sauf si on connaît déjà l'identifiant Valo
    let id = Number(q.valo_id) || null;
    // deno-lint-ignore no-explicit-any
    let card: any = null;
    if (!id) {
      const name = String(q.name ?? "").trim();
      if (!name) return json({ error: "Nom de carte manquant." }, 400);
      const lang = ["fr", "en", "de", "it", "es", "ja", "pt"].includes(String(q.lang)) ? String(q.lang) : "fr";
      const text = [name, String(q.number ?? "").trim(), String(q.set_name ?? "").trim()].filter(Boolean).join(" ").slice(0, 120);
      const res = await valo(`/analysis/identify?game=pokemon&language=${lang}&q=${encodeURIComponent(text)}`, key);
      // deno-lint-ignore no-explicit-any
      const best = (res?.candidates ?? []).find((c: any) => (c.matched_on ?? []).includes("number") && c.score >= 0.55);
      if (!best) return json({ match: null, reason: "Carte introuvable chez Valo." });
      id = best.card?.id ?? best.card?.card_id ?? null;
      card = best.card;
      if (!id) return json({ match: null, reason: "Réponse Valo inattendue." });
    }

    // 2. Cote (1 crédit)
    const s = await valo(`/analysis/cards/${id}/summary`, key);
    const foil = q.finish === "Reverse Holo";
    // deno-lint-ignore no-explicit-any
    const frOffers = (s.prices ?? []).filter((p: any) =>
      p.source === "cardmarket" && p.market_language === "fr" && p.amount != null && p.status !== "missing");
    // deno-lint-ignore no-explicit-any
    const fr = frOffers.find((p: any) => p.variant === (foil ? "foil" : "default")) ?? (foil ? null : frOffers[0]) ?? null;
    // deno-lint-ignore no-explicit-any
    const nm = fr?.conditions?.find((c: any) => c.condition === "NM")?.amount ?? (fr?.condition === "NM" ? fr.amount : null);

    // Pour une reverse, l'offre FR « foil » est plus juste que la cote générale
    // Sans offre FR « foil », la cote générale de Valo vise la version normale : on n'en tient pas compte pour une reverse
    // deno-lint-ignore no-explicit-any
    const rec: any = foil ? {} : (s.recommended ?? {});
    const useOffer = foil && fr?.amount != null;
    return json({
      match: true,
      valo_id: id,
      card: card ? { name: card.name ?? null, number: card.number ?? null } : (s.card ? { name: s.card.name ?? null, number: s.card.number ?? null } : null),
      price: useOffer ? fr.amount : (rec.amount ?? fr?.amount ?? null),
      source: useOffer ? "cardmarket_fr" : (rec.source ?? (fr ? "cardmarket_fr" : null)),
      sales_count: useOffer ? null : (rec.sales_count ?? null),
      confidence: rec.confidence ?? null,
      reliability: s.reliability ?? null,
      observed_at: useOffer ? fr.observed_at : (rec.observed_at ?? null),
      fr_low: nm ?? fr?.amount ?? null,
    });
  } catch (e) {
    const err = e as ValoError;
    return json({ error: err.message }, err.status ?? 502);
  }
});
