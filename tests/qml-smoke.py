"""Headless Qt smoke tests of the production QML and JS.

Requires PySide6-Essentials. Quickshell/Omarchy host types are stubbed; this
checks QML loading, IPC/event wiring, timers, settings, and panel geometry,
not the native Wayland layer surface or the compositor's input delivery.
"""
import json
import os
from pathlib import Path
import re
import tempfile

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")
from PySide6.QtCore import QUrl, QMetaObject, Q_ARG, Q_RETURN_ARG
from PySide6.QtGui import QGuiApplication
from PySide6.QtQml import QQmlComponent, QQmlEngine
from PySide6.QtQuick import QQuickItem
from PySide6.QtTest import QTest

ROOT = Path(__file__).resolve().parents[1]
app = QGuiApplication([])
engine = QQmlEngine()
warnings = []
engine.warnings.connect(lambda errors: warnings.extend(error.toString() for error in errors))


def invoke(obj, method, *args):
    return QMetaObject.invokeMethod(obj, method, Q_RETURN_ARG(str), *(Q_ARG(str, arg) for arg in args))


with tempfile.TemporaryDirectory(prefix="keycaps-qml-") as directory:
    temp = Path(directory)

    def module(name, files, singletons=()):
        target = temp / name.replace(".", "/")
        target.mkdir(parents=True, exist_ok=True)
        lines = [f"module {name}"]
        for key, text in files.items():
            (target / f"{key}.qml").write_text(text, encoding="utf-8")
            lines.append(f"{'singleton ' if key in singletons else ''}{key} 1.0 {key}.qml")
        (target / "qmldir").write_text("\n".join(lines), encoding="utf-8")

    module("Quickshell", {
        "Quickshell": 'pragma Singleton\nimport QtQuick\nQtObject { property var screens: [{name:"test"}]; function env(key) { return "/fixture" } }',
        "PanelWindow": 'import QtQuick\nItem { property var screen; property color color; property int exclusionMode; property var mask }',
        "Region": 'import QtQuick\nQtObject {}',
        "ExclusionMode": 'pragma Singleton\nimport QtQuick\nQtObject { enum Mode { Ignore } }',
    }, ("Quickshell", "ExclusionMode"))
    module("Quickshell.Hyprland", {
        "Hyprland": 'pragma Singleton\nimport QtQuick\nQtObject { property var focusedMonitor: ({name:"test"}); signal rawEvent(var event) }',
    }, ("Hyprland",))
    module("Quickshell.Io", {
        "IpcHandler": 'import QtQuick\nQtObject { objectName: "ipc"; property string target }',
        "FileView": '''import QtQuick
QtObject {
  objectName: "config"
  property string path
  property bool watchChanges
  property bool printErrors
  property bool loaded: true
  property string contents: "{}"
  signal loaded()
  signal fileChanged()
  function text() { return contents }
  function reload() {}
}''',
    })
    module("qs.Commons", {
        "Style": 'pragma Singleton\nimport QtQuick\nQtObject { property int cornerRadius: 6; property var font: ({family:"sans-serif", body:14}); function space(n) { return n } }',
        "Color": 'pragma Singleton\nimport QtQuick\nQtObject { property var popups: ({background:"#202020", border:"#444444", text:"#ffffff"}); property color accent: "#63b1ba"; property color foreground: "#ffffff" }',
        "Util": 'pragma Singleton\nimport QtQuick\nQtObject { function alpha(color, opacity) { return Qt.rgba(0.3, 0.3, 0.3, opacity) } }',
    }, ("Style", "Color", "Util"))
    module("qs.Ui", {})

    for name in ("Service.qml", "KeyModel.js", "ShortcutState.js", "Settings.js"):
        (temp / name).write_text((ROOT / name).read_text(encoding="utf-8"), encoding="utf-8")
    # The platform-specific attached properties cannot load without Quickshell.
    # Leave the production layout, delegates, bindings, and animations intact.
    panel = (ROOT / "Panel.qml").read_text(encoding="utf-8")
    panel = re.sub(r"^import Quickshell.Wayland\n|^\s*WlrLayershell\..*\n", "", panel, flags=re.M)
    panel = panel.replace("anchors { top: true; bottom: true; left: true; right: true }", "anchors.fill: parent")
    (temp / "Panel.qml").write_text(panel, encoding="utf-8")
    (temp / "Harness.qml").write_text('''import QtQuick
import Quickshell.Hyprland
Item {
  width: 1280; height: 720
  QtObject {
    id: host
    function summon(id, payload) { panel.open(payload) }
    function hide(id) { panel.close() }
  }
  Service { id: service; objectName: "service"; shell: host }
  Panel { id: panel; objectName: "panel"; anchors.fill: parent; service: service }
  function send(payload: string): string {
    Hyprland.rawEvent({ name: "custom", data: "omarchy-keycaps," + payload })
    return "ok"
  }
}''', encoding="utf-8")
    engine.addImportPath(str(temp))
    component = QQmlComponent(engine, QUrl.fromLocalFile(str(temp / "Harness.qml")))
    root = component.create()
    assert root is not None, "\n".join(error.toString() for error in component.errors())
    service = root.findChild(QQuickItem, "service")
    panel = root.findChild(QQuickItem, "panel")
    from PySide6.QtCore import QObject
    ipc = service.findChild(QObject, "ipc")
    config = service.findChild(QObject, "config")

    def model():
        return service.property("heldModel").toVariant()

    def send(sequence, keys, **extra):
        return invoke(root, "send", json.dumps(dict(version=1, session="test", sequence=sequence, keys=keys, **extra)))

    config.setProperty("contents", json.dumps({"version": 1, "plugins": [
        {"id": "omarchy-keycaps", "hideAfter": 80, "keycapScale": 1.5, "bottomOffset": 20}]}))
    QMetaObject.invokeMethod(service, "loadSettings")
    assert json.loads(invoke(ipc, "getSettings")) == dict(hideAfter=80, keycapScale=1.5, bottomOffset=20)
    assert panel.property("capHeight") == 63 and panel.property("bottomOffset") == 20
    assert invoke(ipc, "keyEvent", "SHIFT", "1") == "ok"
    assert not panel.property("opened")
    assert invoke(ipc, "keyEvent", "SUPER", "1") == "ok"
    assert [key["label"] for key in model()] == ["SUPER", "SHIFT"]
    assert panel.property("opened")
    assert invoke(ipc, "clear") == "ok"

    send(1, ["CTRL", "SHIFT", 9])
    assert panel.property("active")
    send(2, [])
    assert all(not key["held"] for key in model())
    QTest.qWait(40)
    send(3, [])  # An idle heartbeat must not restart the 80 ms dismissal timer.
    QTest.qWait(60)
    assert not panel.property("opened")
    assert len(model()) == 3, "delegates must survive the exit animation"
    send(4, ["SUPER", 65])  # A shortcut during exit cancels delayed cleanup.
    QTest.qWait(270)
    assert panel.property("active") and len(model()) == 2
    send(3, [])  # Stale packets cannot hide the new combo.
    assert panel.property("active")
    send(5, [])
    QTest.qWait(370)
    assert not panel.property("opened") and model() == []
    send(6, ["CTRL"])
    send(7, [], reset=True)
    assert not panel.property("opened") and model() == []
    assert invoke(ipc, "snapshot", '{"keys":[]}') == "invalid"
    assert invoke(ipc, "keyEvent", "CTRL", "maybe") == "invalid"
    config.setProperty("contents", json.dumps({"version": 1, "plugins": [
        {"id": "omarchy-keycaps", "hideAfter": 0, "keycapScale": 0.5, "bottomOffset": 0}]}))
    QMetaObject.invokeMethod(service, "loadSettings")
    assert panel.property("capHeight") == 21 and panel.property("bottomOffset") == 0
    send(8, ["SUPER"])
    send(9, [])
    QTest.qWait(30)
    assert not panel.property("opened"), "zero delay must dismiss without waiting for another event"
    assert not warnings, "\n".join(warnings)
    root.deleteLater()
    QTest.qWait(1)

print("PASS: QML loads; IPC and socket events drive the panel; settings, release animation lifetime, timers, stale packets, and reload behave correctly")
