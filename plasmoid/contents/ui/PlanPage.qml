import QtQuick
import QtQuick.Layouts
import "Theme.js" as T

// Plan tab: both limits with pace markers and forecasts, the current window's chart and verdict.
ColumnLayout {
    id: page
    property var usage: null        // fetch.py output
    property string err: ""
    property string nextCheck: ""   // "next check in 3m 12s"
    property var today: null        // stats.today, for the footer
    property string chartWin: "5h"
    readonly property bool hasData: usage !== null
    spacing: 12
    Colours { id: pal }

    RowLayout {
        Layout.fillWidth: true
        Layout.topMargin: 2
        Txt { text: "Your plan"; font.bold: true; size: 14; Layout.fillWidth: true }
        Txt {
            visible: page.hasData
            text: "updated " + (page.hasData ? page.usage.updated : "") + (page.nextCheck ? " · " + page.nextCheck : "")
            muted: true; mono: true; size: 11
        }
    }

    Card {   // nothing to show yet: say why
        visible: !page.hasData
        Txt { text: page.err || "Loading…"; color: page.err ? pal.level("bad").text : T.muted; wrapMode: Text.WordWrap; Layout.fillWidth: true }
    }

    Card {   // serving a cached reading: say why
        visible: page.hasData && page.usage.stale
        color: Qt.rgba(0.94, 0.71, 0.35, 0.10)
        Txt {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            color: T.amberText; size: 12
            text: page.hasData && page.usage.stale ? "Showing the reading from " + page.usage.updated + ". " + page.usage.why : ""
        }
    }

    Card {
        visible: page.hasData
        spacing: 6
        Repeater {
            model: page.hasData ? [["5-hour limit", page.usage["5h"]], ["Weekly limit", page.usage.weekly]] : []
            ColumnLayout {
                readonly property var w: modelData[1]
                readonly property var lv: pal.level(w.level)
                Layout.fillWidth: true
                spacing: 6
                Divider { visible: index > 0; Layout.topMargin: 6; Layout.bottomMargin: 4 }
                RowLayout {
                    Layout.fillWidth: true
                    Txt { text: modelData[0]; font.bold: true; size: 14; Layout.fillWidth: true }
                    Txt { text: w.pct + "%"; font.bold: true; mono: true; size: 14 }
                }
                Bar {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    Layout.bottomMargin: 4
                    value: w.pct
                    forecast: w.forecast
                    marker: w.pace
                    fill: lv.fill
                    ghost: lv.ghost
                }
                Txt {
                    text: w.reset ? w.reset.charAt(0).toUpperCase() + w.reset.slice(1) + " · " + w.reset_at : ""
                    muted: true; size: 12
                }
                Txt { visible: w.hint !== ""; text: w.hint; size: 12; font.bold: true; color: lv.text }
            }
        }
    }

    RowLayout {
        visible: page.hasData
        Layout.fillWidth: true
        Layout.topMargin: 4
        Txt { text: "This window"; font.bold: true; size: 14; Layout.fillWidth: true }
        Segmented {
            model: ["5-hour", "Week"]
            currentIndex: page.chartWin === "5h" ? 0 : 1
            onActivated: i => page.chartWin = i === 0 ? "5h" : "weekly"
        }
    }

    Card {
        id: chartCard
        visible: page.hasData
        spacing: 8
        readonly property var w: page.hasData ? page.usage[page.chartWin] : null

        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            radius: 8
            color: T.inset
            Canvas {
                id: chart
                anchors.fill: parent
                anchors.margins: 10
                readonly property var w: chartCard.w
                readonly property var levels: pal.levels
                onLevelsChanged: requestPaint()
                onWChanged: requestPaint()
                onWidthChanged: requestPaint()
                onHeightChanged: requestPaint()
                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()
                    if (!w) return
                    var W = width, H = height
                    // y scale: 100% near the top unless the forecast runs past it
                    var top = Math.min(Math.max(100, w.forecast || 0, w.pct), 200) * 1.08
                    function y(p) { return H - p / top * H }
                    ctx.lineWidth = 1
                    ctx.strokeStyle = T.line
                    ctx.beginPath(); ctx.moveTo(0, Math.round(y(100)) + 0.5); ctx.lineTo(W, Math.round(y(100)) + 0.5); ctx.stroke()
                    ctx.fillStyle = T.muted
                    ctx.font = "10px monospace"
                    ctx.fillText("100%", 2, y(100) + 13)
                    ctx.setLineDash([4, 4]); ctx.strokeStyle = T.faint   // even pace
                    ctx.beginPath(); ctx.moveTo(0, y(0)); ctx.lineTo(W, y(100)); ctx.stroke()

                    var col = pal.level(w.level).fill
                    var pts = w.hist.slice()
                    if (w.now !== null) pts.push([w.now, w.pct])   // now
                    if (!pts.length) return
                    ctx.lineWidth = 2
                    ctx.lineCap = "round"
                    ctx.strokeStyle = col
                    ctx.setLineDash([2, 4])   // before the first reading: estimated from 0
                    ctx.beginPath(); ctx.moveTo(0, y(0)); ctx.lineTo(pts[0][0] * W, y(pts[0][1])); ctx.stroke()
                    ctx.setLineDash([])
                    ctx.beginPath(); ctx.moveTo(pts[0][0] * W, y(pts[0][1]))
                    pts.forEach(function(p) { ctx.lineTo(p[0] * W, y(p[1])) })
                    ctx.stroke()
                    var last = pts[pts.length - 1]
                    if (w.forecast !== null) {   // straight-line forecast to the reset
                        ctx.setLineDash([2, 4])
                        ctx.beginPath(); ctx.moveTo(last[0] * W, y(last[1])); ctx.lineTo(W, y(w.forecast)); ctx.stroke()
                        ctx.setLineDash([])
                    }
                    ctx.fillStyle = col
                    ctx.beginPath(); ctx.arc(last[0] * W, y(last[1]), 4, 0, 2 * Math.PI); ctx.fill()
                }
            }
        }
        RowLayout {
            Layout.fillWidth: true
            Txt { text: chartCard.w ? chartCard.w.start_at : ""; muted: true; mono: true; size: 10 }
            Txt { text: "dotted = estimate"; muted: true; mono: true; size: 10; Layout.fillWidth: true; horizontalAlignment: Text.AlignHCenter }
            Txt { text: chartCard.w ? "resets " + chartCard.w.reset_at : ""; muted: true; mono: true; size: 10 }
        }
        Txt {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.bold: true
            text: chartCard.w ? chartCard.w.verdict : ""
            color: chartCard.w ? pal.level(chartCard.w.level).text : T.muted
        }
    }

    Item { Layout.fillHeight: true }

    Txt {
        visible: page.today !== null
        Layout.fillWidth: true
        text: page.today ? "Claude Code today: " + page.today.tok + " tokens · " + page.today.msgs + " messages" : ""
        muted: true; size: 12
    }
}
