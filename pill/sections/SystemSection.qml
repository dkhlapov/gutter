import QtQuick
import QtQuick.Layouts
import qs.components
import qs.services
import qs.theme
import "system"
import "../../lib/usage.js" as UsageLib

// Reads the stat services (Cpu, Gpu, Memory, NetworkUsage, Storage) directly; the refs keep them sampling only
// while this section exists.
ColumnLayout {
    id: root

    spacing: Theme.pad

    ServiceRef {
        service: Cpu
    }
    ServiceRef {
        service: Gpu
    }
    ServiceRef {
        service: Memory
    }
    ServiceRef {
        service: NetworkUsage
    }
    ServiceRef {
        service: Storage
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 1
        spacing: Theme.pad

        HardwareCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            title: "CPU"
            model: UsageLib.cpuModel(Cpu.name)
            icon: ""
            accent: "teal"
            usage: Cpu.percentage
            temperature: Cpu.temperature
        }

        HardwareCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            title: "GPU"
            model: Gpu.name
            icon: ""
            accent: "magenta"
            usage: Gpu.percentage
            temperature: Gpu.temperature
            status: Gpu.detecting ? "busy" : !Gpu.available ? "missing" : ""
            missingText: "No GPU"
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredHeight: 1
        spacing: Theme.pad

        MemoryCard {
            Layout.preferredWidth: 190
            Layout.fillHeight: true
        }

        NetworkCard {
            Layout.fillWidth: true
            Layout.fillHeight: true
        }

        DisksCard {
            Layout.preferredWidth: 320
            Layout.fillHeight: true
        }
    }
}
