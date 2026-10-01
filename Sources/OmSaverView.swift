//
//  OmSaver — a TUI, Omarchy-vibes screensaver for macOS.
//  Part of the Om series (https://omfi.stranix.net) by Stranix. Free & MIT.
//
//  -- ROLE OF THIS FILE -----------------------------------------------------
//  This is THE whole program: a single class, OmSaverView. A macOS
//  screensaver is not an executable you launch, it is a *plugin* (.saver
//  bundle) loaded by a system process, `legacyScreenSaver`. That process
//  reads the bundle's Info.plist, finds the NSPrincipalClass key
//  ("OmSaverView"), instantiates the class and hands it a full-screen window.
//  We control neither main() nor the event loop: we provide a *view* (in the
//  AppKit sense, like a VB.NET control) and the system animates it.
//
//  The life cycle, imposed by the parent class ScreenSaverView:
//    1. init(frame:isPreview:)  - called once when the plugin is loaded
//    2. animateOneFrame()       - called by a system timer at the rate of
//                                 animationTimeInterval (here 8 times/s);
//                                 this is where the STATE is updated
//                                 (stats, log)
//    3. draw(_:)                - called when the view must repaint; this is
//                                 where the state is DRAWN, nothing else
//  Keeping 2 and 3 apart is the AppKit rule: draw() can be called at any
//  time by the system (resize, etc.), so it must be "pure".
//
//  Three tiling-WM style panes, thin blue borders, Hyprland-ish gaps:
//   ┌ clock ─────────────┐ ┌ system ────────┐
//   │  HH:MM:SS  (huge)  │ │ real CPU bars  │
//   │  date · uptime     │ │ RAM · load     │
//   ├ log ───────────────┤ │ sparkline      │
//   │ geek scrolling log │ └────────────────┘
//   └────────────────────┘   om› series footer
//
import ScreenSaver   // the parent class ScreenSaverView + the plugin contract
import AppKit        // the Mac graphics toolkit (windows, drawing, fonts)
import Darwin        // low-level kernel calls (Mach), Apple's "libc"

// @objc(OmSaverView): exposes the class to the Objective-C runtime under this
// EXACT name. Essential: legacyScreenSaver looks the class up by the string
// "OmSaverView" written in the Info.plist (NSPrincipalClass). Without this
// attribute Swift would decorate the name (mangling) and the plugin would
// not load.
@objc(OmSaverView)
public final class OmSaverView: ScreenSaverView {

    // palette Omarchy (same as OmFi)
    // NSColor takes RGB in 0...1 (not 0...255 as in VB.NET/GDI+).
    private let cBG = NSColor(red: 0.04, green: 0.045, blue: 0.07, alpha: 1)
    private let cBorder = NSColor(red: 0.48, green: 0.60, blue: 0.85, alpha: 1)
    private let cText = NSColor(red: 0.80, green: 0.84, blue: 0.92, alpha: 1)
    private let cDim = NSColor(red: 0.40, green: 0.45, blue: 0.56, alpha: 1)
    private let cAccent = NSColor(red: 0.54, green: 0.65, blue: 0.88, alpha: 1)
    private let cGood = NSColor(red: 0.65, green: 0.89, blue: 0.63, alpha: 1)
    private let cGold = NSColor(red: 0.90, green: 0.76, blue: 0.48, alpha: 1)

    // -- mutable state, updated in animateOneFrame(), read in draw() --
    private var logLines: [(String, NSColor)] = []   // the displayed log (text, color)
    private var nextLog: TimeInterval = 0            // timestamp of the next log line
    private var spark: [Double] = []                 // average CPU history (sparkline)
    private var cpuPrev: [(UInt32, UInt32)] = []   // (busy, total) per core, previous sample
    private var cpuLoads: [Double] = []              // load 0...1 per core, ready to draw
    private var ramUsed: Double = 0                  // fraction 0...1 of RAM in use

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
    // the house ads: the gadget sells the suite (iBeer in reverse)
    private let promos = [
        "om› OmSuite — Omarchy vibes for macOS · om.stranix.net",
        "om› OmFi — the Wi-Fi panel behind this saver · omfi.stranix.net · 2.99",
        "om› ZapZap — WhatsApp one keystroke away · zapzap.stranix.net",
        "om› Sygnet — bookmark sync that includes Safari · sygnet.app",
        "om› more small sharp apps · apps.stranix.net",
    ]
    private var promoIdx = 0
    // "credible" fake operations: pure theatre, nothing is actually done
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

