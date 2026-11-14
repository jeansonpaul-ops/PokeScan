# PokéScan v4

La vitrine de tes cartes Pokémon. Aucune clé secrète, aucun service payant.

## Architecture

| Brique | Rôle | Clé ? |
|---|---|---|
| GitHub Pages (`index.html`, `sw.js`, `manifest.json`, `icons/`) | L'appli | Aucune |
| Tesseract.js (chargé depuis jsDelivr) | Lit « MEG FR 039/132 » en bas de la carte, dans le téléphone | Aucune |
| TCGdex (`api.tcgdex.net`) | Nom, image, rareté, prix Cardmarket et TCGplayer | Aucune (API publique) |
| Supabase | Connexion et table `cards` | Clé *publishable* : publique par conception, la sécurité vient des règles RLS |
| Fonction Supabase `tcgdex` | Relais de secours si TCGdex est injoignable depuis le navigateur | Aucune |
| Fonction Supabase `valo` | Cote des cartes en français (Valo : ventes eBay, offres Cardmarket FR) | Clé Valo gratuite, cachée dans le secret `VALO_API_KEY` |

## Scan

1. La photo est recadrée sur le contour.
2. Tesseract lit la bande du bas : sigle (MEG), langue (FR), numéro (039/132).
3. TCGdex cherche les sets dont le nombre imprimé vaut 132, puis la carte 039 dans ces sets.
4. Si plusieurs sets correspondent, l'appli montre les cartes et tu touches la bonne ; elle retient ensuite le sigle.

Cartes sans code lisible (anciennes séries, promos) : bouton « Taper » ou onglet « Chercher » par nom.

## Déploiement

Sur GitHub, remplace le contenu du dépôt par `index.html`, `manifest.json`, `sw.js` et le dossier `icons/`.
Supabase est déjà configuré (schéma dans `supabase-schema.sql`, fonction dans `supabase/functions/tcgdex/`).

## Cote FR (Valo)

1. Crée une clé « Sandbox » gratuite sur https://valotcg.com/developers/account (elle commence par `vd_test_`).
2. Supabase → Edge Functions → Secrets : ajoute `VALO_API_KEY` = ta clé, et `ALLOWED_EMAILS` = ton email.
3. La cote se calcule seule à chaque nouvelle carte. Pour les cartes déjà en vitrine : Bilan → « Actualiser les prix » (45 cartes par passage).

Quota gratuit : 500 crédits et 250 cartes différentes par mois, 100 requêtes par jour, usage non commercial.
Une nouvelle carte coûte 2 crédits (identification + cote), une actualisation 1 crédit.
