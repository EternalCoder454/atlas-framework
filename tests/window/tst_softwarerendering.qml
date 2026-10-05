import QtQuick
import QtTest
import Atlas.Ui

// AtlasStyle.softwareRendering: this test runs on the Qt Quick software
// backend with detection on (the window test sets ATLAS_SOFTWARE_RENDERING to
// empty, see tests/CMakeLists.txt), so the flag must turn true after the first
// frames. Then the controls that animated must stand still, or step slowly
// from a Timer: no running Animation.Infinite, no ShaderEffect.
TestCase {
    id: test
    name: "SoftwareRendering"
    width: 400
    height: 300
    visible: true
    when: windowShown

    Component {
        id: glowComp
        AtlasEdgeGlow {
            anchors.fill: parent
            active: true
        }
    }
    Component {
        id: spinnerComp
        AtlasSpinner {
            running: true
        }
    }
    Component {
        id: barComp
        AtlasProgressBar {
            width: 200
            indeterminate: true
        }
    }
    Component {
        id: workingBarComp
        AtlasProgressBar {
            width: 200
            value: 0.4
        }
    }
    Component {
        id: installComp
        AtlasInstallButton {
            installState: "installing"
            progress: -1
        }
    }
    Component {
        id: heroComp
        StatusHero {
            width: 300
            headline: "Working"
            busy: true
            showBar: true
        }
    }
    Component {
        id: placeholderComp
        AtlasPlaceholder {
            width: 200
            lines: 3
        }
    }

    // Every object below `item`: data, children (delegates) and contentItem.
    function walk(item, found, seen) {
        for (const list of [item.data, item.children]) {
            if (list === undefined) {
                continue;
            }
            for (let i = 0; i < list.length; ++i) {
                const o = list[i];
                if (!seen.has(o)) {
                    seen.add(o);
                    found.push(o);
                    walk(o, found, seen);
                }
            }
        }
        if (item.contentItem && !seen.has(item.contentItem)) {
            seen.add(item.contentItem);
            found.push(item.contentItem);
            walk(item.contentItem, found, seen);
        }
        return found;
    }

    function all(item) {
        return walk(item, [item], new Set([item]));
    }

    function isTimer(o) {
        return o.interval !== undefined && o.repeat !== undefined;
    }

    function runningTimers(item) {
        return all(item).filter(o => isTimer(o) && o.running);
    }

    // No endless animation and no shader effect anywhere in the control. A
    // layer (a ShaderEffectSource, no shader of its own) is allowed: the
    // spinner turns a cached texture rather than redraw its arc each step.
    function verifyNoEndlessMotion(item) {
        for (const o of all(item)) {
            verify(o.fragmentShader === undefined, "no ShaderEffect: " + o);
            verify(!(o.loops === Animation.Infinite && o.running), "no endless animation: " + o);
        }
    }

    // Timers that move something step at most 30 times a second.
    function verifyTimersAreSlow(item) {
        for (const t of runningTimers(item)) {
            verify(t.interval >= 33, "interval " + t.interval + " ms is faster than 30 fps");
        }
    }

    function initTestCase() {
        tryCompare(AtlasStyle, "softwareRendering", true);
    }

    function test_flagTurnsTrueOnTheSoftwareBackend() {
        compare(AtlasStyle.softwareRendering, true);
    }

    function test_edgeGlowIsStaticUnderTheFlag() {
        const glow = createTemporaryObject(glowComp, test);
        verify(glow !== null);
        // Fully shown at once: no fade.
        tryCompare(glow, "opacity", 1);
        compare(glow._breathing, false);
        compare(glow._breath, 1);
        verify(all(glow).length > 1);
        verifyNoEndlessMotion(glow);
        compare(runningTimers(glow).length, 0);
    }

    function test_spinnerStepsFromATimer() {
        const s = createTemporaryObject(spinnerComp, test);
        verify(s !== null);
        tryVerify(() => runningTimers(s).length === 1);
        verifyNoEndlessMotion(s);
        verifyTimersAreSlow(s);
    }

    function test_indeterminateBarSlidesFromATimerAndHasNoShimmer() {
        const b = createTemporaryObject(barComp, test);
        verify(b !== null);
        tryVerify(() => runningTimers(b).length === 1);
        verifyNoEndlessMotion(b);
        verifyTimersAreSlow(b);
        const bands = all(b).filter(o => o.phase !== undefined && o.gradient !== undefined);
        verify(bands.length > 0);
        for (const band of bands) {
            compare(band.visible, false);
        }
    }

    function test_workingBarShimmerIsHidden() {
        const b = createTemporaryObject(workingBarComp, test);
        verify(b !== null);
        verifyNoEndlessMotion(b);
        compare(runningTimers(b).length, 0);
        const bands = all(b).filter(o => o.phase !== undefined && o.gradient !== undefined);
        verify(bands.length > 0);
        for (const band of bands) {
            compare(band.visible, false);
        }
    }

    function test_installButtonSlidesFromATimer() {
        const b = createTemporaryObject(installComp, test);
        verify(b !== null);
        tryVerify(() => runningTimers(b).length === 1);
        verifyNoEndlessMotion(b);
        verifyTimersAreSlow(b);
        for (const band of all(b).filter(o => o.phase !== undefined && o.gradient !== undefined)) {
            compare(band.visible, false);
        }
    }

    function test_statusHeroTurnsFromTimers() {
        const h = createTemporaryObject(heroComp, test);
        verify(h !== null);
        // The ring and the indeterminate bar: two timers.
        tryVerify(() => runningTimers(h).length === 2);
        verifyNoEndlessMotion(h);
        verifyTimersAreSlow(h);
    }

    function test_placeholderSweepIsStatic() {
        const p = createTemporaryObject(placeholderComp, test);
        verify(p !== null);
        verify(all(p).length > 1);
        verifyNoEndlessMotion(p);
        compare(runningTimers(p).length, 0);
    }
}
