import QtQuick
import QtTest
import "../lib/usage.js" as U

TestCase {
    name: "Usage"

    // Thresholds: cookie < 40 % ≤ sunny < 80 % ≤ burst.
    function test_shapeFor() {
        compare(U.shapeFor(0), "cookie");
        compare(U.shapeFor(0.39), "cookie");
        compare(U.shapeFor(0.4), "sunny");
        compare(U.shapeFor(0.79), "sunny");
        compare(U.shapeFor(0.8), "burst");
        compare(U.shapeFor(1), "burst");
    }

    function test_shapeForBadInput() {
        compare(U.shapeFor(NaN), "cookie");
        compare(U.shapeFor(undefined), "cookie");
    }

    // /proc/cpuinfo names end in " 8-Core Processor"; a name cut short leaves "8-" dangling.
    function test_cpuModel() {
        compare(U.cpuModel("AMD Ryzen 7 9800X3D 8-Core Processor"), "AMD Ryzen 7 9800X3D");
        compare(U.cpuModel("AMD Ryzen 9 7950X 16-Core Processor"), "AMD Ryzen 9 7950X");
        compare(U.cpuModel("AMD Ryzen 7 9800X3D 8-"), "AMD Ryzen 7 9800X3D");
        compare(U.cpuModel("Intel(R) Core(TM) i7-12700K"), "Intel(R) Core(TM) i7-12700K");
        compare(U.cpuModel(""), "");
        compare(U.cpuModel(undefined), "");
    }

    function test_shapeOutline() {
        compare(U.shapeOutline("cookie", 0, 0, 10).length, 8);
        compare(U.shapeOutline("sunny", 0, 0, 10).length, 16);
        compare(U.shapeOutline("burst", 0, 0, 10).length, 24);
        // Tips on the outer radius, notches inside it, all around the centre.
        const pts = U.shapeOutline("burst", 50, 40, 20);
        for (let i = 0; i < pts.length; i++) {
            const d = Math.hypot(pts[i].x - 50, pts[i].y - 40);
            fuzzyCompare(d, i % 2 === 0 ? 20 : 20 * 0.58, 1e-9);
        }
        // A burst starts at 12 o'clock.
        fuzzyCompare(pts[0].x, 50, 1e-9);
        fuzzyCompare(pts[0].y, 20, 1e-9);
    }

    function test_shapeOutlineUnknownKindIsCookie() {
        compare(U.shapeOutline("nope", 0, 0, 10).length, 8);
    }
}
