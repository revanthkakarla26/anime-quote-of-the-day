import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Anime quote of the day, with the character's picture. The day's quote is
// dealt from a date-seeded shuffle of quotes.json, so every quote gets a day
// before any repeats. Pictures are cached in images/ by fetch-images.py, so
// nothing goes online; the only running cost is a once-a-minute date check.
BarWidget {
  id: root
  moduleName: "reva.animequote"

  readonly property bool showName: setting("showName", false)
  readonly property bool notifyDaily: setting("notify", true)
  readonly property real maxLabelWidth: setting("maxLabelWidth", 140)

  readonly property string pluginDir: decodeURIComponent(String(Qt.resolvedUrl(".")).replace(/^file:\/\//, "")).replace(/\/$/, "")
  readonly property string stateFile: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/reva.animequote/announced"

  property var characters: ({})
  property var quotes: []
  property string today: dateKey()
  // A quote rolled from the popup or the launcher; -1 shows today's.
  property int rolled: -1

  readonly property int dailyIndex: dailyIndexFor(today, quotes.length)
  readonly property int index: rolled >= 0 && rolled < quotes.length ? rolled : dailyIndex
  readonly property var quote: index >= 0 ? quotes[index] : null
  readonly property var character: quote && characters[quote.by] ? characters[quote.by] : ({})
  readonly property string imagePath: imageFor(character)

  readonly property real avatarSize: Math.max(14, barSize - Style.space(7))

  property bool popupOpen: false
  function close() { popupOpen = false }

  implicitWidth: vertical ? barSize : row.implicitWidth + Style.space(14)
  implicitHeight: vertical ? avatarSize + Style.space(10) : barSize

  function dateKey() {
    return Qt.formatDate(new Date(), "yyyy-MM-dd")
  }

  function glyph(codepoint) {
    return String.fromCodePoint(codepoint)
  }

  function imageFor(info) {
    return info && info.image ? pluginDir + "/images/" + info.image : ""
  }

  // mulberry32, a small seedable PRNG (Math.random can't be seeded), driving
  // a Fisher-Yates shuffle of the quote indexes.
  function shuffled(count, seed) {
    var state = seed >>> 0
    function next() {
      state = (state + 0x6D2B79F5) >>> 0
      var t = state
      t = Math.imul(t ^ (t >>> 15), t | 1)
      t ^= t + Math.imul(t ^ (t >>> 7), t | 61)
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296
    }
    var deck = []
    for (var i = 0; i < count; i++) deck.push(i)
    for (var j = count - 1; j > 0; j--) {
      var k = Math.floor(next() * (j + 1))
      var swap = deck[j]
      deck[j] = deck[k]
      deck[k] = swap
    }
    return deck
  }

  // Each round of `count` days deals the whole deck in a fresh order. If a
  // round would open with the quote the previous one ended on, its first two
  // cards trade places so no quote shows two days running.
  function dailyIndexFor(key, count) {
    if (count <= 0) return -1
    var parts = key.split("-")
    var day = Math.floor(Date.UTC(+parts[0], +parts[1] - 1, +parts[2]) / 86400000)
    var round = Math.floor(day / count)
    var deck = shuffled(count, round + 1)
    if (count > 2 && deck[0] === shuffled(count, round)[count - 1]) {
      var first = deck[0]
      deck[0] = deck[1]
      deck[1] = first
    }
    return deck[day % count]
  }

  // A random quote other than the one showing, from another character when possible.
  function roll() {
    if (quotes.length < 2) return
    var pick = index
    for (var tries = 0; tries < 12 && (pick === index || quotes[pick].by === quote.by); tries++)
      pick = Math.floor(Math.random() * quotes.length)
    rolled = pick === index ? (index + 1) % quotes.length : pick
  }

  function showToday() {
    rolled = -1
    popupOpen = true
  }

  function load(raw) {
    try {
      var data = JSON.parse(raw)
      var chars = data.characters || {}
      characters = chars
      quotes = (data.quotes || []).filter(function(q) { return q && q.text && chars[q.by] })
    } catch (e) {
      console.warn("reva.animequote: quotes.json is not valid JSON:", e)
    }
    if (rolled >= quotes.length) rolled = -1
    announceSoon.restart()
  }

  function tooltipText() {
    if (!quote) return "No quotes loaded"
    var text = quote.text.length > 140 ? quote.text.slice(0, 137) + "…" : quote.text
    return "“" + text + "” — " + character.name
  }

  function escapeMarkup(text) {
    return String(text).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
  }

  // On multi-monitor setups only the first bar's instance announces.
  function isPrimary() {
    var items = bar && typeof bar.moduleWidgets === "function" ? bar.moduleWidgets(moduleName) : [root]
    return items.length === 0 || items[0] === root
  }

  // Announce today's quote once a day: at the first login of the day, or at
  // midnight when the machine is on. The state file holds the last date
  // announced, so shell restarts don't repeat it; it's only written once the
  // notification went out. Clicking the notification opens the popup.
  function announce(force) {
    if (dailyIndex < 0 || notifier.running) return
    if (!force && (!notifyDaily || !isPrimary())) return
    var q = quotes[dailyIndex]
    var info = characters[q.by]
    var args = ["-a", "Anime Quote", "-t", "12000", "-A", "default=Show"]
    var icon = imageFor(info)
    if (icon) args.push("-i", icon)
    args.push(info.name + " · " + info.anime, "“" + escapeMarkup(q.text) + "”")
    notifier.command = ["bash", "-c", announceScript, "reva-animequote", stateFile, today, force ? "1" : "0"].concat(args)
    notifier.running = true
  }

  readonly property string announceScript: [
    'state="$1" day="$2" force="$3"; shift 3',
    'if [ "$force" != 1 ] && [ "$(cat "$state" 2>/dev/null)" = "$day" ]; then exit 0; fi',
    'notify-send "$@" || exit',
    'mkdir -p "${state%/*}" && printf "%s\\n" "$day" > "$state"'
  ].join("\n")

  Process {
    id: notifier
    stdout: SplitParser {
      onRead: data => {
        if (data.trim() === "default") root.showToday()
      }
    }
  }

  // Gives the notification service time to come up at login.
  Timer {
    id: announceSoon
    interval: 5000
    onTriggered: root.announce(false)
  }

  FileView {
    path: root.pluginDir + "/quotes.json"
    watchChanges: true
    onFileChanged: reload()
    onLoaded: root.load(text())
    onLoadFailed: error => console.warn("reva.animequote: can't read quotes.json:", error)
  }

  // Cheap enough to poll, and unlike a timer aimed at midnight it also
  // catches the date changing while the machine was suspended.
  Timer {
    interval: 60000
    running: true
    repeat: true
    onTriggered: root.today = root.dateKey()
  }

  onTodayChanged: {
    rolled = -1
    announceSoon.restart()
  }

  // omarchy-shell reva.animequote <toggle|random|today|notify>
  IpcHandler {
    target: "reva.animequote"

    function toggle(): void {
      root.popupOpen = !root.popupOpen
    }

    function random(): void {
      root.roll()
      root.popupOpen = true
    }

    function today(): void {
      root.showToday()
    }

    function notify(): void {
      root.announce(true)
    }
  }

  // A picture cropped to fill the item, anchored at the top so faces stay in
  // frame, with rounded corners (a circle when radius is half the size).
  component Portrait: Item {
    id: portrait
    property string path: ""
    property real radius: 0
    readonly property bool ready: picture.status === Image.Ready

    Image {
      id: picture
      anchors.fill: parent
      visible: false
      source: portrait.path ? Util.fileUrl(portrait.path) : ""
      fillMode: Image.PreserveAspectCrop
      verticalAlignment: Image.AlignTop
      asynchronous: true
      smooth: true
      sourceSize.width: Math.ceil(portrait.width * 2)
    }

    Item {
      id: mask
      anchors.fill: parent
      visible: false
      layer.enabled: true

      Rectangle {
        anchors.fill: parent
        radius: portrait.radius
        color: "black"
      }
    }

    MultiEffect {
      anchors.fill: parent
      visible: portrait.ready
      source: picture
      maskEnabled: true
      maskSource: mask
      maskThresholdMin: 0.5
      maskSpreadAtMin: 1.0
    }
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.space(6)

    Item {
      id: avatar
      anchors.verticalCenter: parent.verticalCenter
      width: root.avatarSize
      height: root.avatarSize

      Portrait {
        id: barPortrait
        anchors.fill: parent
        anchors.margins: Math.max(1, Style.space(2))
        radius: width / 2
        path: root.imagePath
      }

      Rectangle {
        anchors.fill: parent
        visible: barPortrait.ready
        radius: width / 2
        color: "transparent"
        border.width: Math.max(1, Style.space(1.5))
        border.color: Color.accent
      }

      Text {
        anchors.centerIn: parent
        visible: !barPortrait.ready
        textFormat: Text.PlainText
        text: root.glyph(0xF0757)
        color: root.bar.barForeground
        font.family: root.bar.fontFamily
        font.pixelSize: Style.font.icon
      }
    }

    Text {
      anchors.verticalCenter: parent.verticalCenter
      visible: root.showName && !root.vertical && root.quote !== null
      width: Math.min(root.maxLabelWidth, implicitWidth)
      textFormat: Text.PlainText
      text: root.character.name || ""
      color: root.bar.barForeground
      font.family: root.bar.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
    }
  }

  MouseArea {
    anchors.fill: parent
    hoverEnabled: true
    cursorShape: Qt.PointingHandCursor
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    onClicked: mouse => {
      if (mouse.button === Qt.RightButton) {
        root.roll()
        root.popupOpen = true
      } else {
        root.popupOpen = !root.popupOpen
      }
    }
    onEntered: root.bar.showTooltip(root, root.tooltipText())
    onExited: root.bar.hideTooltip(root)
  }

  PopupCard {
    id: popup
    anchorItem: root
    bar: root.bar
    owner: root
    open: root.popupOpen
    contentWidth: popup.fittedContentWidth(Style.space(460))
    contentHeight: popup.fittedContentHeight(Math.max(frame.height, details.implicitHeight))

    Row {
      anchors.fill: parent
      spacing: Style.space(14)

      Item {
        id: frame
        width: Style.space(124)
        height: Style.space(186)

        Rectangle {
          anchors.fill: parent
          radius: Style.space(8)
          color: Qt.tint(Color.popups.background, Qt.rgba(Color.accent.r, Color.accent.g, Color.accent.b, 0.10))
        }

        Portrait {
          id: popupPortrait
          anchors.fill: parent
          radius: Style.space(8)
          path: root.imagePath
        }

        Text {
          anchors.centerIn: parent
          visible: !popupPortrait.ready
          textFormat: Text.PlainText
          text: root.glyph(0xF0009)
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.space(48)
        }

        Rectangle {
          anchors.fill: parent
          radius: Style.space(8)
          color: "transparent"
          border.width: Math.max(1, Style.space(2))
          border.color: Color.accent
        }
      }

      Column {
        id: details
        width: parent.width - frame.width - parent.spacing
        spacing: Style.space(6)

        Text {
          textFormat: Text.PlainText
          text: root.glyph(0xF0757)
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.space(26)
          height: Style.space(22)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.quote ? root.quote.text : "No quotes loaded. Check quotes.json in the plugin folder."
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: root.quote && root.quote.text.length > 120 ? Style.font.body : Style.font.subtitle
          wrapMode: Text.WordWrap
          lineHeight: 1.2
        }

        Item {
          width: 1
          height: Style.space(2)
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: "— " + (root.character.name || "")
          color: Color.accent
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.title
          font.bold: true
          wrapMode: Text.WordWrap
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.character.anime || ""
          color: Qt.darker(root.bar.foreground, 1.4)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
          font.italic: true
          wrapMode: Text.WordWrap
        }

        Item {
          width: 1
          height: Style.space(4)
        }

        Row {
          spacing: Style.space(6)

          Button {
            iconText: root.glyph(0xF076E)
            text: "Another"
            tooltipText: "A random quote"
            foreground: root.bar.foreground
            enabled: root.quotes.length > 1
            onClicked: root.roll()
          }

          Button {
            visible: root.rolled >= 0
            iconText: root.glyph(0xF00F6)
            text: "Today's"
            tooltipText: "Back to today's quote"
            foreground: root.bar.foreground
            onClicked: root.rolled = -1
          }
        }

        Text {
          width: parent.width
          textFormat: Text.PlainText
          text: root.rolled >= 0
            ? "Random pick · " + (root.index + 1) + " of " + root.quotes.length
            : Qt.formatDate(new Date(root.today + "T12:00:00"), "dddd d MMMM") + " · a new quote at midnight"
          color: Qt.darker(root.bar.foreground, 1.6)
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.caption
          wrapMode: Text.WordWrap
        }
      }
    }
  }
}
