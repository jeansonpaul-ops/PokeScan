// PokéScan — relais TCGdex (sans clé, sans secret)
// Utilisé seulement si le navigateur n'arrive pas à joindre api.tcgdex.net directement.
// Ne relaie que des lectures de l'API publique TCGdex v2.

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const PATH = /^v2\/[a-z]{2}(-[a-z]{2})?\/[\w.\-\/?=&:%+]{1,240}$/;

Deno.serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS });
  const { path } = await req.json().catch(() => ({ path: null }));
  if (typeof path !== "string" || !PATH.test(path) || path.includes("..")) {
    return new Response(JSON.stringify({ error: "Chemin TCGdex invalide." }), {
      status: 400,
      headers: { ...CORS, "Content-Type": "application/json" },
    });
  }
  const r = await fetch(`https://api.tcgdex.net/${path}`);
  return new Response(await r.text(), {
    status: r.status,
    headers: { ...CORS, "Content-Type": "application/json", "Cache-Control": "public, max-age=3600" },
  });
});