    // The constructor imposed by ScreenSaverView. `isPreview` is true when the
    // view is the small thumbnail in System Settings (same code, tiny frame,
    // hence the `scale` factor in draw()). The `init?` return type means a
    // constructor that can fail and return nil, the Cocoa convention.
    public override init?(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        // Rate of the system timer that will call animateOneFrame().
        // 8 Hz is plenty for a clock and some bars; no need to burn CPU at
        // 60 fps on a screen that is supposed to save energy.
        animationTimeInterval = 1.0 / 8.0
        for (m, kind) in bootMsgs {
            logLines.append((stamp(m), kind == 0 ? cAccent : cDim))
        }
    }
    // Second constructor required by NSCoding (deserialization from an
    // Interface Builder file). Never used here, but the compiler demands it
    // as soon as init is overridden; we simply delegate to the parent.
    required init?(coder: NSCoder) { super.init(coder: coder) }

    // Prefixes a log line with the current time, syslog style.
    private func stamp(_ s: String) -> String {
        let f = DateFormatter(); f.dateFormat = "HH:mm:ss"
        return "[\(f.string(from: Date()))] \(s)"
    }

    // MARK: real system stats
    //
    // Here we leave the comfortable Swift world to talk to the kernel through
    // the Mach APIs, the macOS equivalent of reading /proc/stat on Linux.
    // These are C APIs: raw pointers, memory you must free yourself.

    private func sampleCPU() {
        // host_processor_info() returns, for each core, COUNTERS ACCUMULATED
        // since boot (ticks spent in user/system/nice/idle). A single snapshot
        // says nothing: the load is the DIFFERENCE between two samples (as
        // with /proc/stat).
        var cpuCount: natural_t = 0
        var info: processor_info_array_t?          // C pointer filled by the kernel
        var infoCount: mach_msg_type_number_t = 0
        guard host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO,
                                  &cpuCount, &info, &infoCount) == KERN_SUCCESS,
              let info = info else { return }
        // The kernel allocated this array in OUR address space; ARC knows
        // nothing about it, so it must be returned by hand (otherwise a leak
        // on every tick). `defer` = run when the function exits, no matter how.
        defer {
            vm_deallocate(mach_task_self_, vm_address_t(bitPattern: info),
                          vm_size_t(infoCount) * vm_size_t(MemoryLayout<integer_t>.size))
        }
        var loads: [Double] = []
        var prev: [(UInt32, UInt32)] = []
        for i in 0..<Int(cpuCount) {
            // The array is flat: CPU_STATE_MAX integers per core.
            let base = i * Int(CPU_STATE_MAX)
            let user = UInt32(bitPattern: info[base + Int(CPU_STATE_USER)])
            let sys = UInt32(bitPattern: info[base + Int(CPU_STATE_SYSTEM)])
            let nice = UInt32(bitPattern: info[base + Int(CPU_STATE_NICE)])
            let idle = UInt32(bitPattern: info[base + Int(CPU_STATE_IDLE)])
            // `&+` / `&-`: modulo (wrapping) arithmetic. In Swift an integer
            // overflow CRASHES by default, yet these 32-bit counters wrap
            // around after a few weeks of uptime, and the difference stays
            // correct in modulo arithmetic, exactly as in C.
            let busy = user &+ sys &+ nice
            let total = busy &+ idle
            if i < cpuPrev.count {
                let db = Double(busy &- cpuPrev[i].0)
                let dt = Double(total &- cpuPrev[i].1)
                loads.append(dt > 0 ? min(1, db / dt) : 0)
            } else {
                loads.append(0)   // first pass: no delta yet
            }
            prev.append((busy, total))
        }
        cpuPrev = prev
        cpuLoads = loads

