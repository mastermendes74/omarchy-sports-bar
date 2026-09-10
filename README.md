# Omarchy Sports Bar Widget

Widget para a barra do Omarchy (Quickshell) que mostra os próximos eventos e últimos resultados das tuas equipas preferidas — de qualquer desporto coberto pela ESPN (NBA, NFL, MLB, WNBA, NHL, F1) e pela TheSportsDB (futebol europeu: Liga Portugal, Champions League, Premier League...).

## ⚽ Funcionalidades

- **Próximos eventos** das tuas equipas na barra, ao lado das horas
- **Notificações antecipadas** 30 minutos antes de cada evento
- **Resultados** notificados no fim de cada jogo
- **Configuração de equipas** via popup no widget (qualquer desporto da ESPN)
- **Ícone dinâmico**: verde quando há jogo <24h, vermelho se o cache expirar

## 🏗️ Requisitos

- [Omarchy](https://omarchy.org) (shell Quickshell + Hyprland)
- Python 3.9+ (para o worker)

## 📦 Instalação

```bash
omarchy plugin add https://github.com/mendestein/omarchy-sports-bar --enable --yes
```

O plugin cria automaticamente `~/.local/state/omarchy-sports/` no primeiro arranque e começa a fazer fetch das equipas por omissão.

## ⚙️ Configurar as tuas equipas

Clica no ícone ⚽ na barra (ou no painel) para abrir o popup. Usa o formulário para adicionar equipas:

**ESPN (NBA, NFL, MLB, WNBA, NHL, F1...):**
- Provider: `espn`
- Sport: um de `basketball/nba`, `football/nfl`, `baseball/mlb`, `hockey/nhl`, `basketball/wnba`
- Team abbr: abreviatura de 2-3 letras (ex: `lal`, `ne`, `nyy`, `bos`)
- Nome: como queres ver na barra

**Futebol europeu (TheSportsDB):**
- Provider: `thesportsdb`
- Nome: pesquisa o nome (ex: "Benfica", "Porto") — clica "Pesquisar" e escolhe o resultado

**F1:**
- Provider: `f1` — mostra o próximo GP e o resultado do último

### Ficheiro directo

Também podes editar `~/.local/state/omarchy-sports/teams.json`:

```json
{
  "teams": [
    {"provider": "espn", "sport": "basketball/nba", "team": "lal", "name": "LA Lakers"},
    {"provider": "thesportsdb", "sport": "soccer", "team_id": "134114", "name": "FC Porto"},
    {"provider": "f1", "name": "Fórmula 1"}
  ]
}
```

## 🏗️ Como funciona

- `Panel.qml` — bar widget + popup (UI)
- `worker/sports_worker.py` — Python stdlib-only: consulta as APIs, escreve cache atómico, envia notificações (notify-send)
- `~/.local/state/omarchy-sports/data.json` — cache dos eventos (escrito pelo worker, lido pelo widget)
- `~/.local/state/omarchy-sports/notified.json` — ledger anti-duplicados

O worker corre como subprocesso do widget (Quickshell `execDetached`): tick a cada minuto (notificações) e fetch a cada hora (rede).

## 🏗️ APIs usadas

| Provider | Desportos | Rate limit free |
|---|---|---|
| [TheSportsDB](https://www.thesportsdb.com) | Futebol europeu | 30 req/min |
| [ESPN](https://site.api.espn.com) | NBA, NFL, MLB, WNBA, NHL, F1 | não-oficial, sem key |

## 🩺 Resolução de problemas

- **O widget não aparece na barra**: verifica `omarchy plugin list` (precisa `OMARCHY_PATH=/usr/share/omarchy`).
- **Dados antigos**: o worker faz fetch a cada hora; força com `python3 ~/.config/omarchy/plugins/mendestein.sports/worker/sports_worker.py fetch`.
- **Sem notificações**: verifica se `notify-send` funciona no teu Hyprland.

## 💝 Doar

Se este widget te for útil: [PayPal — mendestein@outlook.com](https://www.paypal.com/donate?business=mendestein@outlook.com)

## 📄 Licença

MIT