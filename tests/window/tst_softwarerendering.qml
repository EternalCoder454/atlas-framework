import QtQuick
import QtTest
import Atlas.Ui

// AtlasStyle.softwareRendering: this test runs on the Qt Quick software
// backend (tests/visual/run-variant.sh sets QT_QUICK_BACKEND=software), so the
// flag must turn true once the window's scene graph is up, and AtlasEdgeGlow
// must then be static: no running animation, no ShaderEffect.
TestCase {
    id: test
    name: "SoftwareRendering"
    width: 300
    height: 200
    visible: true
    when: windowShown

    Component {
        id: glowComp
        AtlasEdgeGlow {
            anchors.fill: parent
            active: true
        }
    }

    function walk(item, found) {
        for (let i = 0; i < item.data.length; ++i) {
            const o = item.data[i];
            found.push(o);
            if (o.data !== undefined) {
                walk(o, found);
            }
        }
        return found;
    }

    function test_flagTurnsTrueOnTheSoftwareBackend() {
        tryCompare(AtlasStyle, "softwareRendering", true);
    }

    function test_edgeGlowIsStaticUnderTheFlag() {
        tryCompare(AtlasStyle, "softwareRendering", true);
        const glow = createTemporaryObject(glowComp, test);
        verify(glow !== null);
        // Fully shown at once: no fade.
        compare(glow.opacity, 1);
        compare(glow._breathing, false);
        const all = walk(glow, []);
        verify(all.length > 0);
        for (const o of all) {
            verify(String(o).indexOf("ShaderEffect") < 0, "no ShaderEffect: " + o);
            verify(!o.running, "no running animation: " + o);
        }
        // The breathing value never leaves 1 and the opacity holds.
        wait(600);
        compare(glow._breath, 1);
        compare(glow.opacity, 1);
    }
}
