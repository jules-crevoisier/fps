#!/usr/bin/env python3
"""Planificateur de tâches : backlog, dépendances, propriété des fichiers, vagues parallèles.

Le backlog (tasks/backlog.yaml) est la SPEC éditée à la main : ce script ne le réécrit
jamais, sauf `import` qui AJOUTE des tâches en fin de fichier. L'état d'avancement vit
dans tasks/state.json (écrit uniquement par ce script).

Deux tâches peuvent tourner en même temps si et seulement si :
  1. toutes leurs dépendances sont terminées (done ou dropped) ;
  2. leurs listes `files` sont disjointes (un fichier, un dossier ou un glob en commun = conflit).

Usage :
  python tools/tasks/plan.py validate
  python tools/tasks/plan.py status
  python tools/tasks/plan.py waves  [--max 6]
  python tools/tasks/plan.py ready  [--max 6] [--epic E1] [--ids A,B] [--json] [--brief] [--out F]
  python tools/tasks/plan.py start|done|todo ID [ID ...]
  python tools/tasks/plan.py block ID --reason "..."
  python tools/tasks/plan.py drop ID [ID ...] --reason "doublon de X"
  python tools/tasks/plan.py note ID "texte"
  python tools/tasks/plan.py prompt ID | verify-prompt ID
  python tools/tasks/plan.py import FICHIER.md [...] [--dry-run]
  python tools/tasks/plan.py board
  python tools/tasks/plan.py html [--out F]
"""
from __future__ import annotations

import argparse
import datetime as dt
import io
import json
import re
import sys
from fnmatch import fnmatch
from pathlib import Path

try:
    import yaml
except ImportError:  # pragma: no cover
    sys.exit("PyYAML manquant : python -m pip install pyyaml")

ROOT = Path(__file__).resolve().parents[2]
BACKLOG = ROOT / "tasks" / "backlog.yaml"
STATE = ROOT / "tasks" / "state.json"
BOARD = ROOT / "docs" / "tasks" / "BOARD.md"

STATUSES = ("todo", "doing", "done", "blocked", "dropped")
FINISHED = ("done", "dropped")  # « dropped » = abandonnée ou doublon : satisfait les dépendances
PRIORITY_RANK = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}
SIZE_WEIGHT = {"S": 1, "M": 2, "L": 4}
REQUIRED = ("id", "title", "epic", "files", "acceptance")

# Préfixe d'identifiant -> (épopée, priorité, modèle, agent) pour les tâches importées.
PREFIX_DEFAULTS = {
    "BUG": ("E1", "P0", "sonnet", "builder"),
    "GF": ("E2", "P1", "sonnet", "builder"),
    "MV": ("E2", "P1", "sonnet", "builder"),
    "BOT": ("E3", "P1", "sonnet", "builder"),
    "BOTFIX": ("E3", "P1", "sonnet", "builder"),
    "ART": ("E4", "P1", "sonnet", "builder"),
    "A3D": ("E4", "P2", "sonnet", "builder"),
    "UX": ("E5", "P1", "sonnet", "builder"),
    "LD": ("E6", "P2", "sonnet", "builder"),
    "TECH": ("E7", "P2", "sonnet", "builder"),
    "FUN": ("E8", "P3", "sonnet", "builder"),
}


# --------------------------------------------------------------------------- données

