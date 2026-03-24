import CoreServices
import Foundation

public final class FolderMonitor {
    public typealias EventHandler = @Sendable ([String]) -> Void

    private let url: URL
    private let handler: EventHandler
    private var stream: FSEventStreamRef?

    public init(url: URL, handler: @escaping EventHandler) {
        self.url = url
        self.handler = handler
    }

    deinit {
        stop()
    }

    public func start() {
        guard stream == nil else { return }

        let context = Unmanaged.passRetained(FolderMonitorContext(handler: handler))

        var callbacks = FSEventStreamContext(
            version: 0,
            info: context.toOpaque(),
            retain: { info in
                guard let info else { return nil }
                _ = Unmanaged<FolderMonitorContext>.fromOpaque(info).retain()
                return UnsafeRawPointer(info)
            },
            release: { info in
                guard let info else { return }
                Unmanaged<FolderMonitorContext>.fromOpaque(UnsafeMutableRawPointer(mutating: info)).release()
            },
            copyDescription: nil
        )

        stream = FSEventStreamCreate(
            kCFAllocatorDefault,
            { _, info, count, pathsPointer, _, _ in
                guard let info else { return }
                let context = Unmanaged<FolderMonitorContext>.fromOpaque(info).takeUnretainedValue()
                let paths = unsafeBitCast(pathsPointer, to: NSArray.self) as? [String] ?? []
                context.handler(Array(paths.prefix(count)))
            },
            &callbacks,
            [url.path] as CFArray,
            FSEventStreamEventId(kFSEventStreamEventIdSinceNow),
            0.7,
            FSEventStreamCreateFlags(
                kFSEventStreamCreateFlagFileEvents |
                kFSEventStreamCreateFlagUseCFTypes |
                kFSEventStreamCreateFlagNoDefer
            )
        )

        guard let stream else { return }

        FSEventStreamSetDispatchQueue(stream, DispatchQueue.main)
        FSEventStreamStart(stream)
    }

    public func stop() {
        guard let stream else { return }
        FSEventStreamStop(stream)
        FSEventStreamInvalidate(stream)
        FSEventStreamRelease(stream)
        self.stream = nil
    }
}

private final class FolderMonitorContext {
    let handler: FolderMonitor.EventHandler

    init(handler: @escaping FolderMonitor.EventHandler) {
        self.handler = handler
    }
}
