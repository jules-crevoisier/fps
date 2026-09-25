## ShopRules.gd
## Garde-fous de monétisation en code (FUN-08, docs/research/05_fun_retention.md
## §2.5 « Battle pass, loot boxes, régulation UE/France, mineurs » + §4 point 5
## « Monétisation pas encore bornée par le code »). Ce module ne rend rien et
## ne vend rien : il refuse une `offer` AVANT tout affichage boutique ou appel
## Steam (le futur ShopUI, hors périmètre FUN-08, doit appeler `validate()` en
## tout premier, jamais après coup).
##
## Sources exactes (chaque règle de `violations()` cite l'une d'entre elles —
## voir SOURCES, testé par tests/meta/test_shop_rules.gd : la citation n'est
## pas qu'un commentaire, elle est vérifiée) :
##  - PEGI, juin 2026 : un « paid random item » (loot box, pack, roue) exige au
##    moins PEGI 16 ; une offre limitée dans le TEMPS ou en QUANTITÉ exige au
##    moins PEGI 12 (docs/research/05_fun_retention.md §2.5, sources Reed
##    Smith / Wccftech). Notre jeu vise PEGI 12 (thème cartoon) : aucun objet
##    aléatoire payant, aucune offre à minuteur ni à stock limité.
##  - UE, Digital Fairness Act (DFA), proposition attendue T4 2026 : prix réels
##    affichés (en euros) à côté de toute monnaie virtuelle, fenêtre de
##    confirmation avant achat (docs/research/05_fun_retention.md §2.5,
##    sources Freshfields / CADE). Conséquence : pas de monnaie premium qui
##    maquille le prix réel, `currency` doit être EUR.
##  - France, JONUM (loi SREN du 21 mai 2024, décret n° 2026-60 du 4 février
##    2026) : le régime ne vise que les objets MONÉTISABLES, c'est-à-dire
##    échangeables ou convertibles (docs/research/05_fun_retention.md §2.5,
##    sources ANJ / Bird & Bird). Des cosmétiques liés au compte et non
##    échangeables en sortent : `tradable` doit rester faux.
##
## `validate()` est PUR (aucune E/S, aucun état) : un champ interdit
## SIMPLEMENT PRÉSENT dans `offer` suffit à la refuser, sans égard à sa valeur
## pour `expires_at`/`stock_limit` (une offre honnête ne porte pas ces clés du
## tout).
class_name ShopRules
extends RefCounted

## Citations utilisées par `violations()` — voir la doc d'en-tête. Clé par
## régulation (PEGI/DFA/JONUM) plutôt que par champ d'offre : plusieurs règles
## peuvent citer la même source (ex. `expires_at` et `stock_limit` citent
## toutes deux PEGI).
const SOURCES := {
	"PEGI": "PEGI, juin 2026 : objet aléatoire payant >= PEGI 16 ; offre à minuteur ou à stock limité >= PEGI 12 (Reed Smith, Wccftech).",
	"DFA": "UE, Digital Fairness Act, proposition attendue T4 2026 : prix réels en euros affichés à côté de toute monnaie virtuelle (Freshfields, CADE).",
	"JONUM": "France, loi SREN, décret n° 2026-60 du 4 février 2026 : régime déclenché par des objets monétisables/échangeables — nos cosmétiques restent liés au compte (ANJ, Bird & Bird).",
}

## Seule monnaie affichable (DFA : prix réels en euros, pas de monnaie
## premium qui maquille le coût).
const ALLOWED_CURRENCY := "EUR"

## Vrai si `offer` respecte tous les garde-fous de monétisation. Équivalent à
## `violations(offer).is_empty()` — voir cette fonction pour la raison
## précise d'un refus.
static func validate(offer: Dictionary) -> bool:
	return violations(offer).is_empty()

## Liste (jamais vide si `validate()` est faux) des règles violées par
## `offer`, chacune citant sa source (SOURCES). Utilisée par le futur ShopUI
## pour expliquer un refus, et par tests/meta/test_shop_rules.gd pour vérifier
## la bonne règle plutôt qu'un simple booléen.
static func violations(offer: Dictionary) -> Array[String]:
	var out: Array[String] = []
	if bool(offer.get("random", false)):
		out.append("random=true : objet aléatoire payant interdit -- %s" % SOURCES["PEGI"])
	if offer.has("expires_at"):
		out.append("expires_at présent : offre à minuteur interdite -- %s" % SOURCES["PEGI"])
	if offer.has("stock_limit"):
		out.append("stock_limit présent : offre à stock limité interdite -- %s" % SOURCES["PEGI"])
	if String(offer.get("currency", "")) != ALLOWED_CURRENCY:
		out.append("currency != EUR : monnaie premium ou non affichée en euros interdite -- %s" % SOURCES["DFA"])
	if bool(offer.get("tradable", false)):
		out.append("tradable=true : cosmétique échangeable interdit -- %s" % SOURCES["JONUM"])
	return out