def load_backlog() -> dict:
    data = yaml.safe_load(BACKLOG.read_text(encoding="utf-8")) or {}
    data.setdefault("defaults", {})
    data.setdefault("epics", {})
    data.setdefault("tasks", [])
    d = data["defaults"]
    # Arbitrages du lead sur les tâches importées : champs remplacés, `add_depends_on` ajouté.
    overrides = data.get("overrides", {}) or {}
    for t in data["tasks"]:
        o = overrides.get(t.get("id"), {}) or {}
        for k, v in o.items():
            if k == "add_depends_on":
                current = list(t.get("depends_on") or [])
                t["depends_on"] = current + [x for x in v if x not in current]
            else:
                t[k] = v
    for t in data["tasks"]:
        t.setdefault("model", d.get("model", "sonnet"))
        t.setdefault("agent", d.get("agent", "builder"))
        t.setdefault("priority", d.get("priority", "P2"))
        t.setdefault("size", "M")
        t.setdefault("depends_on", [])
        t.setdefault("reads", [])
        t.setdefault("verify", [])
        t["depends_on"] = list(t["depends_on"] or [])
        t["files"] = list(t.get("files") or [])
        # Dépendances d'épopée : toute tâche de l'épopée attend ces tâches (sauf elles-mêmes).
        epic = data["epics"].get(t.get("epic"), {}) or {}
        for dep in epic.get("depends_on", []) or []:
            if dep != t["id"] and dep not in t["depends_on"]:
                t["depends_on"].append(dep)
    # Jalons : `gate: [P0, P1]` = attend toutes les autres tâches de son épopée de ces priorités.
    for t in data["tasks"]:
        prios = t.get("gate")
        if not prios:
            continue
        for o in data["tasks"]:
            if o is not t and o["epic"] == t["epic"] and o["priority"] in prios \
                    and not o.get("gate") and o["id"] not in t["depends_on"]:
                t["depends_on"].append(o["id"])
    return data


def load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {"tasks": {}}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def status_of(state: dict, tid: str) -> str:
    return state["tasks"].get(tid, {}).get("status", "todo")


def now() -> str:
    return dt.datetime.now().isoformat(timespec="seconds")


# --------------------------------------------------------------------------- fichiers

def _dir_like(p: str) -> bool:
    last = p.rstrip("/").rsplit("/", 1)[-1]
    return any(c in p for c in "*?[") or p.endswith("/") or "." not in last


def _norm(p: str) -> str:
    return p.replace("\\", "/").strip().lstrip("./") if not p.startswith("../") else p


def _base(p: str) -> str:
    for i, c in enumerate(p):
        if c in "*?[":
            p = p[:i]
            break
    return p.rstrip("/")


def paths_conflict(a: str, b: str) -> bool:
    a, b = _norm(a), _norm(b)
    if a.rstrip("/") == b.rstrip("/") or fnmatch(a, b) or fnmatch(b, a):
        return True
    ba, bb = _base(a), _base(b)
    if _dir_like(a) and (bb == ba or bb.startswith(ba + "/")):
        return True
    if _dir_like(b) and (ba == bb or ba.startswith(bb + "/")):
        return True
    return False


def tasks_conflict(t1: dict, t2: dict) -> list[tuple[str, str]]:
    return [(a, b) for a in t1["files"] for b in t2["files"] if paths_conflict(a, b)]


# --------------------------------------------------------------------------- graphe

def index(tasks: list[dict]) -> dict[str, dict]:
    return {t["id"]: t for t in tasks}


def find_cycles(tasks: list[dict]) -> list[list[str]]:
    by_id = index(tasks)
    color: dict[str, int] = {}
    cycles: list[list[str]] = []

    def visit(tid: str, stack: list[str]) -> None:
        color[tid] = 1
        stack.append(tid)
        for dep in by_id[tid]["depends_on"]:
            if dep not in by_id:
                continue
            if color.get(dep) == 1:
                cycles.append(stack[stack.index(dep):] + [dep])
            elif color.get(dep) is None:
                visit(dep, stack)
        stack.pop()
        color[tid] = 2

    for t in tasks:
        if t["id"] not in color:
            visit(t["id"], [])
    return cycles


def critical_path(tasks: list[dict], state: dict) -> dict[str, int]:
    """Longueur (pondérée par la taille) du plus long chemin restant qui DÉPEND de chaque tâche."""
    dependents: dict[str, list[str]] = {t["id"]: [] for t in tasks}
    for t in tasks:
        for dep in t["depends_on"]:
            if dep in dependents:
                dependents[dep].append(t["id"])
    by_id = index(tasks)
    memo: dict[str, int] = {}

    def length(tid: str, seen: frozenset) -> int:
        if tid in memo:
            return memo[tid]
        if tid in seen:
            return 0
        own = 0 if status_of(state, tid) in FINISHED else SIZE_WEIGHT.get(by_id[tid]["size"], 2)
        best = max((length(d, seen | {tid}) for d in dependents[tid]), default=0)
        memo[tid] = own + best
        return memo[tid]

    return {t["id"]: length(t["id"], frozenset()) for t in tasks}


