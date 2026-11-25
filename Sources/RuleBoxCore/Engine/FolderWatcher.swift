import Foundation

/// Kernel-level macOS folder watcher backed by `DispatchSourceFileSystemObject` (`O_EVTONLY`)
/// with per-folder debouncing so burst writes coalesce into a single rule pass.
public final class FolderWatcher: @unchecked Sendable {
    private struct WatchHandle {
        let folderID: UUID
        let path: String
        let fd: Int32
        let source: DispatchSourceFileSystemObject
        var pendingDebounce: DispatchWorkItem?
    }

    private let queue = DispatchQueue(label: "com.rulebox.folder-watcher", qos: .utility)
    private var handles: [UUID: WatchHandle] = [:]
    private let debounceInterval: TimeInterval
    private let onFolderChanged: @Sendable (UUID) -> Void

    public init(debounceInterval: TimeInterval = 0.4, onFolderChanged: @escaping @Sendable (UUID) -> Void) {
        self.debounceInterval = debounceInterval
        self.onFolderChanged = onFolderChanged
    }

    deinit {
        stopAll()
    }

    public func sync(folders: [WatchedFolder], active: Bool) {
        queue.async { [weak self] in
            guard let self else { return }
            if !active {
                self.stopAllLocked()
                return
            }

            let desired: [UUID: String] = Dictionary(
                uniqueKeysWithValues: folders.filter(\.isEnabled).map { ($0.id, $0.path) }
            )

            // Remove stale or changed watchers
            for (id, handle) in self.handles {
                if desired[id] != handle.path {
                    handle.pendingDebounce?.cancel()
                    handle.source.cancel()
                    self.handles.removeValue(forKey: id)
                }
            }

            // Start new watchers
            for (id, path) in desired where self.handles[id] == nil {
                self.startWatchingLocked(folderID: id, path: path)
            }
        }
    }

    public func stopAll() {
        queue.sync {
            stopAllLocked()
        }
    }

    private func stopAllLocked() {
        for (_, handle) in handles {
            handle.pendingDebounce?.cancel()
            handle.source.cancel()
        }
        handles.removeAll()
    }

    private func startWatchingLocked(folderID: UUID, path: String) {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fd,
            eventMask: [.write, .extend, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            guard let self, var handle = self.handles[folderID] else { return }
            handle.pendingDebounce?.cancel()
            let work = DispatchWorkItem { [weak self] in
                self?.onFolderChanged(folderID)
            }
            handle.pendingDebounce = work
            self.handles[folderID] = handle
            self.queue.asyncAfter(deadline: .now() + self.debounceInterval, execute: work)
        }

        source.setCancelHandler {
            close(fd)
        }

        handles[folderID] = WatchHandle(folderID: folderID, path: path, fd: fd, source: source, pendingDebounce: nil)
        source.resume()
    }
}
