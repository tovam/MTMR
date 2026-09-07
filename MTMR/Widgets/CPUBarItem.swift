//
//  CPUBarItem.swift
//  MMTMR
//
//  Pixel-history graphs for CPU and memory usage.
//

import AppKit
import Foundation

enum SystemUsageMetric: Sendable {
    case cpu
    case memory

    var accessibilityLabel: String {
        switch self {
        case .cpu: return "Historique d’utilisation du processeur"
        case .memory: return "Historique d’utilisation de la mémoire"
        }
    }
}

private struct SystemUsageSampler {
    let metric: SystemUsageMetric
    private var previousCPULoad: host_cpu_load_info_data_t?

    init(metric: SystemUsageMetric) {
        self.metric = metric
        self.previousCPULoad = nil
    }

    mutating func sample() -> Double? {
        switch metric {
        case .cpu:
            return sampleCPU()
        case .memory:
            return sampleMemory()
        }
    }

    private mutating func sampleCPU() -> Double? {
        var load = host_cpu_load_info()
        var count = mach_msg_type_number_t(
            MemoryLayout<host_cpu_load_info_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &load) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics(mach_host_self(), HOST_CPU_LOAD_INFO, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }
        guard let previous = previousCPULoad else {
            previousCPULoad = load
            return nil
        }
        previousCPULoad = load

        let user = Double(load.cpu_ticks.0 &- previous.cpu_ticks.0)
        let system = Double(load.cpu_ticks.1 &- previous.cpu_ticks.1)
        let idle = Double(load.cpu_ticks.2 &- previous.cpu_ticks.2)
        let nice = Double(load.cpu_ticks.3 &- previous.cpu_ticks.3)
        let total = user + system + idle + nice
        guard total > 0 else { return nil }
        return min(1, max(0, (user + system + nice) / total))
    }

    private func sampleMemory() -> Double? {
        var statistics = vm_statistics64()
        var count = mach_msg_type_number_t(
            MemoryLayout<vm_statistics64_data_t>.size / MemoryLayout<integer_t>.size
        )
        let result = withUnsafeMutablePointer(to: &statistics) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                host_statistics64(mach_host_self(), HOST_VM_INFO64, $0, &count)
            }
        }
        guard result == KERN_SUCCESS else { return nil }

        var pageSize: vm_size_t = 0
        guard host_page_size(mach_host_self(), &pageSize) == KERN_SUCCESS, pageSize > 0 else {
            return nil
        }
        let totalPages = ProcessInfo.processInfo.physicalMemory / UInt64(pageSize)
        guard totalPages > 0 else { return nil }

        let reclaimablePages = UInt64(statistics.free_count)
            + UInt64(statistics.inactive_count)
            + UInt64(statistics.speculative_count)
        let availablePages = min(totalPages, reclaimablePages)
        return Double(totalPages - availablePages) / Double(totalPages)
    }
}

@MainActor
private final class SystemUsageGraphView: NSView, RuntimeRenderSignatureProviding {
    static let size = NSSize(width: 30, height: 30)

    // Calm at normal load, increasingly warm only in the upper range.
    private static let loadGradient = NSGradient(
        colorsAndLocations:
        (NSColor(srgbRed: 0.27, green: 0.72, blue: 0.48, alpha: 0.95), 0.00),
        (NSColor(srgbRed: 0.27, green: 0.72, blue: 0.48, alpha: 0.95), 0.55),
        (NSColor(srgbRed: 0.83, green: 0.71, blue: 0.29, alpha: 0.95), 0.70),
        (NSColor(srgbRed: 0.84, green: 0.51, blue: 0.27, alpha: 0.95), 0.85),
        (NSColor(srgbRed: 0.84, green: 0.33, blue: 0.33, alpha: 0.95), 1.00)
    )

    private var samples: [CGFloat] = []
    private var revision: UInt64 = 0