def sort_key(t: dict, cp: dict[str, int]):
    return (PRIORITY_RANK.get(t["priority"], 9), -cp.get(t["id"], 0), SIZE_WEIGHT.get(t["size"], 2), t["id"])


def blocked_closure(tasks: list[dict], state: dict) -> set[str]:
    """Tâches bloquées + tout ce qui en dépend (transitivement)."""
    blocked = {t["id"] for t in tasks if status_of(state, t["id"]) == "blocked"}
    changed = True
    while changed:
        changed = False
        for t in tasks:
            if t["id"] not in blocked and any(d in blocked for d in t["depends_on"]):
                blocked.add(t["id"])
                changed = True
    return blocked


def finished_ids(tasks: list[dict], state: dict) -> set[str]:
    return {t["id"] for t in tasks if status_of(state, t["id"]) in FINISHED}


def pick_ready(tasks: list[dict], state: dict, max_n: int, done: set[str], busy: list[dict],
               epic: str | None = None, only: set[str] | None = None) -> list[dict]:
    cp = critical_path(tasks, state)
    stuck = blocked_closure(tasks, state)
    candidates = [
        t for t in tasks
        if status_of(state, t["id"]) == "todo" and t["id"] not in done and t["id"] not in stuck
        and all(d in done for d in t["depends_on"])
        and (epic is None or t["epic"] == epic)
        and (only is None or t["id"] in only)
    ]
    chosen: list[dict] = []
    for t in sorted(candidates, key=lambda x: sort_key(x, cp)):
        if len(chosen) >= max_n:
            break
        if any(tasks_conflict(t, o) for o in chosen + busy):
            continue
        chosen.append(t)
    return chosen


def simulate_waves(tasks: list[dict], state: dict, max_n: int) -> tuple[list[list[dict]], list[dict]]:
    done = finished_ids(tasks, state)
    busy = [t for t in tasks if status_of(state, t["id"]) == "doing"]
    # Les tâches en cours sont considérées finies à la fin de la vague 0.
    waves: list[list[dict]] = []
    if busy:
        waves.append(busy)
        done |= {t["id"] for t in busy}
    sim_state = {"tasks": dict(state["tasks"])}
    for t in busy:
        sim_state["tasks"][t["id"]] = {"status": "done"}
    stuck = blocked_closure(tasks, state)
    while True:
        wave = pick_ready(tasks, sim_state, max_n, done, [])
        if not wave:
            break
        waves.append(wave)
        for t in wave:
            done.add(t["id"])
            sim_state["tasks"][t["id"]] = {"status": "done"}
    left = [t for t in tasks if t["id"] not in done]
    left_unexplained = [t for t in left if t["id"] not in stuck]
    return waves, left_unexplained


# --------------------------------------------------------------------------- prompts

