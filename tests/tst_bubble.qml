import QtQuick
import QtTest
import "../lib/bubble.js" as B

TestCase {
    name: "Bubble"

    // A 200 x 100 balloon with an 18 px tail of half-base 9, the tip at x = 40.
    function inside(x, y) {
        return B.contains(x, y, 200, 100, 18, 40, 9);
    }

    function test_tailCentreFollowsTailX() {
        compare(B.tailCentre(200, 0.5, 9, 3, 8), 100);
    }

    function test_tailCentreStaysClearOfTheCorners() {
        compare(B.tailCentre(200, 0, 9, 3, 8), 18.5);
        compare(B.tailCentre(200, 1, 9, 3, 8), 181.5);
    }

    function test_bodyIsInside() {
        verify(inside(0, 18));
        verify(inside(100, 60));
        verify(inside(200, 100));
    }

    function test_outsideTheBox() {
        verify(!inside(-1, 50));
        verify(!inside(201, 50));
        verify(!inside(100, 101));
        verify(!inside(40, -1));
    }

    function test_tailTriangleIsInside() {
        verify(inside(40, 1));
        verify(inside(40, 17));
        verify(inside(49, 18));
        verify(inside(31, 18));
        verify(inside(44, 9));
    }

    function test_cornersBesideTheTailAreNot() {
        verify(!inside(10, 5));
        verify(!inside(100, 5));
        verify(!inside(52, 17));
        verify(!inside(49, 9));
        verify(!inside(200, 0));
    }
}
