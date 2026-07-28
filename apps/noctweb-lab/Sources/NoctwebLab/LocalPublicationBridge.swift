import Foundation
import Network

/// A loopback-only bridge that lets the separately sandboxed native Browser
/// request an already-signed Lab publication. It exposes no publisher keys,
/// drafts, workspace metadata, or write capability.
final class LocalPublicationBridge: @unchecked Sendable {
    static let port: NWEndpoint.Port = 9477

    private let publicationProvider: @Sendable (String) async -> Data?
    private let queue = DispatchQueue(
        label: "net.noctweave.noctweb-lab.publication-bridge",
        qos: .utility
    )
    private let lock = NSLock()
    private var listener: NWListener?

    init(
        publicationProvider: @escaping @Sendable (String) async -> Data?
    ) {
        self.publicationProvider = publicationProvider
    }

    func start() {
        lock.lock()
        defer { lock.unlock() }
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            parameters.requiredLocalEndpoint = .hostPort(
                host: "127.0.0.1",
                port: Self.port
            )
            let listener = try NWListener(using: parameters)
            listener.newConnectionHandler = { [weak self] connection in
                self?.handle(connection)
            }
            listener.stateUpdateHandler = { [weak self, weak listener] state in
                if case .failed = state {
                    self?.clear(listener)
                }
            }
            self.listener = listener
            listener.start(queue: queue)
        } catch {
            listener = nil
        }
    }

    private func clear(_ failedListener: NWListener?) {
        lock.lock()
        defer { lock.unlock() }
        guard listener === failedListener else { return }
        listener = nil
    }

    private func handle(_ connection: NWConnection) {
        connection.start(queue: queue)
        connection.receive(
            minimumIncompleteLength: 1,
            maximumLength: 8_192
        ) { [weak self, weak connection] data, _, _, _ in
            guard let self, let connection else { return }
            guard
                let data,
                data.count <= 8_192,
                let request = String(data: data, encoding: .utf8),
                request.contains("\r\n\r\n"),
                let address = Self.requestedAddress(from: request)
            else {
                self.send(status: 400, body: Data(), over: connection)
                return
            }

            Task {
                guard let envelope = await self.publicationProvider(address) else {
                    self.send(status: 404, body: Data(), over: connection)
                    return
                }
                self.send(status: 200, body: envelope, over: connection)
            }
        }
    }

    static func requestedAddress(from request: String) -> String? {
        guard
            let firstLine = request.components(separatedBy: "\r\n").first
        else { return nil }
        let components = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard
            components.count == 3,
            components[0] == "GET",
            components[2] == "HTTP/1.1" || components[2] == "HTTP/1.0",
            let urlComponents = URLComponents(
                string: "http://127.0.0.1\(components[1])"
            ),
            urlComponents.path == "/v1/publication",
            let address = urlComponents.queryItems?
                .first(where: { $0.name == "address" })?
                .value,
            (1...512).contains(address.utf8.count),
            !address.unicodeScalars.contains(where: {
                CharacterSet.controlCharacters.contains($0)
            })
        else { return nil }
        return address
    }

    private func send(
        status: Int,
        body: Data,
        over connection: NWConnection
    ) {
        let response = Self.responseData(status: status, body: body)
        connection.send(
            content: response,
            contentContext: .defaultMessage,
            isComplete: true,
            completion: .contentProcessed { _ in connection.cancel() }
        )
    }

    static func responseData(status: Int, body: Data) -> Data {
        let reason: String
        switch status {
        case 200: reason = "OK"
        case 404: reason = "Not Found"
        default: reason = "Bad Request"
        }
        let contentType = status == 200
            ? "application/vnd.noctweave.noctweb-capsule"
            : "application/octet-stream"
        let headers = [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(body.count)",
            "Cache-Control: no-store",
            "Connection: close",
            "",
            "",
        ].joined(separator: "\r\n")
        var response = Data(headers.utf8)
        response.append(body)
        return response
    }
}