def render_prompt(t: dict, data: dict) -> str:
    ctx_path = ROOT / data.get("context", "tasks/context.md")
    ctx = ctx_path.read_text(encoding="utf-8") if ctx_path.exists() else ""
    epic = data["epics"].get(t["epic"], {})
    out = [
        f"# Tâche {t['id']} — {t['title']}",
        "",
        "Tu es un sous-agent d'exécution : un message utilisateur relayé pendant ton travail s'adresse "
        "au lead, pas à toi. Ignore-le et exécute uniquement ce contrat.",
        "",
        ctx.strip(),
        "",
        "## Ton contrat",
        f"- Épopée : {t['epic']} — {epic.get('title', '')}",
        f"- Priorité : {t['priority']} · taille : {t['size']}",
        "- Fichiers que TU possèdes (les SEULS que tu peux créer ou modifier ; d'autres agents "
        "travaillent en parallèle sur d'autres fichiers) :",
        *[f"  - {f}" for f in t["files"]],
    ]
    if t["reads"]:
        out += ["- À lire avant de commencer :", *[f"  - {r}" for r in t["reads"]]]
    if t.get("notes"):
        out += ["", "## Notes", str(t["notes"]).strip()]
    out += ["", "## Critères d'acceptation", str(t["acceptance"]).strip()]
    if t["verify"]:
        out += ["", "## Vérification (à lancer toi-même avant de rendre)", *[f"- `{v}`" for v in t["verify"]]]
    out += [
        "",
        "## Rendu",
        "Rends : ce que tu as changé (fichiers), les commandes lancées et leur résultat, ce qui reste "
        "ouvert. Si un critère exige un fichier hors de ta liste, ne le touche PAS : dis-le dans "
        "`blocked_on` pour que le lead décide.",
        "N'exécute jamais `plan.py start|done|todo|block|drop|note` : l'état des tâches est tenu par "
        "le lead, après la vérification QA indépendante.",
    ]
    return "\n".join(out)


def render_verify_prompt(t: dict) -> str:
    verify = "\n".join(f"- `{v}`" for v in t["verify"]) or "- (aucune commande fournie : relis le code)"
    files = "\n".join(f"- {f}" for f in t["files"])
    return (
        f"Tu es le vérificateur QA de la tâche {t['id']} — {t['title']} (jeu FPS Godot 4.7, "
        f"dépôt C:\\Users\\srko\\Desktop\\fps). Un agent affirme l'avoir terminée. Sois sceptique : "
        f"tu ne modifies RIEN, tu vérifies.\n\n"
        f"## Fichiers censés avoir changé\n{files}\n\n"
        f"## Critères d'acceptation\n{str(t['acceptance']).strip()}\n\n"
        f"## Commandes de vérification\n{verify}\n\n"
        "Lis le diff de ces fichiers (`git diff -- <fichiers>` et fichiers non suivis), lance les "
        "commandes, contrôle chaque critère un par un. Échec si : un critère n'est pas rempli, un "
        "test a été affaibli pour passer, du code mort / TODO / placeholder, une erreur Godot "
        "nouvelle dans la sortie. D'autres agents modifient d'autres fichiers en parallèle : ne juge "
        "que les fichiers de cette tâche. Rends pass=true seulement si tout est vérifié."
    )


# --------------------------------------------------------------------------- import

TASK_START = re.compile(r"^\s*-\s+id:\s*(\S+)")
KEY_LINE = re.compile(r"^\s{2,}([a-z_]+):\s*(.*)$")


def _parse_list(v: str) -> list[str]:
    v = v.strip()
    if v.startswith("[") and v.endswith("]"):
        v = v[1:-1]
    return [x.strip().strip("'\"") for x in v.split(",") if x.strip()]


def extract_tasks(md: str) -> list[dict]:
    """Extrait les tâches des blocs ``` d'un markdown (format strict demandé aux agents)."""
    tasks: list[dict] = []
    for block in re.findall(r"```[a-zA-Z]*\n(.*?)```", md, flags=re.S):
        if not re.search(r"^\s*-\s+id:", block, flags=re.M):
            continue
        cur: dict | None = None
        last_key = None
        for raw in block.splitlines():
            line = re.sub(r"\s+#\s.*$", "", raw) if not raw.strip().startswith("acceptance") else raw
            m = TASK_START.match(line)
            if m:
                cur = {"id": m.group(1).strip()}
                tasks.append(cur)
                last_key = None
                continue
            if cur is None:
                continue
            k = KEY_LINE.match(line)
            if k and k.group(1) in ("title", "files", "depends_on", "size", "acceptance", "reads",
                                    "priority", "model", "agent", "verify", "notes", "epic"):
                key, val = k.group(1), k.group(2).strip()
                if key in ("files", "depends_on", "reads", "verify"):
                    cur[key] = _parse_list(val)
                else:
                    cur[key] = val.strip("'\"") if val not in ("|", ">") else ""
                last_key = key
            elif last_key in ("acceptance", "title", "notes") and raw.strip():
                cur[last_key] = (cur.get(last_key, "") + " " + raw.strip()).strip()
    return [t for t in tasks if t.get("title")]


