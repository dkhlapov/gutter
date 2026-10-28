import QtQuick
import QtTest
import "../lib/tiles.js" as T

TestCase {
    name: "Tiles"

    function test_fullRows() {
        verify(T.fullRows(4, 4));
        verify(T.fullRows(6, 3));
        verify(T.fullRows(8, 4));
        verify(!T.fullRows(5, 4));
        verify(!T.fullRows(7, 3));
        verify(!T.fullRows(0, 4));
        verify(!T.fullRows(3, 0));
    }
}
