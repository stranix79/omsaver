//
//  OmSaver — a TUI, Omarchy-vibes screensaver for macOS.
//  Part of the Om series (https://omfi.stranix.net) by Stranix. Free & MIT.
//
//  Three tiling-WM style panes, thin blue borders, Hyprland-ish gaps:
//   ┌ clock ─────────────┐ ┌ system ────────┐
//   │  HH:MM:SS  (huge)  │ │ real CPU bars  │
//   │  date · uptime     │ │ RAM · load     │
//   ├ log ───────────────┤ │ sparkline      │
//   │ geek scrolling log │ └────────────────┘
//   └────────────────────┘   om› series footer
//
import ScreenSaver
import AppKit
import Darwin

@objc(OmSaverView)
public final class OmSaverView: ScreenSaverView {

    // palette Omarchy (same as OmFi)
    private let cBG = NSColor(red: 0.04, green: 0.045, blue: 0.07, alpha: 1)
    private let cBorder = NSColor(red: 0.48, green: 0.60, blue: 0.85, alpha: 1)
    private let cText = NSColor(red: 0.80, green: 0.84, blue: 0.92, alpha: 1)
    private let cDim = NSColor(red: 0.40, green: 0.45, blue: 0.56, alpha: 1)
    private let cAccent = NSColor(red: 0.54, green: 0.65, blue: 0.88, alpha: 1)
    private let cGood = NSColor(red: 0.65, green: 0.89, blue: 0.63, alpha: 1)
    private let cGold = NSColor(red: 0.90, green: 0.76, blue: 0.48, alpha: 1)

    private var logLines: [(String, NSColor)] = []
    private var nextLog: TimeInterval = 0
    private var spark: [Double] = []
    private var cpuPrev: [(UInt32, UInt32)] = []   // (busy, total) per core
    private var cpuLoads: [Double] = []
    private var ramUsed: Double = 0