def cmd_import(args, data, state) -> int:
    existing = {t["id"] for t in data["tasks"]}
    added: list[dict] = []
    for f in args.files:
        path = Path(f)
        md = path.read_text(encoding="utf-8")
        for t in extract_tasks(md):
            if t["id"] in existing:
                continue
            prefix = re.match(r"[A-Z0-9]+?(?=-\d)", t["id"])
            epic, prio, model, agent = PREFIX_DEFAULTS.get(prefix.group(0) if prefix else "",
                                                           ("E0", "P2", "sonnet", "builder"))
            task = {
                "id": t["id"],
                "epic": t.get("epic") or epic,
                "title": t["title"],
                "priority": t.get("priority") or prio,
                "size": (t.get("size") or "M").upper()[:1],
                "model": t.get("model") or model,
                "agent": t.get("agent") or agent,
                "files": t.get("files", []),
                "reads": t.get("reads") or [path.as_posix()],
                "depends_on": t.get("depends_on", []),
                "acceptance": t.get("acceptance", ""),
                "source": path.as_posix(),
            }
            if t.get("verify"):
                task["verify"] = t["verify"]
            added.append(task)
            existing.add(t["id"])
    if not added:
        print("Aucune nouvelle tâche.")
        return 0
    buf = io.StringIO()
    buf.write(f"\n  # --- importé le {now()} depuis {', '.join(Path(f).as_posix() for f in args.files)}\n")
    for task in added:
        dumped = yaml.safe_dump([task], allow_unicode=True, sort_keys=False, width=100)
        buf.write("".join("  " + ln if ln.strip() else ln for ln in dumped.splitlines(True)))
    if args.dry_run:
        print(buf.getvalue())
    else:
        with BACKLOG.open("a", encoding="utf-8", newline="\n") as fh:
            fh.write(buf.getvalue())
    print(f"{len(added)} tâche(s) {'à importer' if args.dry_run else 'importée(s)'} : "
          + ", ".join(t["id"] for t in added))
    return 0


# --------------------------------------------------------------------------- commandes

def cmd_validate(args, data, state) -> int:
    tasks = data["tasks"]
    errors, warnings = [], []
    ids = [t.get("id") for t in tasks]
    for tid in {i for i in ids if ids.count(i) > 1}:
        errors.append(f"id en double : {tid}")
    # YAML garde silencieusement le DERNIER bloc d'une clé répétée : deux blocs
    # `overrides:` pour la même tâche effacent les champs du premier (incident du
    # 2026-09-24 : fichiers et dépendances d'UX-01 perdus). Détecté sur le texte brut.
    raw = BACKLOG.read_text(encoding="utf-8")
    if "\noverrides:" in raw and "\ntasks:" in raw:
        ov_text = raw[raw.index("\noverrides:"):raw.index("\ntasks:")]
        ov_keys = re.findall(r"^  ([A-Z][A-Z0-9]*-[0-9A-Z]+):", ov_text, re.M)
        for key in sorted({k for k in ov_keys if ov_keys.count(k) > 1}):
            errors.append(f"override en double (le 2e bloc efface le 1er) : {key}")
    by_id = index(tasks)
    for t in tasks:
        for k in REQUIRED:
            if not t.get(k):
                errors.append(f"{t.get('id', '?')} : champ requis manquant « {k} »")
        for d in t["depends_on"]:
            if d not in by_id:
                errors.append(f"{t['id']} dépend de {d} qui n'existe pas")
        if t["epic"] not in data["epics"]:
            errors.append(f"{t['id']} : épopée inconnue {t['epic']}")
        if t["priority"] not in PRIORITY_RANK:
            errors.append(f"{t['id']} : priorité invalide {t['priority']}")
        if t["size"] not in SIZE_WEIGHT:
            errors.append(f"{t['id']} : taille invalide {t['size']}")
    for cyc in find_cycles(tasks):
        errors.append("cycle : " + " -> ".join(cyc))
    for tid in data.get("overrides", {}) or {}:
        if tid not in by_id:
            errors.append(f"overrides vise {tid} qui n'existe pas")
    for tid in state["tasks"]:
        if tid not in by_id:
            warnings.append(f"state.json connaît {tid} absent du backlog")
    for e in errors:
        print("ERREUR  ", e)
    for w in warnings:
        print("ATTENTION", w)
    print(f"{len(tasks)} tâches, {len(errors)} erreur(s), {len(warnings)} avertissement(s).")
    return 1 if errors else 0


