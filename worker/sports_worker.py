#!/usr/bin/env python3
"""sports_worker.py — worker stdlib-only do widget Omarchy sports-bar (v2 multi-provider).

Subcomandos:
  fetch   — consulta APIs das equipas configuradas (ESPN + TheSportsDB + Jolpica)
  tick    — verifica janelas de notificação (pré-kickoff / pós-fim), notify-send
  search <desporto> <nome> — pesquisa team/sport IDs

Só stdlib. Estado:
  ~/.local/state/omarchy-sports/teams.json     — equipas preferidas
  ~/.local/state/omarchy-sports/data.json      — cache de eventos (escrito pelo worker)
  ~/.local/state/omarchy-sports/notified.json  — ledger anti-duplicados

Formato teams.json:
{"teams": [
  {"provider": "espn", "sport": "basketball/nba", "team": "lal", "name": "LA Lakers"},
  {"provider": "thesportsdb", "sport": "soccer", "team_id": "134114", "name": "FC Porto"},
  {"provider": "f1", "name": "Ferrari"}
]}
"""
import json, os, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone, timedelta
from urllib.parse import quote_plus
from zoneinfo import ZoneInfo

HOME = os.path.expanduser("~/.local/state/omarchy-sports")
os.makedirs(HOME, exist_ok=True)
TEAMS_F = os.path.join(HOME, "teams.json")
DATA_F = os.path.join(HOME, "data.json")
NOTIF_F = os.path.join(HOME, "notified.json")

TSDB = "https://www.thesportsdb.com/api/v1/json/123"
ESPN = "https://site.api.espn.com/apis/site/v2/sports"
UA = {"User-Agent": "curl/8.5.0"}  # ESPN bloqueia outros UA
TZ = ZoneInfo("Europe/Lisbon")

DEFAULT_TEAMS = {"teams": []}

def ensure_state_files():
    if not os.path.exists(TEAMS_F):
        atomic_write(TEAMS_F, DEFAULT_TEAMS)
    if not os.path.exists(DATA_F):
        atomic_write(DATA_F, {"schema_version": 2, "updated": None, "events": []})
    if not os.path.exists(NOTIF_F):
        atomic_write(NOTIF_F, {"sent": []})


def atomic_write(path, data):
    tmp = path + ".tmp"
    with open(tmp, "w") as f: json.dump(data, f, ensure_ascii=False, indent=1)
    os.replace(tmp, path)


def load_json(path, default):
    try:
        with open(path, "r", encoding="utf-8") as fh:
            return json.load(fh)
    except Exception:
        return default

def http_json(url, retries=2):
    delay = 2
    for _ in range(retries):
        try:
            req = urllib.request.Request(url, headers=UA)
            return json.load(urllib.request.urlopen(req, timeout=15))
        except Exception as e:
            if "429" in str(e):
                time.sleep(delay); delay *= 2; continue
            print(f"  ! {url.split('/')[-1]}: {str(e)[:80]}", flush=True)
            return None
    return None

def norm(provider, sport, event_id, name, kickoff_utc, status, home, away,
         hs, as_, league, extra=None):
    return {
        "id": f"{provider}:{event_id}", "provider": provider, "sport": sport,
        "event": name, "league": league or "",
        "home": home or "", "away": away or "",
        "home_score": hs, "away_score": as_,
        "status": status or "", "kind": kind_of(status),
        "kickoff_utc": kickoff_utc,
        "kickoff_local": local_pt(kickoff_utc) if kickoff_utc else None,
        **(extra or {})
    }

def kind_of(status):
    s = (status or "").upper()
    if s in ("FT", "FINAL", "FINISHED", "MATCH_FINISHED", "STATUS_FULL_TIME"):
        return "finished"
    if s in ("NS", "SCHEDULED", "STATUS_SCHEDULED", ""):
        return "upcoming"
    return "live"

def local_pt(iso_utc):
    try:
        dt = datetime.fromisoformat(iso_utc.replace("Z",""))
        if dt.tzinfo is None: dt = dt.replace(tzinfo=timezone.utc)
        return dt.astimezone(TZ).strftime("%a %d/%m %H:%M")
    except Exception: return None