        // RAM: host_statistics64() fills a C struct of memory page counters.
        // The API expects a pointer to integer_t; `withMemoryRebound`
        // temporarily reinterprets our struct as an array of integers, the
        // (int *)&stats cast of C, but explicit and bounded, as Swift demands.
        var stats = vm_statistics64()
        var count = mach_msg_type_number_t(MemoryLayout<vm_statistics64>.size / MemoryLayout<integer_t>.size)
        let host = mach_host_self()
        _ = withUnsafeMutablePointer(to: &stats) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(host, HOST_VM_INFO64, $0, &count)
            }
        }
        // "Used" memory = active pages + wired (non-pageable, kernel) +
        // compressed, the same formula Activity Monitor uses.
        let pageSize = Double(vm_kernel_page_size)
        let used = (Double(stats.active_count) + Double(stats.wire_count)
                    + Double(stats.compressor_page_count)) * pageSize
        let total = Double(ProcessInfo.processInfo.physicalMemory)
        ramUsed = total > 0 ? used / total : 0
    }

    // MARK: animation

    // Called about 8 times/s by the ScreenSaverView timer. This is the
    // saver's "game loop": update the state, then needsDisplay = true asks
    // the system to call draw() again on the next display cycle.
    // We NEVER draw directly here.
    public override func animateOneFrame() {
        sampleCPU()
        let avg = cpuLoads.isEmpty ? 0 : cpuLoads.reduce(0, +) / Double(cpuLoads.count)
        spark.append(avg)
        if spark.count > 90 { spark.removeFirst() }   // sliding window of 90 ticks
        let now = Date().timeIntervalSince1970
        if now >= nextLog {
            // next log line in 1.2 to 3.5 s (deliberately irregular rhythm,
            // more "alive" than a metronome)
            nextLog = now + Double.random(in: 1.2...3.5)
            let roll = Int.random(in: 0..<10)   // ten-sided die: 10% ads, 30% fun, 60% ops
            if roll == 0 {
                // an ad line now and then, in series green
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
    //
    // AppKit draws in "immediate mode": inside draw(), a current graphics
    // context is already open, and setFill()/fill()/stroke() act on it
    // implicitly (close to GDI+ in VB.NET).
    // CAREFUL with the AppKit coordinate system: the origin (0,0) is at the
    // BOTTOM left and Y goes up, the opposite of VB.NET, HTML and almost
    // everything else.

    private func mono(_ size: CGFloat, _ weight: NSFont.Weight = .medium) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: weight)
    }
    // Draws a string at a given point (p = bottom-left corner of the text).
    private func text(_ s: String, _ p: NSPoint, _ font: NSFont, _ color: NSColor) {
        (s as NSString).draw(at: p, withAttributes: [.font: font, .foregroundColor: color])
    }
    // Width of a string in a given font, used to center/align.
    private func tw(_ s: String, _ font: NSFont) -> CGFloat {
        (s as NSString).size(withAttributes: [.font: font]).width
    }
    // Draws a TUI "pane": rounded frame + title embedded in the top border
    // (paint a small background rectangle over the line, then the title
    // inside it, the classic TUI trick).
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

    // The full rendering, repainted every frame. Everything is positioned as
    // fractions of the view size plus a `scale` factor calibrated on a
    // 1440x900 reference screen: the same code fills a 5K display or the
    // preview thumbnail in System Settings.
    public override func draw(_ rect: NSRect) {
        cBG.setFill()
        bounds.fill()
        let W = bounds.width, H = bounds.height
        let scale = max(0.5, min(W / 1440, H / 900))
        let gap = 24 * scale
        let leftW = W * 0.58

        // -- clock pane (reminder: y=H*0.52 is measured from the BOTTOM of the screen)
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

        // -- log pane
        let logR = NSRect(x: gap, y: gap, width: leftW - 1.5 * gap, height: H * 0.52 - 1.5 * gap)
        pane(logR, title: "om› journal", scale: scale)
        let logF = mono(13 * scale)
        let lineH = 20 * scale
        let maxLines = Int((logR.height - 40 * scale) / lineH)
        var y = logR.minY + 16 * scale
        // .reversed(): the most recent line at the bottom, like a terminal
        // (start from the bottom of the pane and stack upwards).
        for (line, color) in logLines.suffix(maxLines).reversed() {
            text(line, NSPoint(x: logR.minX + 18 * scale, y: y), logF, color)
            y += lineH
        }
        // blinking cursor on the last line
        // (visible every other half second, derived from the clock; no
        // dedicated timer needed since we repaint 8 times/s)
        if Int(Date().timeIntervalSince1970 * 2) % 2 == 0, let last = logLines.last {
            let lastW = tw(last.0, logF)
            cText.setFill()
            NSRect(x: logR.minX + 18 * scale + lastW + 6 * scale,
                   y: logR.minY + 16 * scale, width: 8 * scale, height: 15 * scale).fill()
        }

        // -- system pane (right)
        let sysR = NSRect(x: leftW + 0.5 * gap, y: gap,
                          width: W - leftW - 1.5 * gap, height: H - 2 * gap)
        pane(sysR, title: "om› system", scale: scale)
        // `sy` is a vertical cursor: start from the TOP of the pane (maxY)
        // and go DOWN section by section (hence sy -= ..., Y downwards).
        var sy = sysR.maxY - 46 * scale
        let labF = mono(11 * scale, .semibold)
        let inX = sysR.minX + 20 * scale
        let inW = sysR.width - 40 * scale

        text("CPU / CORES", NSPoint(x: inX, y: sy), labF, cDim)
        sy -= 14 * scale
        let barH = 12 * scale
        // beyond 10 cores, two columns (modern Macs have 8 to 16+)
        let cols = cpuLoads.count > 10 ? 2 : 1
        let rows = cols == 1 ? cpuLoads.count : (cpuLoads.count + 1) / 2
        let colW = (inW - CGFloat(cols - 1) * 14 * scale) / CGFloat(cols)
        for (i, load) in cpuLoads.enumerated() {
            let col = CGFloat(i / rows), row = CGFloat(i % rows)
            let bx = inX + col * (colW + 14 * scale)
            let by = sy - row * (barH + 7 * scale)
            // gauge background (full bar, dimmed)...
            cDim.withAlphaComponent(0.25).setFill()
            NSBezierPath(roundedRect: NSRect(x: bx + 26 * scale, y: by, width: colW - 26 * scale, height: barH),
                         xRadius: 2, yRadius: 2).fill()
            // ...then the fill proportional to the load (gold above 80%)
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

        // CPU sparkline: a closed polygon (line + return along the bottom),
        // filled translucent then outlined, the "area chart" look
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

        // host name at the bottom of the system pane
        let host = Host.current().localizedName ?? "mac"
        let hostF = mono(12 * scale)
        text("host \(host)", NSPoint(x: inX, y: sysR.minY + 18 * scale), hostF, cDim)

        // -- rotating ad footer (changes every ~12 s)
        // Bundle(for:) finds the .saver bundle that contains THIS class
        // (not Bundle.main, which would be legacyScreenSaver!) and reads the
        // version from its Info.plist, written by build.sh, single source.
        let appV = Bundle(for: OmSaverView.self).infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let foot = promos[Int(Date().timeIntervalSince1970 / 12) % promos.count] + "  ·  om› saver v" + appV
        let footF = mono(12 * scale)
        text(foot, NSPoint(x: W / 2 - tw(foot, footF) / 2, y: 6 * scale), footF,
             cDim.withAlphaComponent(0.85))
    }

    // No "Options..." sheet in System Settings: declare it, otherwise macOS
    // would show a button that opens... nothing.
    public override var hasConfigureSheet: Bool { false }
    public override var configureSheet: NSWindow? { nil }
}