    init() {
        super.init(frame: NSRect(origin: .zero, size: Self.size))
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var intrinsicContentSize: NSSize { Self.size }
    override var isOpaque: Bool { false }
    var runtimeRenderSignature: String { String(revision) }

    func append(_ usage: Double) {
        samples.append(CGFloat(min(1, max(0, usage))))
        revision &+= 1
        if samples.count > 512 {
            samples.removeFirst(samples.count - 512)
        }
        needsDisplay = true
        NotificationCenter.default.post(name: .mmtmrRuntimeVisualDidChange, object: nil)
    }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        guard let context = NSGraphicsContext.current else { return }

        context.saveGraphicsState()
        defer { context.restoreGraphicsState() }
        context.shouldAntialias = false

        // Clear our own pixels instead of painting a card behind the graph.
        // The native Touch Bar background remains visible through the view.
        context.compositingOperation = .copy
        NSColor.clear.setFill()
        bounds.fill()
        context.compositingOperation = .sourceOver

        let scale = max(1, window?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
        let pixel = 1 / scale
        let capacity = max(1, Int((bounds.width * scale).rounded(.down)))
        let visibleSamples = samples.suffix(capacity)
        let startingX = bounds.maxX - CGFloat(visibleSamples.count) * pixel

        let bars = NSBezierPath()
        for (index, sample) in visibleSamples.enumerated() {
            let height = (sample * bounds.height * scale).rounded(.down) / scale
            guard height > 0 else { continue }
            bars.appendRect(NSRect(
                x: startingX + CGFloat(index) * pixel,
                y: bounds.minY,
                width: pixel,
                height: min(bounds.height, height)
            ))
        }
        bars.addClip()
        Self.loadGradient?.draw(
            from: NSPoint(x: bounds.midX, y: bounds.minY),
            to: NSPoint(x: bounds.midX, y: bounds.maxY),
            options: []
        )
    }
}

/// A fixed-size graph. Every successful sample appends one physical-pixel
/// column at the right edge; older columns move left and eventually disappear.
@MainActor
final class SystemUsageBarItem: NSCustomTouchBarItem {
    @MainActor
    private final class TimerTarget: NSObject {
        weak var owner: SystemUsageBarItem?

        init(owner: SystemUsageBarItem) {
            self.owner = owner
        }

        @objc func fire() {
            owner?.sampleTimerFired()
        }
    }

    private let metric: SystemUsageMetric
    private let refreshInterval: TimeInterval
    private let graphView = SystemUsageGraphView()
    private var sampler: SystemUsageSampler
    private var timer: Timer?
    private var timerTarget: TimerTarget?

    init(
        identifier: NSTouchBarItem.Identifier,
        metric: SystemUsageMetric,
        refreshInterval: TimeInterval
    ) {
        self.metric = metric
        self.refreshInterval = min(30, max(1, refreshInterval.isFinite ? refreshInterval : 2))
        self.sampler = SystemUsageSampler(metric: metric)
        super.init(identifier: identifier)

        timerTarget = TimerTarget(owner: self)
        view = graphView
        updateAccessibility(usage: nil)
        sampleAndSchedule()
    }

    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func sampleTimerFired() {
        sampleAndSchedule()
    }

    private func sampleAndSchedule() {
        timer?.invalidate()
        timer = nil

        guard let usage = sampler.sample(), usage.isFinite else {
            // CPU usage is a delta, so obtain its second counter snapshot fast.
            schedule(after: metric == .cpu ? 0.35 : refreshInterval)
            return
        }

        graphView.append(usage)
        updateAccessibility(usage: usage)
        schedule(after: refreshInterval)
    }

    private func schedule(after interval: TimeInterval) {
        guard let timerTarget else { return }
        let timer = Timer(
            timeInterval: interval,
            target: timerTarget,
            selector: #selector(TimerTarget.fire),
            userInfo: nil,
            repeats: false
        )
        self.timer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private func updateAccessibility(usage: Double?) {
        graphView.setAccessibilityLabel(metric.accessibilityLabel)
        graphView.setAccessibilityValue(
            usage.map { "\(Int(($0 * 100).rounded())) %" } ?? "Mesure en cours"
        )
    }

    isolated deinit {
        timer?.invalidate()
    }
}
