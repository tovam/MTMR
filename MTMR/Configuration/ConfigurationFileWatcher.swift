import Darwin
import Foundation

/// Watches the parent directory rather than the JSON inode so editor-style
/// atomic save/rename operations remain observable.
final class ConfigurationFileWatcher: @unchecked Sendable {
    private let configurationURL: URL
    private let debounceInterval: TimeInterval
    private let queue: DispatchQueue
    private let callbackQueue: DispatchQueue
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var debounceWorkItem: DispatchWorkItem?
    private var onChange: (@Sendable () -> Void)?

    init(
        configurationURL: URL,
        debounceInterval: TimeInterval = 0.15,
        queue: DispatchQueue = DispatchQueue(label: "com.tovam.MMTMR.configuration-watcher"),
        callbackQueue: DispatchQueue = .main
    ) {
        self.configurationURL = configurationURL
        self.debounceInterval = debounceInterval
        self.queue = queue
        self.callbackQueue = callbackQueue
    }

    func startWatching(onChange: @escaping @Sendable () -> Void) throws {
        try queue.sync {
            stopWatchingOnQueue()
            self.onChange = onChange
            try armDirectorySource()
            armFileSourceIfPresent()
        }
    }

    func stopWatching() {
        queue.sync { stopWatchingOnQueue() }
    }

    deinit {
        directorySource?.cancel()
        fileSource?.cancel()
        debounceWorkItem?.cancel()
    }

    private func armDirectorySource() throws {
        let directoryURL = configurationURL.deletingLastPathComponent()
        let descriptor = open(directoryURL.path, O_EVTONLY)
        guard descriptor >= 0 else {
            throw ConfigurationDiagnostic(
                code: "watcher.open",
                path: directoryURL.path,
                message: "Could not watch configuration directory (errno \(errno))."
            )
        }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .link, .revoke],
            queue: queue
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self, let newSource else { return }
            self.directoryEvent(flags: newSource.data)
        }
        newSource.setCancelHandler { close(descriptor) }
        directorySource = newSource
        newSource.resume()
    }

    private func directoryEvent(flags: DispatchSource.FileSystemEvent) {
        let rearmDirectory = !flags.intersection([.delete, .rename, .revoke]).isEmpty
        if rearmDirectory {
            directorySource?.cancel()
            directorySource = nil
        }
        // An atomic save replaces the file inode. Reopen it after every parent
        // directory mutation so subsequent in-place writes remain observable.
        fileSource?.cancel()
        fileSource = nil
        scheduleChange(rearmDirectory: rearmDirectory, rearmFile: true)
    }

    private func armFileSourceIfPresent() {
        guard fileSource == nil else { return }
        let descriptor = open(configurationURL.path, O_EVTONLY)
        guard descriptor >= 0 else { return }

        let newSource = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .delete, .rename, .attrib, .extend, .revoke],
            queue: queue
        )
        newSource.setEventHandler { [weak self, weak newSource] in
            guard let self, let newSource else { return }
            self.fileEvent(flags: newSource.data)
        }
        newSource.setCancelHandler { close(descriptor) }
        fileSource = newSource
        newSource.resume()
    }

    private func fileEvent(flags: DispatchSource.FileSystemEvent) {
        let mustRearm = !flags.intersection([.delete, .rename, .revoke]).isEmpty
        if mustRearm {
            fileSource?.cancel()
            fileSource = nil
        }
        scheduleChange(rearmDirectory: false, rearmFile: mustRearm)
    }

    private func scheduleChange(rearmDirectory: Bool, rearmFile: Bool) {
        debounceWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            guard let self else { return }
            if rearmDirectory, self.directorySource == nil {
                try? self.armDirectorySource()
            }
            if rearmFile || self.fileSource == nil {
                self.armFileSourceIfPresent()
            }
            let callback = self.onChange
            self.callbackQueue.async { callback?() }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }

    private func stopWatchingOnQueue() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        directorySource?.cancel()
        directorySource = nil
        fileSource?.cancel()
        fileSource = nil
        onChange = nil
    }
}
