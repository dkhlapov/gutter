import QtQuick
import QtTest
import "../lib/format.js" as F

TestCase {
    name: "Format"

    function test_bytes() {
        compare(F.bytes(0), "0 B");
        compare(F.bytes(1536), "1.5 KiB");
        compare(F.bytes(5 * 1024 * 1024 * 1024), "5.0 GiB");
        compare(F.bytes(-5), "0 B");
    }

    function test_kib() {
        compare(F.kib(8 * 1024 * 1024), "8.0 GiB");
    }

    function test_duration() {
        compare(F.duration(65), "1:05");
        compare(F.duration(3725), "1:02:05");
        compare(F.duration(-3), "0:00");
        compare(F.duration(NaN), "0:00");
    }
}
