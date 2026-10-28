import QtQuick
import QtTest
import "../lib/stats.js" as S

TestCase {
    name: "Stats"

    // Real /proc/stat head from this machine: aggregate line first, then one line per core.
    readonly property string procStat: "cpu  12658935 708668 1671418 158465633 230946 245525 112707 0 0 0\n"
        + "cpu0 1095187 55548 171443 9438101 27581 70631 10997 0 0 0\n"
        + "cpu1 1334458 155818 180579 9160380 26374 19105 8698 0 0 0\n"
        + "intr 1 2 3\n"

    function test_parseCpuStat() {
        // total = 12658935 + 708668 + 1671418 + 158465633 + 230946 + 245525 + 112707 + 0 (steal) = 174093832
        // busy = total - idle - iowait = 174093832 - 158465633 - 230946 = 15397253
        compare(S.parseCpuStat(procStat), { busy: 15397253, total: 174093832 });
    }

    function test_parseCpuStatBadInput() {
        compare(S.parseCpuStat(""), { busy: 0, total: 0 });
        compare(S.parseCpuStat(undefined), { busy: 0, total: 0 });
        compare(S.parseCpuStat("cpu0 1 2 3 4 5 6 7 0\n"), { busy: 0, total: 0 });
        // Older kernels give fewer columns.
        compare(S.parseCpuStat("cpu  10 0 5 80 5\n"), { busy: 15, total: 100 });
    }

    function test_cpuFraction() {
        compare(S.cpuFraction({ busy: 10, total: 100 }, { busy: 30, total: 140 }), 0.5);
        compare(S.cpuFraction({ busy: 10, total: 100 }, { busy: 10, total: 200 }), 0);
        compare(S.cpuFraction({ busy: 0, total: 1 }, { busy: 51, total: 52 }), 1);
    }

    function test_cpuFractionFirstSampleAndNoElapsed() {
        compare(S.cpuFraction(null, { busy: 5, total: 10 }), 0);
        compare(S.cpuFraction(undefined, { busy: 5, total: 10 }), 0);
        compare(S.cpuFraction({ busy: 5, total: 10 }, null), 0);
        compare(S.cpuFraction({ busy: 5, total: 10 }, { busy: 5, total: 10 }), 0);
    }

    function test_cpuFractionEmptyBaseline() {
        // An empty /proc/stat read parses to zeros; the next good sample must not become a since-boot average.
        compare(S.cpuFraction(S.parseCpuStat(""), S.parseCpuStat(procStat)), 0);
        compare(S.cpuFraction({ busy: 0, total: 0 }, { busy: 50, total: 50 }), 0);
    }

    function test_cpuFractionCounterReset() {
        // Counters went backwards (reboot, suspend quirk): no negative or >1 fractions.
        compare(S.cpuFraction({ busy: 500, total: 1000 }, { busy: 5, total: 10 }), 0);
        compare(S.cpuFraction({ busy: 10, total: 100 }, { busy: 5, total: 150 }), 0);
        compare(S.cpuFraction({ busy: 10, total: 100 }, { busy: 200, total: 110 }), 1);
    }

    function test_parseCpuModel() {
        const info = "processor\t: 0\nvendor_id\t: AuthenticAMD\ncpu family\t: 26\n"
            + "model\t\t: 68\nmodel name\t: AMD Ryzen 7 9800X3D 8-Core Processor\nstepping\t: 0\n"
            + "processor\t: 1\nmodel name\t: Something Else\n";
        compare(S.parseCpuModel(info), "AMD Ryzen 7 9800X3D 8-Core Processor");
        compare(S.parseCpuModel("model name :   padded name  \n"), "padded name");
        compare(S.parseCpuModel("processor\t: 0\n"), "");
        compare(S.parseCpuModel(""), "");
        compare(S.parseCpuModel(undefined), "");
    }

    readonly property string meminfo: "MemTotal:       31935100 kB\nMemFree:         2217224 kB\n"
        + "MemAvailable:   13097436 kB\nBuffers:              36 kB\nCached:         11597880 kB\n"
        + "SwapCached:        15488 kB\n"

    function test_parseMeminfo() {
        const m = S.parseMeminfo(meminfo);
        compare(m.total, 31935100);
        compare(m.used, 31935100 - 13097436);
        fuzzyCompare(m.percentage, (31935100 - 13097436) / 31935100, 1e-12);
    }

    function test_parseMeminfoBadInput() {
        compare(S.parseMeminfo(""), { total: 0, used: 0, percentage: 0 });
        compare(S.parseMeminfo(undefined), { total: 0, used: 0, percentage: 0 });
        // No MemAvailable (very old kernel): MemFree stands in.
        const m = S.parseMeminfo("MemTotal: 1000 kB\nMemFree: 250 kB\n");
        compare(m.used, 750);
        compare(m.percentage, 0.75);
    }

    readonly property string netDev: "Inter-|   Receive                                                |  Transmit\n"
        + " face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed\n"
        + "    lo: 1256732682 4714738    0    0    0     0          0         0 1256732682 4714738    0    0    0     0       0          0\n"
        + "enp9s0:       0       0    0    0    0     0          0         0        0       0    0    0    0     0       0          0\n"
        + " wlan0: 20492489223 18099272    0 16813    0     0          0         0 3206306382 7448523    0    0    0     0       0          0\n"

    function test_parseNetDev() {
        compare(S.parseNetDev(netDev), { rx: 20492489223, tx: 3206306382 });
    }

    function test_parseNetDevExcludesVirtual() {
        const line = (n, rx, tx) => n + ": " + rx + " 1 0 0 0 0 0 0 " + tx + " 1 0 0 0 0 0 0\n";
        const text = line("lo", 1000, 1000) + line("veth1a2b", 7, 7) + line("docker0", 8, 8)
            + line("br-1234abcd", 9, 9) + line("virbr0", 10, 10)
            + line("eth0", 100, 50) + line("wlan0", 20, 5) + line("bridge0", 3, 4);
        compare(S.parseNetDev(text), { rx: 123, tx: 59 });
    }

    function test_parseNetDevGluedCounter() {
        // A wide byte counter can touch the colon: "eth0:123456789012 ...".
        compare(S.parseNetDev("eth0:123456789012 1 0 0 0 0 0 0 55 1 0 0 0 0 0 0\n"), { rx: 123456789012, tx: 55 });
    }

    function test_parseNetDevBadInput() {
        compare(S.parseNetDev(""), { rx: 0, tx: 0 });
        compare(S.parseNetDev(undefined), { rx: 0, tx: 0 });
        compare(S.parseNetDev("garbage\nno colon here\n"), { rx: 0, tx: 0 });
    }

    function test_netSpeed() {
        compare(S.netSpeed({ rx: 1000, tx: 500 }, { rx: 3000, tx: 1500 }, 2), { down: 1000, up: 500 });
        compare(S.netSpeed({ rx: 100, tx: 50 }, { rx: 40, tx: 60 }, 1), { down: 0, up: 10 });
    }

    function test_netSpeedNoBaseline() {
        compare(S.netSpeed(null, { rx: 100, tx: 50 }, 1), { down: 0, up: 0 });
        compare(S.netSpeed(undefined, { rx: 100, tx: 50 }, 1), { down: 0, up: 0 });
        compare(S.netSpeed({ rx: 1, tx: 1 }, { rx: 100, tx: 50 }, 0), { down: 0, up: 0 });
        compare(S.netSpeed({ rx: 1, tx: 1 }, { rx: 100, tx: 50 }, -1), { down: 0, up: 0 });
    }

    function test_netSpeedEmptyBaseline() {
        // A failed read parses to zeros; the next good sample must not become bytes since boot / interval.
        compare(S.netSpeed(S.parseNetDev(""), S.parseNetDev(netDev), 2), { down: 0, up: 0 });
        compare(S.netSpeed({ rx: 0, tx: 0 }, { rx: 100, tx: 50 }, 1), { down: 0, up: 0 });
    }

    function test_netSpeedCounterWrap() {
        // An interface that vanished or a counter that wrapped reads as no traffic, never negative.
        compare(S.netSpeed({ rx: 100, tx: 100 }, { rx: 10, tx: 10 }, 1), { down: 0, up: 0 });
    }

    function test_pushSample() {
        compare(S.pushSample([1, 2, 3], 4, 3), [2, 3, 4]);
        compare(S.pushSample([1], 2, 3), [1, 2]);
        compare(S.pushSample([], 1, 3), [1]);
        compare(S.pushSample([1, 2, 3, 4, 5], 6, 3), [4, 5, 6]);
        compare(S.pushSample([1, 2], 3, 0), []);
    }

    function test_pushSampleDoesNotMutate() {
        const buf = [1, 2, 3];
        const out = S.pushSample(buf, 4, 3);
        compare(buf, [1, 2, 3]);
        verify(out !== buf);
        compare(S.pushSample(null, 1, 3), [1]);
    }

    readonly property string df: "Filesystem     1024-blocks      Used Available Capacity Mounted on\n"
        + "/dev/nvme0n1p2   972566196 378930116 589360028      40% /\n"
        + "devtmpfs          15872548         0  15872548       0% /dev\n"
        + "tmpfs             15967548   1479864  14487684      10% /dev/shm\n"
        + "efivarfs               128        72        52      58% /sys/firmware/efi/efivars\n"
        + "tmpfs              6387020      2472   6384548       1% /run\n"
        + "none                  1024         0      1024       0% /run/credentials/systemd-journald.service\n"
        + "/dev/nvme0n1p2   972566196 378930116 589360028      40% /var/tmp\n"
        + "/dev/nvme0n1p2   972566196 378930116 589360028      40% /home\n"
        + "/dev/nvme0n1p1     4186104    677804   3508300      17% /boot\n"
        + "tmpfs              3193508   1146820   2046688      36% /run/user/1000\n"

    function test_parseDf() {
        const d = S.parseDf(df);
        compare(d.length, 2);
        compare(d[0].mount, "/");
        compare(d[0].used, 378930116);
        compare(d[0].total, 972566196);
        compare(d[0].free, 589360028);
        fuzzyCompare(d[0].perc, 378930116 / 972566196, 1e-12);
        compare(d[0].hasRoot, true);
        compare(d[1].mount, "/boot");
        compare(d[1].total, 4186104);
        compare(d[1].hasRoot, false);
    }

    function test_parseDfSkipsPseudoFilesystems() {
        const text = "Filesystem 1024-blocks Used Available Capacity Mounted on\n"
            + "squashfs 100 100 0 100% /snap/core\n"
            + "overlay 5000 1000 4000 20% /var/lib/containers\n"
            + "/dev/sdb1 2000 500 1500 25% /mnt/data\n";
        const d = S.parseDf(text);
        compare(d.length, 1);
        compare(d[0].mount, "/mnt/data");
        compare(d[0].hasRoot, false);
    }

    function test_parseDfMountWithSpaces() {
        const d = S.parseDf("Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sdc1 1000 100 900 10% /mnt/my disk\n");
        compare(d.length, 1);
        compare(d[0].mount, "/mnt/my disk");
    }

    function test_parseDfZeroTotal() {
        const d = S.parseDf("Filesystem 1024-blocks Used Available Capacity Mounted on\n/dev/sdd1 0 0 0 0% /mnt/empty\n");
        compare(d.length, 1);
        compare(d[0].perc, 0);
    }

    function test_parseDfBadInput() {
        compare(S.parseDf(""), []);
        compare(S.parseDf(undefined), []);
        compare(S.parseDf("Filesystem 1024-blocks Used Available Capacity Mounted on\n"), []);
    }

    function test_pickGpu() {
        compare(S.pickGpu([{ vram: 1e9, busyOk: true }, { vram: 16e9, busyOk: true }]), 1);
        compare(S.pickGpu([{ vram: 16e9, busyOk: false }]), -1);
        // A bigger card without gpu_busy_percent loses to a smaller one that has it.
        compare(S.pickGpu([{ vram: 16e9, busyOk: false }, { vram: 1e9, busyOk: true }]), 1);
        compare(S.pickGpu([]), -1);
        compare(S.pickGpu(null), -1);
        // Equal VRAM: the first card wins.
        compare(S.pickGpu([{ vram: 4e9, busyOk: true }, { vram: 4e9, busyOk: true }]), 0);
    }

    function test_parseTemp() {
        compare(S.parseTemp("68000\n"), 68);
        compare(S.parseTemp("45500"), 45.5);
        compare(S.parseTemp(" 0\n"), 0);
        compare(S.parseTemp(""), -1);
        compare(S.parseTemp(undefined), -1);
        compare(S.parseTemp("cat: no such file\n"), -1);
    }

    function test_parseLspciName() {
        compare(S.parseLspciName('03:00.0 "VGA compatible controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Navi 48 [Radeon RX 9070/9070 XT/9070 GRE]" -rc0 -p00 "ASUSTeK Computer Inc." "Device 061a"'),
            "Radeon RX 9070/9070 XT/9070 GRE");
        compare(S.parseLspciName('76:00.0 "VGA compatible controller" "Advanced Micro Devices, Inc. [AMD/ATI]" "Granite Ridge [Radeon 610M]" -rcb -p00 "Gigabyte Technology Co., Ltd" "Device d000"'),
            "Radeon 610M");
        // No bracketed marketing name: the plain device name.
        compare(S.parseLspciName('00:02.0 "VGA compatible controller" "Intel Corporation" "HD Graphics 530" -r06 "Dell" "Device 0123"'),
            "HD Graphics 530");
        compare(S.parseLspciName(""), "");
        compare(S.parseLspciName("garbage"), "");
    }
}