def cmd_status(args, data, state) -> int:
    tasks = data["tasks"]
    print(f"{'Épopée':<5} {'total':>5} {'fait':>5} {'cours':>5} {'bloq':>5}  titre")
    for eid, epic in data["epics"].items():
        et = [t for t in tasks if t["epic"] == eid]
        if not et:
            continue
        c = {s: sum(1 for t in et if status_of(state, t["id"]) == s) for s in STATUSES}
        print(f"{eid:<5} {len(et):>5} {c['done'] + c['dropped']:>5} {c['doing']:>5} {c['blocked']:>5}  "
              f"{epic.get('title', '')}")
    doing = [t for t in tasks if status_of(state, t["id"]) == "doing"]
    if doing:
        print("\nEn cours :", ", ".join(t["id"] for t in doing))
    ready = pick_ready(tasks, state, 99, finished_ids(tasks, state), doing)
    print("Prêtes  :", ", ".join(t["id"] for t in ready) or "aucune")
    return 0


def cmd_waves(args, data, state) -> int:
    waves, left = simulate_waves(data["tasks"], state, args.max)
    for i, wave in enumerate(waves):
        tag = "en cours" if i == 0 and all(status_of(state, t["id"]) == "doing" for t in wave) else f"vague {i}"
        print(f"\n== {tag} ({len(wave)} en parallèle)")
        for t in wave:
            deps = ",".join(t["depends_on"]) or "-"
            print(f"  {t['id']:<10} {t['priority']} {t['size']} {t['model']:<6} {t['title'][:70]}  [dép: {deps}]")
    if left:
        print("\nNon planifiables (dépendance manquante ou cycle) :", ", ".join(t["id"] for t in left))
    stuck = blocked_closure(data["tasks"], state)
    if stuck:
        print("Bloquées (et dépendantes) :", ", ".join(sorted(stuck)))
    return 0


def cmd_ready(args, data, state) -> int:
    tasks = data["tasks"]
    busy = [t for t in tasks if status_of(state, t["id"]) == "doing"]
    only = set(args.ids.split(",")) if args.ids else None
    chosen = pick_ready(tasks, state, args.max, finished_ids(tasks, state), busy, args.epic, only)
    if args.json or args.out:
        payload = {
            "generated": now(),
            "tasks": [{
                "id": t["id"], "title": t["title"], "model": t["model"], "agent": t["agent"],
                "isolation": t.get("isolation"), "files": t["files"],
                **({} if args.brief else {"prompt": render_prompt(t, data),
                                          "verify_prompt": render_verify_prompt(t)}),
            } for t in chosen],
        }
        text = json.dumps(payload, indent=2, ensure_ascii=False)
        if args.out:
            Path(args.out).write_text(text, encoding="utf-8")
            print(f"{len(chosen)} tâche(s) -> {args.out} : " + ", ".join(t["id"] for t in chosen))
        else:
            print(text)
    else:
        for t in chosen:
            print(f"{t['id']:<10} {t['priority']} {t['size']} {t['model']:<6} {t['title']}")
        if not chosen:
            print("Aucune tâche prête.")
    return 0


def cmd_set(args, data, state, status: str) -> int:
    by_id = index(data["tasks"])
    for tid in args.ids:
        if tid not in by_id:
            print(f"inconnue : {tid}")
            return 1
        entry = state["tasks"].setdefault(tid, {})
        entry["status"] = status
        entry[f"{status}_at"] = now()
        if status in ("blocked", "dropped") and getattr(args, "reason", None):
            entry["reason"] = args.reason
    save_state(state)
    print(f"{', '.join(args.ids)} -> {status}")
    return 0


