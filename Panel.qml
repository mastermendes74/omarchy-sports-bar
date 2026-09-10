import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

Panel {
  id: root
  moduleName: "mendestein.sports"
  ipcTarget: "mendestein.sports"
  manageIpc: false

  // ---- estado ----
  property var teams: []
  property var events: []
  property string lastUpdated: ""
  property bool stale: false
  property bool addingTeam: false
  property bool busy: false
  property string searchOutput: ""
  property var searchResults: []
  property string newTeamProvider: "espn"
  property string newTeamSport: "basketball/nba"
  property string newTeamName: ""
  property string newTeamId: ""

  readonly property string teamsPath: Quickshell.env("HOME") + "/.local/state/omarchy-sports/teams.json"
  readonly property string dataPath: Quickshell.env("HOME") + "/.local/state/omarchy-sports/data.json"
  readonly property string workerPath: Quickshell.env("HOME") + "/.config/omarchy/plugins/mendestein.sports/worker/sports_worker.py"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  implicitWidth: sportsBtn.implicitWidth
  implicitHeight: sportsBtn.implicitHeight

  // ---- próximo evento / último resultado ----
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
  readonly property real hoursUntil: nextEvent && nextEvent.kickoff_utc
      ? (new Date(nextEvent.kickoff_utc) - Date.now()) / 3600000 : 9999
  readonly property string state: stale ? "stale" : (hoursUntil < 24 ? "upcoming" : (lastResult ? "result" : "idle"))

  // ---- PayPal donate ----
  readonly property string donateUrl:
    "https://www.paypal.com/cgi-bin/webscr?cmd=_donations"
    + "&business=mendestein%40outlook.com"
    + "&item_name=mendestein.sports%20omarchy%20plugin"
    + "&currency_code=EUR&no_shipping=1"

  // ---- ficheiros ----
  FileView {
    id: teamsFile
    path: root.teamsPath
    watchChanges: true
    atomicWrites: true
    onLoaded: root.loadTeams()
    onLoadFailed: root.loadTeams()
    onFileChanged: { teamsFile.reload() }
  }
  FileView {
    id: dataFile
    path: root.dataPath
    watchChanges: true
    onLoaded: root.loadEvents()
    onFileChanged: dataFile.reload()
  }


  // ---- funções ----
  function log(msg) { console.log("sports-widget:", msg) }
  function loadTeams() {
    try { var d = JSON.parse(teamsFile.text()); teams = (d && d.teams) || [] }
    catch (e) { teams = [] }
  }
  function loadEvents() {
    try { var d = JSON.parse(dataFile.text()); events = (d && d.events) || []; lastUpdated = d.updated || ""
      stale = lastUpdated ? ((Date.now() - new Date(lastUpdated).getTime())/1000 > 7200) : false }
    catch (e) { stale = true }
  }
  function saveTeams() {
    busy = true
    Quickshell.execDetached(["bash", "-c",
      "mkdir -p ~/.local/state/omarchy-sports && cat > " + teamsPath + " << 'EOJSON'\n" +
      JSON.stringify({teams: teams}, null, 1) + "\nEOJSON\n" + workerPath + " fetch"])
    // recarregar após o fetch
    reloadTimer.restart()
  }
  Timer {
    id: reloadTimer
    interval: 5000
    onTriggered: { teamsFile.reload(); dataFile.reload(); busy = false }
  }
  function removeTeam(index) {
    var t = teams.slice()
    t.splice(index, 1)
    teams = t
    saveTeams()
  }
  function addTeam(provider, sport, teamId, name) {
    var t = {provider: provider, name: name}
    if (provider === "espn") { t.sport = sport; t.team = teamId }
    else if (provider === "thesportsdb") { t.sport = "soccer"; t.team_id = teamId }
    else if (provider === "f1") { }
    teams.push(t)
    saveTeams()
  }
  function doSearch(name) {
    busy = true
    Quickshell.execDetached(["bash", "-c", workerPath + " search thesportsdb '" + name.replace(/[\'";]/g, "") + "' > /tmp/sports_search.txt"])
    searchReadTimer.restart()
  }
  Timer {
    id: searchReadTimer
    interval: 4000
    onTriggered: {
      var lines = []
      try {
        var content = ""
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/sports_search.txt", false)
        xhr.send()
        lines = xhr.responseText.split("\n").filter(function(l){ return l.trim() !== "" })
      } catch(e) {}
      searchResults = lines.map(function(l) {
        var parts = l.split(/\s+/)
        return {id: parts[0], name: l}
      })
      busy = false
    }
  }

  // ---- bar icon + popup ----
  BarIconButton {
    id: sportsBtn
    bar: root.bar
    text: "⚽"
    slotSize: Style.bar.statusSlot
    tooltipText: "Sports events"
    active: root.state === "upcoming"
    activeColor: "#4caf50"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) root.runFetch()
      else root.toggle()
    }
  }

  function runFetch() {
    Quickshell.execDetached(["bash", "-c", root.workerPath + " fetch"])
  }

  KeyboardPanel {
    id: panel
    anchorItem: sportsBtn
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

          // -------- próximos eventos --------
          Text {
            text: "⚽ Próximos eventos"
            color: root.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: {
              var now = new Date()
              var up = root.events.filter(function(e) {
                return e.kind === "upcoming" && e.kickoff_utc && new Date(e.kickoff_utc) > now
              })
              up.sort(function(a,b){ return a.kickoff_utc > b.kickoff_utc ? 1 : -1 })
              return up.slice(0, 5)
            }
            delegate: Row {
              spacing: Style.space(8)
              Text { text: "⏳"; color: root.foreground; font.pixelSize: Style.font.caption }
              Text {
                text: (modelData.kickoff_local || "") + "  " + (modelData.event || "")
                color: root.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
              }
            }
          }

          Text {
            visible: root.events.filter(function(e){ return e.kind === "upcoming" }).length === 0
            text: "Sem eventos próximos"
            color: Qt.darker(root.foreground, 1.4)
            font.pixelSize: Style.font.body
          }

          // -------- resultados --------
          Text {
            text: "🏁 Últimos resultados"
            color: root.foreground
            font.letterSpacing: 1
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: {
              var fin = root.events.filter(function(e) {
                return e.kind === "finished" && e.home_score !== null && e.home_score !== undefined
              })
              fin.sort(function(a,b){ return (b.kickoff_utc||"") > (a.kickoff_utc||"") ? 1 : -1 })
              return fin.slice(0, 5)
            }
            delegate: Row {
              spacing: Style.space(8)
              Text { text: "🏁"; color: root.foreground; font.pixelSize: Style.font.caption }
              Text {
                text: modelData.home + " " + modelData.home_score + " - " + modelData.away_score + " " + modelData.away
                color: root.foreground
                font.pixelSize: Style.font.body
              }
            }
          }

          Rectangle { height: 1; width: parent.width; color: Qt.alpha(root.foreground, 0.15) }

          // -------- equipas preferidas --------
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

          Repeater {
            model: root.teams
            delegate: Row {
              required property var modelData
              required property int index
              spacing: Style.space(6)
              Text {
                text: "•"
                color: Qt.darker(root.foreground, 1.4)
                font.pixelSize: Style.font.body
              }
              Text {
                text: (modelData.name || modelData.team || modelData.team_id || "?") + "  [" + (modelData.provider || "?") + "]"
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

          Text {
            visible: root.teams.length === 0
            text: "Nenhuma equipa configurada — clica + para adicionar"
            color: Qt.darker(root.foreground, 1.4)
            font.pixelSize: Style.font.body
          }

          // -------- form adicionar --------
          Column {
            visible: root.addingTeam
            spacing: Style.space(8)
            width: parent.width

            Row {
              spacing: Style.space(6)
              Text { text: "Provider:"; color: root.foreground; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Repeater {
                model: ["espn", "thesportsdb", "f1"]
                delegate: Rectangle {
                  required property string modelData
                  property bool selected: root.newTeamProvider === modelData
                  width: provText.implicitWidth + Style.space(10); height: Style.space(20)
                  radius: Math.min(4, Style.cornerRadius)
                  color: selected ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  TapHandler { onTapped: { root.newTeamProvider = modelData; root.searchResults = [] } }
                  HoverHandler { cursorShape: Qt.PointingHandCursor }
                  Text { id: provText; anchors.centerIn: parent; text: modelData; color: root.foreground; font.pixelSize: Style.font.caption }
                }
              }
            }

            Row {
              visible: root.newTeamProvider === "espn"
              spacing: Style.space(6)
              Text { text: "Sport:"; color: root.foreground; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Rectangle {
                width: Style.space(240); height: Style.space(22)
                color: Qt.alpha(root.foreground, 0.08)
                radius: Math.min(4, Style.cornerRadius)
                TextInput {
                  id: sportField
                  anchors.fill: parent; anchors.margins: 4
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                  text: root.newTeamSport
                  onTextChanged: root.newTeamSport = text
                }
              }
            }

            Row {
              visible: root.newTeamProvider !== "f1"
              spacing: Style.space(6)
              Text { text: "Nome:"; color: root.foreground; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Rectangle {
                width: Style.space(180); height: Style.space(22)
                color: Qt.alpha(root.foreground, 0.08)
                radius: Math.min(4, Style.cornerRadius)
                TextInput {
                  id: nameField
                  anchors.fill: parent; anchors.margins: 4
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                }
              }
              Rectangle {
                width: searchBtn.implicitWidth + Style.space(12); height: Style.space(22)
                radius: Math.min(4, Style.cornerRadius)
                color: searchArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                TapHandler { onTapped: root.doSearch(nameField.text) }
                HoverHandler { id: searchArea; cursorShape: Qt.PointingHandCursor }
                Text { id: searchBtn; anchors.centerIn: parent; text: "Pesquisar"; color: root.foreground; font.pixelSize: Style.font.caption }
              }
            }

            Column {
              visible: root.searchResults.length > 0
              spacing: Style.space(4)
              width: parent.width
              Repeater {
                model: root.searchResults
                delegate: Rectangle {
                  required property var modelData
                  width: parent ? parent.width : 200; height: Style.space(20)
                  radius: Math.min(4, Style.cornerRadius)
                  color: pickArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  TapHandler {
                    onTapped: {
                      var parts = modelData.id.split(/\s+/)
                      root.addTeam("thesportsdb", "soccer", parts[0], modelData.name.replace(parts[0], "").trim())
                      root.searchResults = []
                    }
                  }
                  HoverHandler { id: pickArea; cursorShape: Qt.PointingHandCursor }
                  Text { anchors.verticalCenter: parent.verticalCenter; text: modelData.name; color: root.foreground; font.pixelSize: Style.font.caption }
                }
              }
            }

            Row {
              visible: root.newTeamProvider === "espn"
              spacing: Style.space(6)
              Text { text: "Team abbr:"; color: root.foreground; font.pixelSize: Style.font.caption; anchors.verticalCenter: parent.verticalCenter }
              Rectangle {
                width: Style.space(120); height: Style.space(22)
                color: Qt.alpha(root.foreground, 0.08)
                radius: Math.min(4, Style.cornerRadius)
                TextInput {
                  id: teamIdField
                  anchors.fill: parent; anchors.margins: 4
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                }
              }
              Rectangle {
                width: addBtn.implicitWidth + Style.space(12); height: Style.space(22)
                radius: Math.min(4, Style.cornerRadius)
                color: addArea2.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                TapHandler { onTapped: root.addTeam("espn", root.newTeamSport, teamIdField.text, nameField.text || teamIdField.text) }
                HoverHandler { id: addArea2; cursorShape: Qt.PointingHandCursor }
                Text { id: addBtn; anchors.centerIn: parent; text: "Adicionar"; color: root.foreground; font.pixelSize: Style.font.caption }
              }
            }
          }

          Rectangle { height: 1; width: parent.width; color: Qt.alpha(root.foreground, 0.2) }

          // -------- donate --------
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