    private let bootMsgs = [
        ("om› saver 1.0 — TUI screensaver, Omarchy vibes", 0),
        ("initializing panes…", 1), ("HERDING PACKETS", 1),
    ]
    private let funnies = [
        "COUNTING COLLISIONS", "HERDING PACKETS", "TUNING ANTENNAS",
        "CHASING BEACONS", "WAVING AT PHOTONS", "SPREADING SPECTRUM",
        "READING RFC 802.11", "ALIGNING PHASES", "POLLING THE AIRWAVES",
        "NEGOTIATING WITH ROUTER", "BUFFERING THE BUFFERS",
        "DODGING MICROWAVES", "DEFRAGMENTING THE AETHER",
        "REBALANCING B-TREES", "WARMING UP CACHES", "GREASING PIPELINES",
        "COMPACTING TIME SERIES", "ROTATING LOG FILES", "FEEDING THE DAEMONS",
        "RECOUNTING SEMAPHORES", "POLISHING FRAMEBUFFERS",
    ]
    // la pub maison — le gadget vend la suite (iBeer inversé)
    private let promos = [
        "om› OmSuite — Omarchy vibes for macOS · om.stranix.net",
        "om› OmFi — the Wi-Fi panel behind this saver · omfi.stranix.net · 2.99",
        "om› ZapZap — WhatsApp one keystroke away · zapzap.stranix.net",
        "om› Sygnet — bookmark sync that includes Safari · sygnet.app",
        "om› more small sharp apps · apps.stranix.net",
    ]
    private var promoIdx = 0
    private let fakeOps = [
        "scan: 12 networks · best -41 dBm ch36",
        "gc: 4096 objects reclaimed in 0.3 ms",
        "tick: all systems nominal",
        "beacon: HANDSHAKE COMPLETE → Hyperion-5G",
        "dns: resolvers rotated (1.1.1.1, 9.9.9.9)",
        "vpn: tunnel utun4 healthy · 0% loss",
        "fs: snapshots pruned · 42 kept",
        "net: rx 2.4 MB/s · tx 318 KB/s",
        "sched: 8 cores idle-balanced",
        "thermal: fans at whisper level",
    ]

    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        animationTimeInterval = 1.0 / 8.0
        for (m, kind) in bootMsgs {
            logLines.append((stamp(m), kind == 0 ? cAccent : cDim))
        }
    }
    required init?(coder: NSCoder) { super.init(coder: coder) }

    private func stamp(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return "[\(f.string(from: Date()))] \(s)"
    }

    // MARK: real system stats

    private func sampleCPU() {
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info = info else { return }
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        var loads: [Double] = []
        var prev: [(UInt32, UInt32)] = []
        for i in 0..<Int(cpuCount) {
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let sys = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            let busy = user &+ sys &+ nice
            let total = busy &+ idle
            if i < cpuPrev.count {
                let db = Double(busy &- cpuPrev[i].0)
                let dt = Double(total &- cpuPrev[i].1)
                loads.append(dt > 0 ? min(1, db / dt) : 0)
            } else {
                loads.append(0)
            }
            prev.append((busy, total))
        }
        cpuPrev = prev
        cpuLoads = loads

        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        ramUsed = total > 0 ? used / total : 0
    }

    // MARK: animation

    public override func animateOneFrame() {
        sampleCPU()
        let avg = cpuLoads.isEmpty ? 0 : cpuLoads.reduce(0, +) / Double(cpuLoads.count)
        spark.append(avg)
        if spark.count > 90 { spark.removeFirst() }
        let now = Date().timeIntervalSince1970
        if now >= nextLog {
            nextLog = now + Double.random(in: 1.2...3.5)
            let roll = Int.random(in: 0..<10)
            if roll == 0 {
                // une ligne de pub de temps en temps, en vert série
                logLines.append((stamp(promos.randomElement()!), cGood))
            } else if roll < 4 {
                logLines.append((stamp(funnies.randomElement()!), cGold))
            } else {
                logLines.append((stamp(fakeOps.randomElement()!), cDim))
            }
            if logLines.count > 40 { logLines.removeFirst() }
        }
        needsDisplay = true
    }

    // MARK: drawing helpers

    private func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    private func text(_ s: String, _ p: NSPoint, _ font: NSFont, _ color: NSColor) {
        (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }
    private func tw(_ s: String, _ font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }
    private func pane(_ r: NSRect, title: String, scale: CGFloat) {
        cBorder.withAlphaComponent(0.75).setStroke()
        let p = NSBezierPath(roundedRect: r, xRadius: 8 * scale, yRadius: 8 * scale)
        p.lineWidth = max(1, 1.5 * scale)
        p.stroke()
        let f = mono(11 * scale, .semibold)
        let t = " \(title) "
        // title embedded in the top border, TUI style
        let x = r.minX + 18 * scale
        cBG.setFill()
        NSRect(x: x - 4, y: r.maxY - 8 * scale, width: tw(t, f) + 8, height: 16 * scale).fill()
        text(t, NSPoint(x: x, y: r.maxY - 8 * scale), f, cDim)
    }

    public override func draw(_ rect: NSRect) {
        cBG.setFill()
        bounds.fill()
        let W = bounds.width, H = bounds.height
        let scale = max(0.5, min(W / 1440, H / 900))
        let gap = 24 * scale
        let leftW = W * 0.58

        // ── pane horloge
        let clockR = NSRect(x: gap, y: H * 0.52, width: leftW - 1.5 * gap, height: H * 0.48 - 1.5 * gap)
        pane(clockR, title: "om› clock", scale: scale)
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        let timeStr = f.string(from: Date())
        let bigF = mono(min(clockR.width / 5.2, clockR.height * 0.42), .bold)
        let ts = tw(timeStr, bigF)
        text(timeStr, NSPoint(x: clockR.midX - ts / 2, y: clockR.midY - bigF.pointSize * 0.45),
             bigF, cText)
        f.dateFormat = "EEEE d MMMM yyyy"
        f.locale = Locale(identifier: "en_US")
        let dateStr = f.string(from: Date()).lowercased()
        let up = ProcessInfo.processInfo.systemUptime
        let sub = "\(dateStr)   ·   up \(Int(up) / 86400)d \(Int(up) % 86400 / 3600)h \(Int(up) % 3600 / 60)m"
        let subF = mono(15 * scale)
        text(sub, NSPoint(x: clockR.midX - tw(sub, subF) / 2, y: clockR.minY + 22 * scale), subF, cDim)

        // ── pane log
        let logR = NSRect(x: gap, y: gap, width: leftW - 1.5 * gap, height: H * 0.52 - 1.5 * gap)
        pane(logR, title: "om› journal", scale: scale)
        let logF = mono(13 * scale)
        let lineH = 20 * scale
        let maxLines = Int((logR.height - 40 * scale) / lineH)
        var y = logR.minY + 16 * scale
        for (line, color) in logLines.suffix(maxLines).reversed() {
            text(line, NSPoint(x: logR.minX + 18 * scale, y: y), logF, color)
            y += lineH
        }
        // curseur clignotant sur la dernière ligne
        if Int(Date().timeIntervalSince1970 * 2) % 2 == 0, let last = logLines.last {
            let lastW = tw(last.0, logF)
            cText.setFill()
            NSRect(x: logR.minX + 18 * scale + lastW + 6 * scale,
                   y: logR.minY + 16 * scale, width: 8 * scale, height: 15 * scale).fill()
        }

        // ── pane système (droite)
        let sysR = NSRect(x: leftW + 0.5 * gap, y: gap,
                          width: W - leftW - 1.5 * gap, height: H - 2 * gap)
        pane(sysR, title: "om› system", scale: scale)
        var sy = sysR.maxY - 46 * scale
        let labF = mono(11 * scale, .semibold)
        let inX = sysR.minX + 20 * scale
        let inW = sysR.width - 40 * scale

        text("CPU / CORES", NSPoint(x: inX, y: sy), labF, cDim)
        sy -= 14 * scale
        let barH = 12 * scale
        let cols = cpuLoads.count > 10 ? 2 : 1
        let rows = cols == 1 ? cpuLoads.count : (cpuLoads.count + 1) / 2
        let colW = (inW - CGFloat(cols - 1) * 14 * scale) / CGFloat(cols)
        for (i, load) in cpuLoads.enumerated() {
            let col = CGFloat(i / rows), row = CGFloat(i % rows)
            let bx = inX + col * (colW + 14 * scale)
            let by = sy - row * (barH + 7 * scale)
            cDim.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: bx + 26 * scale, y: by, width: colW - 26 * scale, height: barH),
                         xRadius: 2, yRadius: 2).fill()
            (load > 0.8 ? cGold : cAccent).setFill()
            NSBezierPath(roundedRect: NSRect(x: bx + 26 * scale, y: by,
                                             width: max(2, (colW - 26 * scale) * load), height: barH),
                         xRadius: 2, yRadius: 2).fill()
            text(String(format: "%2d", i), NSPoint(x: bx, y: by - 1), mono(10 * scale), cDim)
        }
        sy -= CGFloat(rows) * (barH + 7 * scale) + 26 * scale

        // RAM
        text("MEMORY", NSPoint(x: inX, y: sy), labF, cDim)
        let ramPct = String(format: "%.0f%%", ramUsed * 100)
        text(ramPct, NSPoint(x: inX + inW - tw(ramPct, labF), y: sy), labF, cText)
        sy -= 18 * scale
        cDim.withAlphaComponent(0.25).setFill()
        NSBezierPath(roundedRect: NSRect(x: inX, y: sy, width: inW, height: barH), xRadius: 2, yRadius: 2).fill()
        cGood.setFill()
        NSBezierPath(roundedRect: NSRect(x: inX, y: sy, width: max(2, inW * ramUsed), height: barH),
                     xRadius: 2, yRadius: 2).fill()
        sy -= 40 * scale

        // sparkline CPU
        text("LOAD · LAST 90 TICKS", NSPoint(x: inX, y: sy), labF, cDim)
        sy -= 12 * scale
        let gH = min(120 * scale, sy - sysR.minY - 60 * scale)
        let gR = NSRect(x: inX, y: sy - gH, width: inW, height: gH)
        if spark.count > 1, gH > 20 {
            let path = NSBezierPath()
            path.move(to: NSPoint(x: gR.minX, y: gR.minY))
            for (i, v) in spark.enumerated() {
                let x = gR.minX + gR.width * CGFloat(i) / CGFloat(spark.count - 1)
                path.line(to: NSPoint(x: x, y: gR.minY + gR.height * CGFloat(min(1, v))))
            }
            path.line(to: NSPoint(x: gR.maxX, y: gR.minY))
            path.close()
            cAccent.withAlphaComponent(0.3).setFill(); path.fill()
            cAccent.setStroke(); path.lineWidth = max(1, 1.2 * scale); path.stroke()
        }

        // host au bas du pane système
        let host = Host.current().localizedName ?? "mac"
        let hostF = mono(12 * scale)
        text("host \(host)", NSPoint(x: inX, y: sysR.minY + 18 * scale), hostF, cDim)

        // ── footer publicitaire rotatif (change toutes les ~12 s)
        let foot = promos[Int(Date().timeIntervalSince1970 / 12) % promos.count]
        let footF = mono(12 * scale)
        text(foot, NSPoint(x: W / 2 - tw(foot, footF) / 2, y: 6 * scale), footF,
             cDim.withAlphaComponent(0.85))
    }

    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
