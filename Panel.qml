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
  property bool fetchQueued: false
  property var queuedTeams: []
  property int reloadAttempts: 0
  property string searchOutput: ""
  property var searchResults: []
  property string newTeamProvider: "espn"
  property string newTeamSport: "basketball/nba"
  property string newTeamName: ""
  property string newTeamId: ""
  property string selectedSport: "basketball/nba"
  property string selectedFootballCountry: ""
  property string sportFilter: ""
  property bool showOnlyFavorites: false
  property var catalog: ({})
  readonly property var sportCatalog: [
    { key: "basketball/nba", icon: "🏀", label: "NBA" },
    { key: "football/nfl", icon: "🏈", label: "NFL" },
    { key: "baseball/mlb", icon: "⚾", label: "MLB" },
    { key: "hockey/nhl", icon: "🏒", label: "NHL" },
    { key: "basketball/wnba", icon: "🏀", label: "WNBA" },
    { key: "soccer", icon: "⚽", label: "European football" }
  ]
  readonly property var filteredCatalogTeams: {
    var league = catalog[selectedSport]
    var teams = league && league.teams ? league.teams : []
    if (selectedSport === "soccer") {
      var country = (league && league.countries || []).find(function(c) {
        return c.key === root.selectedFootballCountry
      })
      teams = country && country.teams ? country.teams : []
    }
    readonly property var favoriteEventNames: teams.map(function(t) { return (t.name || "").toLowerCase() })
    if (sportFilter !== "") {
      var f = sportFilter.toLowerCase()
      teams = teams.filter(function(t){
        return (t.name || "").toLowerCase().indexOf(f) !== -1 ||
          (t.abbr || "").toLowerCase().indexOf(f) !== -1 ||
          (t.league || "").toLowerCase().indexOf(f) !== -1
      })
    }
      if (showOnlyFavorites) {
        teams = teams.filter(function(t) { return root.isFavorite(t) })
      }
      return teams
  }

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
    onLoaded: if (!root.busy) root.loadTeams()
    onLoadFailed: if (!root.busy) root.loadTeams()
    onFileChanged: { teamsFile.reload() }
  }
  FileView {
    id: catalogFile
    path: Quickshell.env("HOME") + "/.local/state/omarchy-sports/catalog.json"
    watchChanges: false
    onLoaded: {
      try {
        var parsed = JSON.parse(catalogFile.text())
        catalog = parsed || {}
        if (root.selectedSport === "" && root.sportCatalog.length > 0) {
          root.selectedSport = root.sportCatalog[0].key
        }
        if (root.selectedFootballCountry === "" && root.footballCountries().length > 0) {
          root.selectedFootballCountry = root.footballCountries()[0].key
        }
      } catch (e) { catalog = {} }
    }
    onLoadFailed: {
      catalog = {}
    }
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
  function ensureCatalog() {
    if (Object.keys(catalog).length === 0) {
      Quickshell.execDetached(["bash", "-c", "mkdir -p ~/.local/state/omarchy-sports && " + workerPath + " catalog"])
      catalogRefreshTimer.restart()
    }
  }
  Component.onCompleted: {
    ensureCatalog()
    catalogFile.reload()
  }
  Timer {
    id: catalogRefreshTimer
    interval: 3000
    onTriggered: {
      catalogFile.reload()
      if (Object.keys(catalog).length > 0 && root.selectedSport === "") {
        root.selectedSport = root.sportCatalog[0].key
      }
      if (root.selectedFootballCountry === "" && root.footballCountries().length > 0) {
        root.selectedFootballCountry = root.footballCountries()[0].key
      }
    }
  }
  function loadTeams() {
    try {
      var d = JSON.parse(teamsFile.text())
      teams = (d && d.teams) || []
      if (teams.length === 0) events = []
    }
    catch (e) { teams = [] }
  }
  function loadEvents() {
    try { var d = JSON.parse(dataFile.text()); events = (d && d.events) || []; lastUpdated = d.updated || ""
      stale = lastUpdated ? ((Date.now() - new Date(lastUpdated).getTime())/1000 > 7200) : false }
    catch (e) { stale = true }
  }
  function eventBelongsToFavorites(event) {
    if (root.teams.length === 0) return false
    var home = (event.home || "").toLowerCase()
    var away = (event.away || "").toLowerCase()
    return root.teams.some(function(t) {
      var name = (t.name || "").toLowerCase()
      return name !== "" && (home === name || away === name || home.indexOf(name) !== -1 || away.indexOf(name) !== -1)
    })
  }
  function sportIcon(sport) {
    var value = (sport || "").toLowerCase()
    if (value.indexOf("basketball") === 0) return "🏀"
    if (value.indexOf("football") === 0) return "🏈"
    if (value.indexOf("baseball") === 0) return "⚾"
    if (value.indexOf("hockey") === 0) return "🏒"
    if (value.indexOf("soccer") === 0) return "⚽"
    if (value.indexOf("racing") === 0) return "🏎"
    return "🏅"
  }
  function displayEvents(kind) {
    var candidates = root.events.filter(function(e) {
      return root.eventBelongsToFavorites(e) && e.kind === kind &&
        (kind !== "upcoming" || (e.kickoff_utc && new Date(e.kickoff_utc) > new Date()))
    })
    candidates.sort(function(a, b) {
      var left = a.kickoff_utc || ""
      var right = b.kickoff_utc || ""
      return kind === "upcoming"
        ? (left > right ? 1 : -1)
        : (right > left ? 1 : -1)
    })
    var counts = {}
    var selected = []
    candidates.forEach(function(event) {
      var matchingTeams = root.teams.filter(function(team) {
        var name = (team.name || "").toLowerCase()
        var home = (event.home || "").toLowerCase()
        var away = (event.away || "").toLowerCase()
        return name !== "" && (home === name || away === name ||
          home.indexOf(name) !== -1 || away.indexOf(name) !== -1)
      })
      if (matchingTeams.some(function(team) {
        return (counts[team.name] || 0) < 2
      })) {
        selected.push(event)
        matchingTeams.forEach(function(team) {
          counts[team.name] = (counts[team.name] || 0) + 1
        })
      }
    })
    return selected
  }
  function saveTeams() {
    busy = true
    events = []
    lastUpdated = ""
    stale = true
    var payload = JSON.stringify({teams: teams}, null, 1)
    var command = "mkdir -p ~/.local/state/omarchy-sports && cat > " + teamsPath +
      " << 'SPORTS_JSON'\n" + payload + "\nSPORTS_JSON\n" +
      "python3 " + workerPath + " " + (teams.length === 0 ? "clear" : "fetch")
    Quickshell.execDetached(["bash", "-c", command])
    reloadAttempts = 0
    reloadTimer.restart()
  }
  Timer {
    id: reloadTimer
    interval: 1000
    onTriggered: {
      teamsFile.reload()
      dataFile.reload()
      root.loadEvents()
      reloadAttempts += 1
      if (busy && reloadAttempts < 30) {
        reloadTimer.restart()
      } else {
        busy = false
      }
    }
  }
  function removeTeam(index) {
    var t = teams.slice()
    t.splice(index, 1)
    teams = t
    saveTeams()
  }
  function addTeam(provider, sport, teamId, name) {
    var exists = teams.some(function(t) {
      return t.provider === provider && t.sport === sport &&
        (t.team || t.team_id || "") === teamId
    })
    if (exists) {
      addingTeam = false
      return
    }
    var t = {provider: provider, name: name}
    if (provider === "espn") { t.sport = sport; t.team = teamId }
    else if (provider === "thesportsdb") { t.sport = "soccer"; t.team_id = teamId }
    else if (provider === "f1") { }
    var updatedTeams = teams.slice()
    updatedTeams.push(t)
    teams = updatedTeams
    saveTeams()
  }
  function isFavorite(team) {
    return root.teams.some(function(t) {
      if (root.selectedSport === "soccer") {
        return t.provider === "espn" && t.sport === team.sport &&
          (t.team || "").toLowerCase() === (team.abbr || "").toLowerCase()
      }
      return t.provider === "espn" && t.sport === root.selectedSport &&
        (t.team || "").toLowerCase() === (team.abbr || "").toLowerCase()
    })
  }
  function footballCountries() {
    var soccer = root.catalog.soccer
    return soccer && soccer.countries ? soccer.countries : []
  }
  function doSearch(name) {
    var safeName = (name || "").trim()
    if (safeName === "") {
      searchResults = []
      busy = false
      return
    }
    busy = true
    searchResults = []
    var quoted = JSON.stringify(safeName)
    Quickshell.execDetached(["bash", "-c", workerPath + " search thesportsdb " + quoted + " > /tmp/sports_search.txt"])
    searchReadTimer.restart()
  }
  Timer {
    id: searchReadTimer
    interval: 4000
    onTriggered: {
      var lines = []
      try {
        var xhr = new XMLHttpRequest()
        xhr.open("GET", "file:///tmp/sports_search.txt", false)
        xhr.send()
        var text = xhr.responseText || ""
        lines = text.split("\n").filter(function(l){ return l.trim() !== "" })
      } catch(e) { lines = [] }
      searchResults = lines.map(function(l) {
        var trimmed = l.trim()
        var parts = trimmed.split(/\s+/)
        return {id: parts[0] || "", name: trimmed}
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
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: panelColumn
          width: parent.width
          spacing: Style.space(12)

          // -------- próximos eventos --------
          Text {
            text: "⚽ Upcoming events"
            color: root.foreground
            font.family: root.bar.fontFamily
            font.pixelSize: Style.font.body
            font.bold: true
          }

          Repeater {
            model: root.displayEvents("upcoming")
            delegate: Row {
              width: panelColumn.width
              height: Math.max(Style.space(22), eventText.implicitHeight)
              clip: true
              spacing: Style.space(8)
              Text { text: root.sportIcon(modelData.sport); color: root.foreground; font.pixelSize: Style.font.caption }
              Text {
                id: eventText
                width: parent.width - Style.space(24)
                text: (modelData.kickoff_local || "") + "  " + (modelData.event || "")
                color: root.foreground
                font.family: root.bar.fontFamily
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
          }

          Text {
            visible: root.displayEvents("upcoming").length === 0
            text: "No upcoming events"
            color: Qt.darker(root.foreground, 1.4)
            font.pixelSize: Style.font.body
          }

          // -------- resultados --------
          Text {
            text: "🏁 Latest results"
            color: root.foreground
            font.letterSpacing: 1
            font.pixelSize: Style.font.body
          }

          Repeater {
            model: root.displayEvents("finished").filter(function(e) {
              return e.home_score !== null && e.home_score !== undefined
            })
            delegate: Row {
              width: panelColumn.width
              height: Style.space(22)
              clip: true
              spacing: Style.space(8)
              Text { text: root.sportIcon(modelData.sport); color: root.foreground; font.pixelSize: Style.font.caption }
              Text {
                width: Style.space(92)
                text: modelData.kickoff_local || "--/-- --:--"
                color: root.foreground
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 1
              }
              Text {
                width: parent.width - Style.space(128)
                text: modelData.home + " " + modelData.home_score + " - " +
                  modelData.away_score + " " + modelData.away
                color: root.foreground
                font.pixelSize: Style.font.caption
                elide: Text.ElideRight
                maximumLineCount: 1
              }
            }
          }

          Rectangle { height: 1; width: parent.width; color: Qt.alpha(root.foreground, 0.15) }

          // -------- favorite teams --------
          Row {
            spacing: Style.space(8)
            Text {
              text: "⭐ Favorite teams"
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
              width: panelColumn.width
              height: Style.space(22)
              clip: true
              required property var modelData
              required property int index
              spacing: Style.space(6)
              Text {
                text: "•"
                color: Qt.darker(root.foreground, 1.4)
                font.pixelSize: Style.font.body
              }
              Text {
                width: parent.width - Style.space(42)
                text: modelData.name || modelData.team || modelData.team_id || "?"
                color: root.foreground
                font.pixelSize: Style.font.body
                elide: Text.ElideRight
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
            text: "No teams configured — click + to add"
            color: Qt.darker(root.foreground, 1.4)
            font.pixelSize: Style.font.body
          }

          // -------- add team: sports list -> teams with logos --------
          Column {
            visible: root.addingTeam
            spacing: Style.space(8)
            width: parent.width

            // sports list
            Column {
              width: parent.width
              spacing: Style.space(6)
              Repeater {
                model: root.sportCatalog
                delegate: Rectangle {
                  required property var modelData
                  property bool selected: root.selectedSport === modelData.key
                  width: panelColumn.width
                  height: Style.space(24)
                  radius: Math.min(4, Style.cornerRadius)
                  color: selected ? Style.hoverFillFor(root.foreground, Color.accent) : (sportHover.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent")
                  TapHandler {
                    onTapped: {
                      root.selectedSport = modelData.key
                      root.sportFilter = ""
                      root.selectedFootballCountry = modelData.key === "soccer" && root.footballCountries().length
                        ? root.footballCountries()[0].key : ""
                    }
                  }
                  HoverHandler { id: sportHover; cursorShape: Qt.PointingHandCursor }
                  Text {
                    id: sportIcon
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.icon
                    font.pixelSize: Style.font.body
                  }
                  Text {
                    id: sportLabel
                    anchors.left: sportIcon.right
                    anchors.leftMargin: Style.space(4)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.label
                    color: root.foreground
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }

            // filter + teams with logos
            Column {
              visible: root.selectedSport === "soccer"
              width: parent.width
              spacing: Style.space(4)
              Text {
                text: "Country / competition"
                color: Qt.darker(root.foreground, 1.3)
                font.pixelSize: Style.font.caption
              }
              Repeater {
                model: root.footballCountries()
                delegate: Rectangle {
                  required property var modelData
                  width: parent ? parent.width : 300
                  height: Style.space(26)
                  radius: Math.min(4, Style.cornerRadius)
                  color: root.selectedFootballCountry === modelData.key
                    ? Style.hoverFillFor(root.foreground, Color.accent)
                    : "transparent"
                  TapHandler {
                    onTapped: {
                      root.selectedFootballCountry = modelData.key
                      root.sportFilter = ""
                    }
                  }
                  Text {
                    anchors.left: parent.left
                    anchors.leftMargin: Style.space(6)
                    anchors.verticalCenter: parent.verticalCenter
                    text: modelData.name
                    color: root.foreground
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
            Row {
              width: panelColumn.width
              spacing: Style.space(6)
              Rectangle {
                width: panelColumn.width - favoriteFilterText.implicitWidth - Style.space(18)
                height: Style.space(24)
                color: Qt.alpha(root.foreground, 0.08)
                radius: Math.min(4, Style.cornerRadius)
                TextInput {
                  id: filterField
                  anchors.fill: parent; anchors.margins: 4
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                  text: root.sportFilter
                  onTextChanged: root.sportFilter = text
                }
                Text {
                  visible: root.sportFilter === ""
                  anchors.verticalCenter: parent.verticalCenter; anchors.left: parent.left; anchors.leftMargin: 6
                  text: "Filter teams…"; color: Qt.darker(root.foreground, 1.5); font.pixelSize: Style.font.caption
                }
              }
              Rectangle {
                width: favoriteFilterText.implicitWidth + Style.space(12)
                height: Style.space(24)
                radius: Math.min(4, Style.cornerRadius)
                color: root.showOnlyFavorites ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                TapHandler { onTapped: root.showOnlyFavorites = !root.showOnlyFavorites }
                Text {
                  id: favoriteFilterText
                  anchors.centerIn: parent
                  text: root.showOnlyFavorites ? "★ Favorites" : "☆ Favorites"
                  color: root.foreground
                  font.pixelSize: Style.font.caption
                }
              }
            }

            Column {
              visible: root.selectedSport !== ""
              spacing: Style.space(4)
              width: parent.width
              Repeater {
                model: root.filteredCatalogTeams
                delegate: Rectangle {
                  required property var modelData
                  width: panelColumn.width
                  height: Style.space(30)
                  radius: Math.min(4, Style.cornerRadius)
                  color: teamPickArea.containsMouse ? Style.hoverFillFor(root.foreground, Color.accent) : "transparent"
                  TapHandler {
                    onTapped: {
                      var provider = "espn"
                      var sport = root.selectedSport === "soccer" ? modelData.sport : root.selectedSport
                      root.addTeam(provider, sport, modelData.id || modelData.abbr, modelData.name)
                    }
                  }
                  HoverHandler { id: teamPickArea; cursorShape: Qt.PointingHandCursor }
                  Row {
                    id: teamRow
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: Style.space(6)
                    anchors.rightMargin: Style.space(24)
                    spacing: Style.space(8)
                    Image {
                      source: modelData.logo
                      width: Style.space(18); height: Style.space(18)
                      fillMode: Image.PreserveAspectFit
                      asynchronous: true
                    }
                    Text {
                      text: modelData.name
                      color: root.foreground
                      font.pixelSize: Style.font.caption
                      elide: Text.ElideRight
                      width: teamRow.width - Style.space(26)
                    }
                  }
                  Text {
                    anchors.right: parent.right; anchors.rightMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    text: "+"; color: root.foreground; font.pixelSize: Style.font.body
                  }
                }
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
            Text { id: donateText; anchors.centerIn: parent; text: "♥ Donate via PayPal"; color: root.foreground; font.pixelSize: Style.font.caption }
          }
        }
      }
    }
  }
}