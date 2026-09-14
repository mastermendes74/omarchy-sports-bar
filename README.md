# Omarchy Sports Bar Widget

Widget for the Omarchy bar (Quickshell) that shows upcoming events and recent results for your favourite teams — from sports covered by ESPN (NBA, NFL, MLB, WNBA, NHL, F1) and European football competitions.

## ⚽ Features

- **Upcoming events** for your teams in the bar, next to the clock
- **Early notifications** 30 minutes before each event
- **Result notifications** when a game ends
- **Team configuration** through the widget popup
- **Dynamic icon**: green when a game starts within 24 hours, red when the cache expires

## 🏗️ Requirements

- [Omarchy](https://omarchy.org) (shell Quickshell + Hyprland)
- Python 3.9+ (for the worker)

## 📦 Installation

```bash
omarchy plugin add https://github.com/mendestein/omarchy-sports-bar --enable --yes
```

The plugin automatically creates `~/.local/state/omarchy-sports/` on first launch. No teams are selected by default; choose your favourite teams in the widget.

To remove the plugin:

```bash
omarchy plugin remove mendestein.sports
rm -rf ~/.local/state/omarchy-sports
```

## ⚙️ Configuring your teams

Click the ⚽ icon in the bar to open the popup. Select a sport, then select a country or competition for football, and choose teams from the catalogue:

**ESPN (NBA, NFL, MLB, WNBA, NHL, F1...):**
- Provider: `espn`
- Sport: one of `basketball/nba`, `football/nfl`, `baseball/mlb`, `hockey/nhl`, `basketball/wnba`
- Team ID or abbreviation: for example `lal`, `ne`, `nyy`, or `bos`
- Name: the name shown in the bar

**European football (ESPN):**
- Provider: `espn`
- Sport: a competition such as `soccer/por.1`, `soccer/eng.1`, or `soccer/esp.1`
- Select a country or competition first, then choose a team from the list

**F1:**
- Provider: `f1` — shows the next Grand Prix and the latest result

### Direct file configuration

You can also edit `~/.local/state/omarchy-sports/teams.json` directly:

```json
{
  "teams": [
    {"provider": "espn", "sport": "basketball/nba", "team": "lal", "name": "LA Lakers"},
    {"provider": "espn", "sport": "soccer/por.1", "team": "437", "name": "FC Porto"},
    {"provider": "f1", "name": "Formula 1"}
  ]
}
```

## 🏗️ How it works

- `Panel.qml` — bar widget and popup UI
- `worker/sports_worker.py` — stdlib-only Python worker that queries APIs, writes the cache atomically, and sends notifications with `notify-send`
- `~/.local/state/omarchy-sports/data.json` — event cache written by the worker and read by the widget
- `~/.local/state/omarchy-sports/notified.json` — notification de-duplication ledger

The worker runs as a widget subprocess (Quickshell `execDetached`): it checks notifications every minute and fetches network data hourly.

## 🏗️ APIs

| Provider | Sports | Free-tier rate limit |
|---|---|---|
| [TheSportsDB](https://www.thesportsdb.com) | Team search fallback | 30 req/min |
| [ESPN](https://site.api.espn.com) | NBA, NFL, MLB, WNBA, NHL, F1, European football | Unofficial, no key required |

## 🩺 Troubleshooting

- **Widget does not appear in the bar**: check `omarchy plugin list`.
- **Stale data**: the worker fetches hourly; force a refresh with `python3 ~/.config/omarchy/plugins/mendestein.sports/worker/sports_worker.py fetch`.
- **No notifications**: verify that `notify-send` works in your Hyprland session.

## 💝 Donate

If this widget is useful to you: [PayPal — mendestein@outlook.com](https://www.paypal.com/donate?business=mendestein@outlook.com)

## 📄 License

MIT