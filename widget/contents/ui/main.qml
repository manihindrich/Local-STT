import QtQuick
import QtQuick.Layouts
import org.kde.plasma.plasmoid
import org.kde.plasma.core as PlasmaCore
import org.kde.plasma.components as PlasmaComponents3
import org.kde.plasma.extras as PlasmaExtras
import org.kde.plasma.plasma5support as P5Support
import org.kde.kirigami as Kirigami

// Tray icon for Local STT: visible only while a file is being transcribed.
// @TARGET@ is replaced with the install directory by `make install-widget`.
PlasmoidItem {
    id: root

    readonly property string target: "@TARGET@"
    property var st: ({ state: "idle" })

    Plasmoid.status: st.state === "idle" ? PlasmaCore.Types.HiddenStatus : PlasmaCore.Types.ActiveStatus
    Plasmoid.icon: st.state === "error" ? "dialog-error" : "audio-input-microphone"

    toolTipMainText: st.state === "error" ? "Local STT · watcher stopped"
                   : st.state === "busy" ? "Local STT · transcribing" : "Local STT · idle"
    toolTipSubText: summary(st)
    toolTipTextFormat: Text.RichText

    function hsize(b) {
        const u = ["B", "kB", "MB", "GB", "TB"];
        let i = 0;
        while (b >= 1024 && i < u.length - 1) { b /= 1024; i++; }
        return i ? b.toFixed(1) + " " + u[i] : b + " B";
    }

    function htime(s) {
        s = Math.max(0, Math.round(s));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), x = s % 60;
        const pad = n => String(n).padStart(2, "0");
        return h ? `${h}h ${pad(m)}m` : m ? `${m}m ${pad(x)}s` : `${x}s`;
    }

    function esc(t) {
        return String(t).replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;");
    }

    function summary(s) {
        if (s.state === "idle")
            return "Nothing to transcribe";
        const lines = [`<b>${esc(s.file)}</b>`];
        let timing = `${hsize(s.size)} · running ${htime(s.elapsed)}`;
        if (s.eta > 0) timing += ` · ~${htime(s.eta)} left`;
        else if (s.eta === 0) timing += " · finishing";
        lines.push(timing);
        if (s.queued > 0) lines.push(`${s.queued} queued`);
        if (s.cpu) lines.push(`CPU ${s.cpu} of ${s.cores * 100}% · RAM ${esc(s.mem)}`);
        if (s.last) lines.push(`<i>Last: ${esc(s.last)} in ${htime(s.last_secs)}</i>`);
        if (s.errors > 0) lines.push(`<i>${s.errors} failed, left in input/</i>`);
        return lines.join("<br>");
    }

    P5Support.DataSource {
        id: exec
        engine: "executable"
        connectedSources: []
        onNewData: (source, data) => {
            disconnectSource(source);
            try {
                root.st = JSON.parse(data["stdout"]);
            } catch (e) {
                console.warn("Local STT: cannot parse status:", data["stderr"]);
            }
        }
    }

    Timer {
        interval: 5000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: exec.connectSource(root.target + "/status.sh")
    }

    fullRepresentation: Item {
        Layout.preferredWidth: Kirigami.Units.gridUnit * 22
        Layout.preferredHeight: Kirigami.Units.gridUnit * 11

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: Kirigami.Units.smallSpacing

            PlasmaExtras.Heading {
                level: 3
                text: root.toolTipMainText
            }
            PlasmaComponents3.Label {
                Layout.fillWidth: true
                textFormat: Text.RichText
                wrapMode: Text.Wrap
                text: root.summary(root.st)
            }
            Item { Layout.fillHeight: true }
            PlasmaComponents3.Button {
                text: "Open output folder"
                icon.name: "folder-open"
                onClicked: Qt.openUrlExternally("file://" + root.target + "/output")
            }
        }
    }
}