def cmd_note(args, data, state) -> int:
    entry = state["tasks"].setdefault(args.id, {"status": "todo"})
    entry.setdefault("notes", []).append(f"{now()} {args.text}")
    save_state(state)
    return 0


def cmd_prompt(args, data, state, verify: bool = False) -> int:
    t = index(data["tasks"]).get(args.id)
    if not t:
        print(f"inconnue : {args.id}")
        return 1
    print(render_verify_prompt(t) if verify else render_prompt(t, data))
    # Notes posées par `plan.py note` (revues du lead) : elles vivent dans state.json,
    # pas dans le backlog — sans ce bloc, ni l'agent ni le vérificateur ne les voient.
    lead_notes = state.get("tasks", {}).get(args.id, {}).get("notes", [])
    if lead_notes:
        print("\n## Notes du lead (prioritaires sur le contrat en cas de conflit)\n")
        for n in lead_notes:
            print(f"- {n}")
    return 0


def cmd_board(args, data, state) -> int:
    tasks = data["tasks"]
    waves, left = simulate_waves(tasks, state, args.max)
    icon = {"todo": "·", "doing": "▶", "done": "✔", "blocked": "✖", "dropped": "—"}
    out = ["# Tableau des tâches", "",
           f"_Généré par `python tools/tasks/plan.py board` le {now()} — ne pas éditer à la main._", "",
           "| Épopée | Avancement | Fait / Total |", "|---|---|---|"]
    for eid, epic in data["epics"].items():
        et = [t for t in tasks if t["epic"] == eid]
        if not et:
            continue
        d = sum(1 for t in et if status_of(state, t["id"]) in FINISHED)
        bar = "█" * round(10 * d / len(et)) + "░" * (10 - round(10 * d / len(et)))
        out.append(f"| {eid} — {epic.get('title', '')} | `{bar}` | {d} / {len(et)} |")
    out += ["", f"## Plan en vagues (max {args.max} agents en parallèle)", ""]
    for i, wave in enumerate(waves):
        out.append(f"**Vague {i}** — " + " · ".join(f"`{t['id']}` {t['title']}" for t in wave))
        out.append("")
    if left:
        out += ["**Non planifiables** : " + ", ".join(t["id"] for t in left), ""]
    for eid, epic in data["epics"].items():
        et = [t for t in tasks if t["epic"] == eid]
        if not et:
            continue
        out += [f"## {eid} — {epic.get('title', '')}", "", str(epic.get("goal", "")).strip(), "",
                "| | Id | Tâche | Prio | Taille | Modèle | Dépend de |", "|---|---|---|---|---|---|---|"]
        for t in sorted(et, key=lambda x: (PRIORITY_RANK.get(x["priority"], 9), x["id"])):
            st = status_of(state, t["id"])
            out.append(f"| {icon[st]} | `{t['id']}` | {t['title']} | {t['priority']} | {t['size']} | "
                       f"{t['model']} | {', '.join(t['depends_on']) or '—'} |")
        out.append("")
    out += ["## Graphe des dépendances", "", "```mermaid", "graph LR"]
    for t in tasks:
        if status_of(state, t["id"]) in FINISHED:
            continue
        safe = t["id"].replace("-", "_")
        out.append(f"  {safe}[\"{t['id']}\"]")
        for d in t["depends_on"]:
            out.append(f"  {d.replace('-', '_')} --> {safe}")
    out += ["```", ""]
    BOARD.parent.mkdir(parents=True, exist_ok=True)
    BOARD.write_text("\n".join(out), encoding="utf-8")
    print(f"-> {BOARD.relative_to(ROOT).as_posix()}")
    return 0