# ---------- ESPN (NBA, NFL, MLB, WNBA, NHL, ...) ----------
def fetch_espn(team):
    sport_path = team["sport"]  # ex: "basketball/nba"
    tid = resolve_espn_team_id(sport_path, team["team"])
    if sport_path.startswith("soccer/"):
        today = datetime.now(timezone.utc).date()
        end = today + timedelta(days=60)
        start_s = today.strftime("%Y%m%d")
        end_s = end.strftime("%Y%m%d")
        schedule = http_json(f"{ESPN}/{sport_path}/teams/{tid}/schedule?limit=100") or {}
        scoreboard = http_json(
            f"{ESPN}/{sport_path}/scoreboard?dates={start_s}-{end_s}&limit=100"
        ) or {}
        schedule_events = schedule.get("events") or []
        events = list(schedule_events)
        known_ids = {str(e.get("id")) for e in events}
        for event in scoreboard.get("events") or []:
            competitors = (event.get("competitions") or [{}])[0].get("competitors") or []
            if any(str((c.get("team") or {}).get("id")) == str(tid) for c in competitors):
                if str(event.get("id")) not in known_ids:
                    events.append(event)
    else:
        d = http_json(f"{ESPN}/{sport_path}/teams/{tid}/schedule")
        if not d: return []
        events = d.get("events") or []
    out = []
    now = datetime.now(timezone.utc)
    for e in events:
        comps = (e.get("competitions") or [{}])[0]
        cs = comps.get("competitors") or []
        home = away = hs = as_ = None
        for c in cs:
            nm = (c.get("team") or {}).get("displayName","")
            sc = c.get("score")
            if isinstance(sc, dict): sc = sc.get("displayValue")
            if isinstance(sc, dict): sc = sc.get("displayValue")
            if isinstance(sc, str) and sc.isdigit(): sc = int(sc)
            if c.get("homeAway") == "home":
                home, hs = nm, sc
            else:
                away, as_ = nm, sc
        status_obj = (e.get("status") or comps.get("status") or {}).get("type") or {}
        status = status_obj.get("shortDetail","") or status_obj.get("state","")
        date = e.get("date")
        try:
            dt = datetime.fromisoformat(date.replace("Z","+00:00")) if date else None
            if dt and dt.tzinfo is None: dt = dt.replace(tzinfo=timezone.utc)
        except Exception: dt = None
        if dt is None:
            kind, status = "upcoming", "NS"
        elif dt < now:
            kind = "finished" if (hs is not None or as_ is not None) else "upcoming"
        else:
            kind, status = "upcoming", "NS"
        out.append(norm("espn", sport_path, e.get("id"), e.get("name",""),
                        iso_utc(dt) if dt else None, status, home, away, hs, as_,
                        (e.get("league") or {}).get("name","")))
    return out

def resolve_espn_team_id(sport_path, team_id):
    value = str(team_id or "").strip()
    if value.isdigit():
        return value
    catalog = load_json(os.path.join(HOME, "catalog.json"), {})
    league = catalog.get(sport_path) or {}
    for item in league.get("teams", []):
        if str(item.get("abbr", "")).lower() == value.lower():
            return str(item.get("id", value))
    return value

def iso_utc(dt):
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

# ---------- TheSportsDB (futebol europeu, etc) ----------
def fetch_tsdb(team):
    tid = team["team_id"]
    out = []
    nxt = http_json(f"{TSDB}/eventsnext.php?id={tid}") or {}
    lst = http_json(f"{TSDB}/eventslast.php?id={tid}") or {}
    time.sleep(1)
    for e in (nxt.get("events") or []):
        out.append(norm("thesportsdb", team.get("sport","soccer"), e["idEvent"], e.get("strEvent",""),
                        ts_to_utc(e.get("strTimestamp")), "NS",
                        e.get("strHomeTeam",""), e.get("strAwayTeam",""), None, None,
                        e.get("strLeague","")))
    for e in (lst.get("results") or []):
        out.append(norm("thesportsdb", team.get("sport","soccer"), e["idEvent"], e.get("strEvent",""),
                        ts_to_utc(e.get("strTimestamp")), e.get("strStatus"),
                        e.get("strHomeTeam",""), e.get("strAwayTeam",""),
                        e.get("intHomeScore"), e.get("intAwayScore"), e.get("strLeague","")))
    return out

