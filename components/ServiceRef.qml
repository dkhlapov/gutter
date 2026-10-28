import QtQuick

// Keeps a service sampling while this object exists: counts itself in the service's `refs` from completion
// to destruction. Services (Cpu, Gpu, Memory, Storage, NetworkUsage) poll only while `refs > 0`.
QtObject {
    id: root

    property var service
    // The service this ref was counted in; the release goes there even if `service` was reassigned meanwhile.
    property var held: null

    Component.onCompleted: {
        if (!service)
            return;
        held = service;
        held.refs++;
    }

    Component.onDestruction: {
        if (held)
            held.refs--;
    }
}