def cmd_html(args, data, state) -> int:
    """Tableau HTML autonome (données embarquées) à partir de tools/tasks/board_template.html."""
    tasks = data["tasks"]
    waves, left = simulate_waves(tasks, state, args.max)
    epics = []
    for eid, epic in data["epics"].items():
        et = [t for t in tasks if t["epic"] == eid]
        c = {s: sum(1 for t in et if status_of(state, t["id"]) == s) for s in STATUSES}
        epics.append({"id": eid, "title": epic.get("title", ""), "total": len(et), **c})
    payload = {
        "generated": now(),
        "epics": epics,
        "waves": [[t["id"] for t in w] for w in waves],
        "unplannable": [t["id"] for t in left],
        "tasks": [{
            "id": t["id"], "title": t["title"], "epic": t["epic"], "priority": t["priority"],
            "size": t["size"], "model": t["model"], "status": status_of(state, t["id"]),
            "depends_on": t["depends_on"], "files": t["files"], "acceptance": str(t["acceptance"]).strip(),
            "source": t.get("source", ""), "reason": state["tasks"].get(t["id"], {}).get("reason", ""),
        } for t in sorted(tasks, key=lambda x: (x["epic"], PRIORITY_RANK.get(x["priority"], 9), x["id"]))],
    }
    template = (Path(__file__).parent / "board_template.html").read_text(encoding="utf-8")
    data_js = json.dumps(payload, ensure_ascii=False).replace("</", "<\\/")
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(template.replace("/*DATA*/null", data_js), encoding="utf-8")
    print(f"-> {out.as_posix()}")
    return 0


def main(argv: list[str]) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description="Planificateur de tâches du projet")
    sub = p.add_subparsers(dest="cmd", required=True)
    sub.add_parser("validate")
    sub.add_parser("status")
    for name in ("waves", "board"):
        sp = sub.add_parser(name)
        sp.add_argument("--max", type=int, default=6)
    h = sub.add_parser("html")
    h.add_argument("--max", type=int, default=6)
    h.add_argument("--out", default=str(ROOT / "reports" / "tasks" / "board.html"))
    r = sub.add_parser("ready")
    r.add_argument("--max", type=int, default=6)
    r.add_argument("--epic")
    r.add_argument("--ids")
    r.add_argument("--json", action="store_true")
    r.add_argument("--out")
    r.add_argument("--brief", action="store_true",
                   help="sans prompts : les agents les lisent via `prompt` / `verify-prompt`")
    for name in ("start", "done", "todo", "drop"):
        sp = sub.add_parser(name)
        sp.add_argument("ids", nargs="+")
        if name == "drop":
            sp.add_argument("--reason", required=True)
    b = sub.add_parser("block")
    b.add_argument("ids", nargs=1)
    b.add_argument("--reason", required=True)
    n = sub.add_parser("note")
    n.add_argument("id")
    n.add_argument("text")
    for name in ("prompt", "verify-prompt"):
        pr = sub.add_parser(name)
        pr.add_argument("id")
    im = sub.add_parser("import")
    im.add_argument("files", nargs="+")
    im.add_argument("--dry-run", action="store_true")
    args = p.parse_args(argv)

    data, state = load_backlog(), load_state()
    if args.cmd == "validate":
        return cmd_validate(args, data, state)
    if args.cmd == "status":
        return cmd_status(args, data, state)
    if args.cmd == "waves":
        return cmd_waves(args, data, state)
    if args.cmd == "board":
        return cmd_board(args, data, state)
    if args.cmd == "html":
        return cmd_html(args, data, state)
    if args.cmd == "ready":
        return cmd_ready(args, data, state)
    if args.cmd in ("start", "done", "todo", "drop"):
        return cmd_set(args, data, state, {"start": "doing", "drop": "dropped"}.get(args.cmd, args.cmd))
    if args.cmd == "block":
        return cmd_set(args, data, state, "blocked")
    if args.cmd == "note":
        return cmd_note(args, data, state)
    if args.cmd in ("prompt", "verify-prompt"):
        return cmd_prompt(args, data, state, verify=args.cmd == "verify-prompt")
    if args.cmd == "import":
        return cmd_import(args, data, state)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