def ts_to_utc(ts):
    if not ts: return None
    try: return datetime.fromisoformat(ts.replace("Z","")).strftime("%Y-%m-%dT%H:%M:%SZ")
    except Exception: return None

# ---------- F1 (ESPN scoreboard) ----------
def fetch_f1(team):
    out = []
    d = http_json(f"{ESPN}/racing/f1/scoreboard")
    if not d: return out
    for e in (d.get("events") or []):
        status = ((e.get("status") or {}).get("type") or {}).get("shortDetail","")
        out.append(norm("espn-f1", "racing/f1", e.get("id"), e.get("name",""),
                        e.get("date"), status, "", "", None, None, "Formula 1"))
    return out

PROVIDERS = {
    "espn": fetch_espn,
    "thesportsdb": fetch_tsdb,
    "f1": fetch_f1,
}

def dedupe_events(events):
    merged = {}
    for e in events:
        eid = e.get("id")
        if not eid:
            continue
        prev = merged.get(eid)
        if prev is None:
            merged[eid] = e
            continue
        # Prefer the most complete record: keep non-empty metadata and more recent status.
        if len(str(e)) > len(str(prev)):
            merged[eid] = e
    return list(merged.values())


def fetch():
    ensure_state_files()
    teams = load_json(TEAMS_F, DEFAULT_TEAMS).get("teams", [])
    all_events = {}
    for t in teams[:20]:
        provider = t.get("provider", "thesportsdb")
        fn = PROVIDERS.get(provider)
        if not fn:
            print(f"  ! provider desconhecido: {provider}"); continue
        try:
            for e in fn(t):
                all_events[e["id"]] = e
        except Exception as ex:
            print(f"  ! erro fetch {t.get('name')}: {str(ex)[:100]}", flush=True)
        time.sleep(3)  # serializar requests (ESPN rate-limits por IP)
    payload = {"schema_version": 2, "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
               "events": dedupe_events(list(all_events.values()))}
    atomic_write(DATA_F, payload)
    print(f"fetch: {len(payload['events'])} eventos de {len(teams)} equipas", flush=True)

def clear():
    ensure_state_files()
    atomic_write(DATA_F, {
        "schema_version": 2,
        "updated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "events": [],
    })
    atomic_write(NOTIF_F, {"sent": []})
    print("clear: event cache emptied", flush=True)


def tick():
    ensure_state_files()
    try:
        data = load_json(DATA_F, {"events": []})
    except Exception:
        return
    notified = load_json(NOTIF_F, {"sent": []})
    sent = set(notified.get("sent", []) or [])
    new = []
    for e in data.get("events", []):
        # pré-kickoff: <30 min para começar
        pre_key = f"pre:{e['id']}"
        if e.get("kickoff_utc") and pre_key not in sent and e.get("kind") in ("upcoming", "live"):
            try:
                ko = datetime.fromisoformat(e["kickoff_utc"].replace("Z", "+00:00"))
                dt = ko.astimezone(timezone.utc) - datetime.now(timezone.utc)
                if timedelta(0) <= dt <= timedelta(minutes=30):
                    notify(f"⚽ {e['event']}", f"{e['kickoff_local']} — {e['league']}")
                    sent.add(pre_key)
                    new.append(pre_key)
            except Exception:
                pass
        # resultado
        res_key = f"res:{e['id']}"
        if e.get("kind") == "finished" and e.get("home_score") is not None and res_key not in sent:
            notify(f"🏁 {e['home']} {e['home_score']}-{e['away_score']} {e['away']}", e["league"])
            sent.add(res_key)
            new.append(res_key)
    if new:
        notified["sent"] = list((sent | set(new)))[-500:]
        atomic_write(NOTIF_F, notified)

def notify(title, body=""):
    os.system(f'notify-send "{title}" "{body}" 2>/dev/null')


