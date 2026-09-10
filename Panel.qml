import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mendestein.sports"
  ipcTarget: "mendestein.sports"
  manageIpc: false

  property var teams: []
  property var events: []
  property string lastUpdated: ""
  property bool stale: false
  property bool addingTeam: false
  property string selectedSport: ""
  property string searchFilter: ""
  property var catalog: ({})
  readonly property string catalogPath: Quickshell.env("HOME") + "/.local/state/omarchy-sports/catalog.json"
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  readonly property var nextEvent: {
    var now = new Date()
    var up = events.filter(function(e) {
      return e.kind === "upcoming" && e.kickoff_utc && new Date(e.kickoff_utc) > now
    })
    up.sort(function(a,b){ return a.kickoff_utc > b.kickoff_utc ? 1 : -1 })
    return up.length ? up[0] : null
  }
  readonly property var lastResult: {
    var fin = events.filter(function(e) {
      return e.kind === "finished" && e.home_score !== null && e.home_score !== undefined
    })
    fin.sort(function(a,b){ return (b.kickoff_utc||"") > (a.kickoff_utc||"") ? 1 : -1 })
    return fin.length ? fin[0] : null
  }
  readonly property string barLabel: nextEvent
      ? ((nextEvent.kickoff_local || "") + " " + (nextEvent.event || "")).substring(0, 30)
      : ""

  readonly property string donateUrl:
    "https://www.paypal.com/cgi-bin/webscr?cmd=_donations"
    + "&business=mendestein%40outlook.com"
    + "&item_name=mendestein.sports%20omarchy%20widget"
    + "&currency_code=EUR&no_shipping=1"

  FileView {
    id: teamsFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy-sports/teams.json"
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadTeams()
    onFileChanged: teamsFile.reload()
  }
  FileView {
    id: dataFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy-sports/data.json"
    watchChanges: true
    onLoaded: root.loadEvents()
    onFileChanged: dataFile.reload()
  }

  FileView {
    id: catalogFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy-sports/catalog.json"
    watchChanges: true
    onLoaded: root.loadCatalog()
    onFileChanged: catalogFile.reload()
  }
  function loadCatalog() {
    try { catalog = JSON.parse(catalogFile.text()) || {} } catch (e) { catalog = {} }
  }
  function loadTeams() {
    try { var d = JSON.parse(teamsFile.text()); teams = (d && d.teams) || [] } catch (e) { teams = [] }
  }
  function loadEvents() {
    try {
      var d = JSON.parse(dataFile.text())
      events = (d && d.events) || []
      lastUpdated = d.updated || ""
      stale = lastUpdated ? ((Date.now() - new Date(lastUpdated).getTime())/1000 > 7200) : false
    } catch (e) { stale = true }
  }
  function runFetch() { Quickshell.execDetached(["python3", Quickshell.env("HOME") + "/.config/omarchy/plugins/mendestein.sports/worker/sports_worker.py", "fetch"]) }
  function saveTeams() {
    Quickshell.execDetached(["bash", "-c",
      "cat > " + Quickshell.env("HOME") + "/.local/state/omarchy-sports/teams.json << 'EOJSON'\n" +
      JSON.stringify({teams: teams}, null, 1) + "\nEOJSON\n" +
      "sleep 2 && python3 " + Quickshell.env("HOME") + "/.config/omarchy/plugins/mendestein.sports/worker/sports_worker.py fetch"])
  }
  function addTeamEspn(sport, abbr, name, logo) {
    var t = teams.slice()
    t.push({provider: "espn", sport: sport, team: abbr, name: name, logo: logo})
    teams = t
    saveTeams()
  }
  function removeTeam(index) {
    var t = teams.slice(); t.splice(index, 1); teams = t; saveTeams()
  }

  IpcHandler {
    target: "mendestein.sports"
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { runFetch(); return "ok" }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: "⚽"
    tooltipText: root.barLabel || "Sports events"
    active: state === "upcoming"
    activeColor: "#4caf50"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) runFetch()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(panelColumn.implicitHeight, Style.space(600))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: panelColumn.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
          id: panelColumn
          width: parent.width
          spacing: Style.space(12)

          Text {
            text: "⚽ Próximos eventos"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: {
              var now = new Date()
              var up = events.filter(function(e) {
                return e.kind === "upcoming" && e.kickoff_utc && new Date(e.kickoff_utc) > now
              })
              up.sort(function(a,b){ return a.kickoff_utc > b.kickoff_utc ? 1 : -1 })
              return up.slice(0, 5)
            }
            delegate: Row {
              spacing: Style.space(6)
              Text { text: "⏳"; color: root.dim; font.pixelSize: Style.font.caption }
              Text {
                text: (modelData.kickoff_local || "") + " " + (modelData.event || "")
                color: root.foreground
                font.pixelSize: Style.font.body
              }
            }
          }

          Text {
            visible: events.filter(function(e){ return e.kind === "upcoming" }).length === 0
            text: "Sem eventos próximos"
            color: root.dim
            font.pixelSize: Style.font.body
          }

          Text {
            text: "🏁 Últimos resultados"
            color: root.foreground
            font.letterSpacing: 1
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: {
              var fin = events.filter(function(e) {
                return e.kind === "finished" && e.home_score !== null && e.home_score !== undefined
              })
              fin.sort(function(a,b){ return (b.kickoff_utc||"") > (a.kickoff_utc||"") ? 1 : -1 })
              return fin.slice(0, 5)
            }
            delegate: Row {
              spacing: Style.space(6)
              Text { text: "🏁"; color: root.dim; font.pixelSize: Style.font.caption }
              Text {
                text: modelData.home + " " + modelData.home_score + " - " + modelData.away_score + " " + modelData.away
                color: root.foreground
                font.pixelSize: Style.font.body
              }
            }
          }

          Rectangle { height: 1; width: parent.width; color: Qt.alpha(root.foreground, 0.15) }

          Row {
            spacing: Style.space(8)
            Text {
              text: "⭐ Equipas preferidas"
              color: root.foreground
              font.letterSpacing: 1
              font.pixelSize: Style.font.body
            }
            Rectangle {
              width: Style.space(18); height: Style.space(18)
              radius: Math.min(4, Style.cornerRadius)
              color: addArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
              TapHandler { onTapped: root.addingTeam = !root.addingTeam }
              HoverHandler { id: addArea; cursorShape: Qt.PointingHandCursor }
              Text { anchors.centerIn: parent; text: root.addingTeam ? "✕" : "+"; color: root.foreground; font.pixelSize: Style.font.caption }
            }
          }

          // -------- secção de adição de equipas --------
          Column {
            visible: root.addingTeam
            width: parent.width
            spacing: Style.space(10)

            Text {
              text: "Escolhe o desporto:"
              color: root.dim
              font.pixelSize: Style.font.caption
            }

            // lista de desportos com ícones
            Repeater {
              model: [
                {key: "basketball/nba", label: "NBA", icon: "🏀"},
                {key: "football/nfl", label: "NFL", icon: "🏈"},
                {key: "baseball/mlb", label: "MLB", icon: "⚾"},
                {key: "hockey/nhl", label: "NHL", icon: "🏒"},
                {key: "basketball/wnba", label: "WNBA", icon: "🏀"}
              ]
              delegate: Rectangle {
                required property var modelData
                width: parent.width; height: Style.space(28)
                radius: Math.min(6, Style.cornerRadius)
                color: root.selectedSport === modelData.key ? Style.selectedFillFor(root.foreground, Color.accent) : (hover.hovered ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                HoverHandler { id: hover; cursorShape: Qt.PointingHandCursor }
                TapHandler { onTapped: root.selectedSport = modelData.key }
                Row {
                  anchors.verticalCenter: parent.verticalCenter
                  anchors.left: parent.left
                  anchors.leftMargin: Style.space(10)
                  spacing: Style.space(10)
                  Text { text: modelData.icon; font.pixelSize: Style.font.body }
                  Text { text: modelData.label; color: root.foreground; font.pixelSize: Style.font.body }
                }
              }
            }

            // lista de equipas desse desporto com emblemas + filtro
            Column {
              visible: root.selectedSport !== ""
              width: parent.width
              spacing: Style.space(4)

              Rectangle {
                width: parent.width; height: Style.space(24)
                color: Style.hoverFillFor(root.foreground, Color.accent)
                radius: Math.min(4, Style.cornerRadius)
                TextInput {
                  anchors.fill: parent; anchors.margins: 4
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                  onTextChanged: root.searchFilter = text
                }
              }

              Repeater {
                model: {
                  var c = (root.catalog || {})[root.selectedSport]
                  if (!c || !c.teams) return []
                  var f = root.searchFilter.toLowerCase()
                  if (!f) return c.teams
                  return c.teams.filter(function(t) {
                    return t.name.toLowerCase().indexOf(f) !== -1 || (t.abbr || "").toLowerCase().indexOf(f) !== -1
                  })
                }
                delegate: Row {
                  required property var modelData
                  width: parent.width
                  height: Style.space(30)
                  spacing: Style.space(10)

                  Image {
                    width: Style.space(20); height: Style.space(20)
                    source: modelData.logo || ""
                    fillMode: Image.PreserveAspectFit
                    anchors.verticalCenter: parent.verticalCenter
                  }
                  Text {
                    text: modelData.name
                    color: root.foreground
                    font.pixelSize: Style.font.body
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width - Style.space(70)
                    elide: Text.ElideRight
                  }
                  Rectangle {
                    width: Style.space(20); height: Style.space(20)
                    radius: Math.min(4, Style.cornerRadius)
                    color: addHover.containsMouse ? "#4caf50" : "transparent"
                    anchors.verticalCenter: parent.verticalCenter
                    TapHandler {
                      onTapped: root.addTeamEspn(root.selectedSport, modelData.abbr, modelData.name, modelData.logo)
                    }
                    HoverHandler { id: addTm; cursorShape: Qt.PointingHandCursor }
                    Text { anchors.centerIn: parent; text: "+"; color: "#4caf50"; font.pixelSize: Style.font.body }
                  }
                }
              }
            }
          }

          Text { visible: false }
          }

          Repeater {
            model: root.teams
            delegate: Row {
              required property var modelData
              spacing: Style.space(8)
              Image {
                width: Style.space(18); height: Style.space(18)
                source: modelData.logo || ""
                visible: !!modelData.logo
                fillMode: Image.PreserveAspectFit
              }
              Text {
                text: modelData.name
                color: root.foreground
                font.pixelSize: Style.font.body
              }
              Rectangle {
                width: Style.space(16); height: Style.space(16)
                radius: Math.min(4, Style.cornerRadius)
                color: delArea.containsMouse ? "#f44336" : "transparent"
                TapHandler { onTapped: root.removeTeam(index) }
                HoverHandler { id: delArea; cursorShape: Qt.PointingHandCursor }
                Text { anchors.centerIn: parent; text: "✕"; color: "#f44336"; font.pixelSize: Style.font.caption }
              }
            }
          }

          Rectangle { height: 1; width: parent.width; color: Qt.alpha(root.foreground, 0.2) }

          Rectangle {
            width: donateText.implicitWidth + Style.space(16)
            height: Style.space(26)
            radius: Math.min(6, Style.cornerRadius)
            color: donateArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
            border.color: Qt.alpha(root.foreground, 0.3)
            border.width: 1
            TapHandler { onTapped: Quickshell.execDetached(["xdg-open", root.donateUrl]) }
            HoverHandler { id: donateArea; cursorShape: Qt.PointingHandCursor }
            Text { id: donateText; anchors.centerIn: parent; text: "♥ Doar via PayPal"; color: root.foreground; font.pixelSize: Style.font.caption }
          }
        }
      }
    }
  }
}
