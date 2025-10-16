@preconcurrency import Foundation
@preconcurrency import NetworkExtension
@preconcurrency import Combine
import XCEvents

public enum NEErr: Error {
    case notFound
    case connectFailled(Error)
}

public enum NEStatus: Int,Sendable {
//    case invalid = 0
//    case disconnected = 1
//    case connecting = 2
//    case connected = 3
//    case reasserting = 4
//    case disconnecting = 5
//    
//    case network_availability_testing = 600
//    case network_unavailable = 700
//    case realConnected = 800
//    case realFaile = 900
    
    case disconnecting
    case disconnected
    
    case connecting
    case connected
    
    case realConnected
    case realDisconnected
}

public actor XCTunnelManager {
    public static let share = XCTunnelManager()
    
    @MainActor
    public let statusSubject = PassthroughSubject<NEStatus, Never>()
    
    @MainActor
    public let durSubject = PassthroughSubject<Int, Never>()
    
    @MainActor
    public let avgSubject = PassthroughSubject<Int, Never>()
    
    @MainActor
    public var sysStatus: NEVPNStatus = .disconnected
    
    @MainActor
    var status: NEStatus = .disconnected {
        didSet {
            if oldValue != self.status {
                self.statusSubject.send(self.status)
            }
        }
    }
    
    @MainActor
    var dur = 0 {
        didSet {
            if oldValue != self.dur {
                self.durSubject.send(self.dur)
            }
        }
    }
    
    @MainActor
    var avg = 0 {
        didSet {
            if oldValue != self.avg {
                self.avgSubject.send(self.avg)
            }
        }
    }
    
    private init() {
        NotificationCenter.default.addObserver(forName: .NEVPNStatusDidChange, object: nil, queue: .main) { notif in
            let new = (notif.object as? NEVPNConnection)?.status ?? .disconnected
            Task {
                await XCTunnelManager.share.statusUpdate(new)
            }
        }
    }
    
    private var manager: NEVPNManager?
    
    static func asyncStatusStream() -> AsyncStream<NEVPNStatus> {
        AsyncStream<NEVPNStatus> { continuation in
            let observer = NotificationCenter.default.addObserver(
                forName: .NEVPNStatusDidChange,
                object: nil,
                queue: .main
            ) { notification in
                let vpnStatus = (notification.object as? NEVPNConnection)?.status ?? .disconnected
                continuation.yield(vpnStatus)
            }
            
            continuation.onTermination = { _ in
                NotificationCenter.default.removeObserver(observer)
            }
            
            Task {
                try await Task.sleep(nanoseconds: 500_000_000)
                let status = await XCTunnelManager.share.manager?.connection.status ?? .invalid
                continuation.yield(status)
            }
        }
    }
}

public extension XCTunnelManager {
    func getManager(_ isCreate: Bool = false) async throws -> NEVPNManager {
        if let manager = self.manager {
            return manager
        }
        try await self.load(isCreate)
        if let manager = self.manager {
            return manager
        }
        throw NEErr.notFound
    }
    
    func load(_ isCreate: Bool = true) async throws {
        let managers = try await NETunnelProviderManager.loadAllFromPreferences()
        var manager = managers.last
        if manager == nil && isCreate {
            manager = try await self.create()
        }
        try await self.save(manager)
        manager = try await NETunnelProviderManager.loadAllFromPreferences().last
        self.manager = manager
        let status = self.manager?.connection.status ?? .invalid
        if status == .disconnected || status == .invalid {
            await self.setStatus(.realDisconnected)
        }
    }
    
    func enable() async throws {
        let manager = if let m = self.manager {
            m
        } else {
            try await self.getManager()
        }
        try await self.save(manager)
    }

    @MainActor
    func setStatus(_ status: NEStatus) async {
        self.status = status
    }
    
    @MainActor
    func getStatus() async -> NEStatus {
        return self.status
    }
    
    @MainActor
    func statusAsyncStream(stopCondition: NEStatus) -> AsyncStream<NEStatus> {
        return AsyncStream { continuation in
            let publisher = self.statusSubject.eraseToAnyPublisher()
            let cancellable = publisher.sink { status in
                continuation.yield(status)
                if status == stopCondition {
                    continuation.finish()
                }
            }
            continuation.onTermination = { _ in
                cancellable.cancel()
            }
        }
    }
}

private extension XCTunnelManager {
    func create() async throws -> NETunnelProviderManager {
        let manager = NETunnelProviderManager()
        let p = NETunnelProviderProtocol()
        p.serverAddress = "UnlimitedVPNMaster"
        p.providerBundleIdentifier = "com.unlimitedr.tunnel.main.ex"
        manager.protocolConfiguration = p
        return manager
    }
    
    func save(_ manager: NEVPNManager?) async throws {
        manager?.isEnabled = true
        try await manager?.saveToPreferences()
    }
    
    @MainActor
    func statusUpdate(_ new: NEVPNStatus) async {
        self.sysStatus = new
    }
}

public extension XCTunnelManager {
    /// 传加密的
    func connect(_ node: String) async throws {
        
        let manager = try await self.getManager(true)
        try await self.save(manager)
        try manager.connection.startVPNTunnel(options: ["node": node as NSString])
        let stream = XCTunnelManager.asyncStatusStream()
        for await status in stream {
            if status == .connected {
                return
            } else if status == .disconnected || status == .invalid {
                try await self.stop()
                throw NSError(domain: "Connect falie", code: -1)
            }
        }
    }
    
    func reload(_ node: String) async throws {
        guard let data = node.data(using: .utf8) else { throw NSError(domain: "reload err", code: -1) }
        let manager = try await self.getManager()
        try (manager.connection as? NETunnelProviderSession)?.sendProviderMessage(data)
    }
    
    func stop() async throws {
        try await self.getManager().connection.stopVPNTunnel()
        let stream = XCTunnelManager.asyncStatusStream()
        for await status in stream {
            if status == .disconnected || status == .invalid {
                return
            }
        }
    }
    
    func stopAll() async throws {
        let manager = try await self.getManager()
        try await self.save(manager)
        manager.connection.stopVPNTunnel()
    }
}