def catalog():
    """Gera catalog.json com equipas ESPN e principais ligas de futebol."""
    out = {}
    sports = [("basketball","nba"),("football","nfl"),("hockey","nhl"),("baseball","mlb"),("basketball","wnba")]
    for sport, league in sports:
        key = f"{sport}/{league}"
        try:
            d = http_json(f"https://sports.core.api.espn.com/v2/sports/{sport}/leagues/{league}/teams?limit=100")
            teams = []
            for it in (d or {}).get('items', []):
                ref = it.get('$ref','')
                try:
                    t = http_json(ref)
                    logos = t.get('logos') or []
                    teams.append({"abbr": t.get('abbreviation',''), "name": t.get('displayName',''),
                                  "id": t.get('id',''), "logo": logos[0].get('href','') if logos else ''})
                except Exception: pass
                time.sleep(0.15)
            out[key] = {"league": league, "teams": teams}
            print(f"catalog: {key} -> {len(teams)}", flush=True)
        except Exception as e:
            print(f"catalog {key}: ERRO {e}", flush=True)
    football_leagues = [
        ("soccer/por.1", "Portugal", "Primeira Liga"),
        ("soccer/eng.1", "England", "Premier League"),
        ("soccer/esp.1", "Spain", "La Liga"),
        ("soccer/ger.1", "Germany", "Bundesliga"),
        ("soccer/ita.1", "Italy", "Serie A"),
        ("soccer/uefa.champions", "Europe", "Champions League"),
    ]
    football_teams = []
    football_countries = []
    for key, country, league in football_leagues:
        try:
            sport, league_key = key.split("/", 1)
            d = http_json(f"https://sports.core.api.espn.com/v2/sports/{sport}/leagues/{league_key}/teams?limit=100") or {}
            teams = []
            for item in d.get("items") or []:
                t = http_json(item.get("$ref", "")) or {}
                logos = t.get("logos") or []
                team = {"id": t.get("id", ""), "abbr": t.get("abbreviation", ""),
                        "name": t.get("displayName", ""), "league": league,
                        "logo": logos[0].get("href", "") if logos else "",
                        "country": country, "sport": key}
                if team["id"] and team["name"]:
                    teams.append(team)
                    football_teams.append(team)
            football_countries.append({"key": key, "name": f"{country} — {league}", "country": country, "teams": teams})
            out[key] = {"league": league, "teams": teams}
            print(f"catalog: {key} -> {len(teams)}", flush=True)
            time.sleep(0.2)
        except Exception as e:
            print(f"catalog {key}: ERRO {e}", flush=True)
    out["soccer"] = {"league": "European football", "countries": football_countries}
    path = os.path.join(HOME, "catalog.json")
    atomic_write(path, out)
    total = sum(len(v.get("teams", [])) for v in out.values())
    total += sum(len(c.get("teams", [])) for c in out.get("soccer", {}).get("countries", []))
    print(f"catalog.json: {total} equipas")

def search(provider, name):
    if not name or not name.strip():
        print("(introduz um nome para pesquisar)")
        return
    if provider == "espn":
        # espn team search: usar lista de leagues conhecidas → teams/{abbr}
        print("ESPN: usar abreviatura da equipa (ex: lal, bos, ne). Leagues: basketball/nba, football/nfl, baseball/mlb, hockey/nhl, basketball/wnba")
        return
    clean_name = quote_plus(name.strip())
    d = http_json(f"{TSDB}/searchteams.php?t={clean_name}")
    teams = (d or {}).get("teams") or []
    if not teams:
        print("(sem resultados — free tier limita a 1, pode estar errado)")
        return
    for t in teams[:8]:
        print(f"{t.get('idTeam', '')}  {t.get('strTeam', '')}  ({t.get('strLeague', '')})")

if __name__ == "__main__":
    cmd = sys.argv[1] if len(sys.argv) > 1 else "fetch"
    if cmd == "fetch": fetch()
    elif cmd == "clear": clear()
    elif cmd == "tick": tick()
    elif cmd == "search" and len(sys.argv) > 3: search(sys.argv[2], sys.argv[3])
    elif cmd == "catalog": catalog()
    else: print("uso: fetch | tick | search <provider> <nome>")
