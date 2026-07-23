import Foundation
import Hummingbird
import HummingbirdWebSocket

struct EditorServerController: Sendable {
    let configuration: MMTMREditorServerConfiguration
    let provider: any ServerConfigurationProviding
    let assets: any ServerEditorAssetServing
    let security: EditorServerSecurity
    let events: EditorServerEventHub
    let preview: EditorPreviewStore
    let mutationRateLimiter: EditorMutationRateLimiter
    let webSocketLimiter: EditorWebSocketLimiter

    func buildHTTPRouter() -> Router<BasicRequestContext> {
        let router = Router(context: BasicRequestContext.self)

        router.get("/") { request, _ in
            guard security.allowsPublicAssetRequest(request) else {
                return forbiddenResponse()
            }
            let asset = assets.asset(at: "index.html") ?? Self.editorUnavailableAsset
            var response = assetResponse(asset, cacheControl: "no-store")
            response.headers[.setCookie] = security.cookie.description
            return response
        }

        router.get("/assets/:name") { request, context in
            guard security.allowsPublicAssetRequest(request) else {
                return forbiddenResponse()
            }
            guard let name = context.parameters.get("name"),
                  let asset = assets.asset(at: "assets/\(name)")
            else {
                return notFoundResponse()
            }
            return assetResponse(asset, cacheControl: "public, max-age=31536000, immutable")
        }

        router.get("/favicon.svg") { request, _ in
            guard security.allowsPublicAssetRequest(request) else {
                return forbiddenResponse()
            }
            guard let asset = assets.asset(at: "favicon.svg") else {
                return notFoundResponse()
            }
            return assetResponse(asset, cacheControl: "public, max-age=86400")
        }

        // The bundled editor receives this cookie from GET /. Keeping a tiny public
        // bootstrap route also lets the Vite development server establish the exact
        // same loopback-only session before it calls the authenticated API.
        router.get("/api/v1/session") { request, _ in
            guard security.allowsPublicAssetRequest(request) else {
                return forbiddenResponse()
            }
            var response = jsonResponse(SessionEnvelope(ok: true))
            response.headers[.setCookie] = security.cookie.description
            return response
        }

        router.get("/api/v1/status") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: false) else {
                return forbiddenResponse()
            }
            do {
                let snapshot = try await provider.configurationSnapshot()
                return jsonResponse(
                    StatusEnvelope(
                        version: configuration.appVersion,
                        port: configuration.port,
                        configPath: snapshot.configPath,
                        revision: snapshot.revision,
                        valid: snapshot.valid,
                        serverURL: configuration.serverURL.absoluteString
                    )
                )
            } catch {
                return await providerFailureResponse(error)
            }
        }

        router.get("/api/v1/schema") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: false) else {
                return forbiddenResponse()
            }
            do {
                return jsonResponse(try await provider.configurationSchema())
            } catch {
                return await providerFailureResponse(error)
            }
        }

        router.get("/api/v1/config") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: false) else {
                return forbiddenResponse()
            }
            do {
                let snapshot = try await provider.configurationSnapshot()
                var response = jsonResponse(ConfigurationEnvelope(snapshot: snapshot))
                response.headers[.eTag] = Self.eTag(for: snapshot.revision)
                return response
            } catch {
                return await providerFailureResponse(error)
            }
        }

        router.get("/api/v1/applications") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: false) else {
                return forbiddenResponse()
            }
            do {
                var response = jsonResponse(try await provider.applicationCatalog())
                response.headers[.cacheControl] = "no-store"
                return response
            } catch {
                return await providerFailureResponse(error)
            }
        }

        router.post("/api/v1/validate") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: true) else {
                return forbiddenResponse()
            }
            guard await mutationRateLimiter.allowRequest() else {
                return rateLimitedResponse()
            }
            guard acceptsJSON(request) else {
                return unsupportedMediaTypeResponse()
            }
            do {
                let body: SourceRequest = try await decodeBody(request, as: SourceRequest.self)
                let result = try await provider.validateConfiguration(source: body.source)
                return jsonResponse(ValidationEnvelope(result: result))
            } catch let error as EditorRequestBodyError {
                return bodyErrorResponse(error)
            } catch {
                return await providerFailureResponse(error)
            }
        }

        router.put("/api/v1/config") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: true) else {
                return forbiddenResponse()
            }
            guard await mutationRateLimiter.allowRequest() else {
                return rateLimitedResponse()
            }
            guard acceptsJSON(request) else {
                return unsupportedMediaTypeResponse()
            }
            guard let expectedRevision = Self.revision(fromIfMatch: request.headers[.ifMatch]) else {
                return jsonErrorResponse(
                    status: .badRequest,
                    code: "missing_or_invalid_if_match",
                    message: "If-Match must contain the quoted configuration revision."
                )
            }

            do {
                let body: SourceRequest = try await decodeBody(request, as: SourceRequest.self)
                switch try await provider.replaceConfiguration(source: body.source, expectedRevision: expectedRevision) {
                case .accepted(let snapshot):
                    let envelope = ConfigurationEnvelope(snapshot: snapshot)
                    let event = ServerEvent(
                        type: snapshot.valid ? .configChanged : .configInvalid,
                        revision: snapshot.revision,
                        payload: Self.jsonValue(envelope)
                    )
                    await events.publish(event)
                    var response = jsonResponse(envelope)
                    response.headers[.eTag] = Self.eTag(for: snapshot.revision)
                    return response

                case .conflict(let snapshot):
                    return jsonResponse(
                        ConflictEnvelope(
                            error: ErrorDescription(
                                code: "revision_conflict",
                                message: "The configuration changed since this draft was loaded."
                            ),
                            revision: snapshot.revision,
                            current: ConfigurationEnvelope(snapshot: snapshot)
                        ),
                        status: .conflict
                    )

                case .invalid(let validation):
                    return jsonResponse(ValidationEnvelope(result: validation), status: .unprocessableContent)
                }
            } catch let error as EditorRequestBodyError {
                return bodyErrorResponse(error)
            } catch {
                return await providerFailureResponse(error)
            }
        }

        router.post("/api/v1/preview/context") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: true) else {
                return forbiddenResponse()
            }
            guard await mutationRateLimiter.allowRequest() else {
                return rateLimitedResponse()
            }
            guard acceptsJSON(request) else {
                return unsupportedMediaTypeResponse()
            }
            do {
                let context: ServerJSONValue = try await decodeBody(request, as: ServerJSONValue.self)
                let storedContext = await preview.replace(with: context)
                let event = ServerEvent(
                    type: .simulationChanged,
                    payload: .object(["kind": .string("context"), "context": storedContext])
                )
                await events.publish(event)
                return jsonResponse(PreviewContextEnvelope(context: storedContext))
            } catch let error as EditorRequestBodyError {
                return bodyErrorResponse(error)
            } catch {
                return jsonErrorResponse(status: .badRequest, code: "invalid_json", message: "The preview context is not valid JSON.")
            }
        }

        router.post("/api/v1/preview/action") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: true) else {
                return forbiddenResponse()
            }
            guard await mutationRateLimiter.allowRequest() else {
                return rateLimitedResponse()
            }
            guard acceptsJSON(request) else {
                return unsupportedMediaTypeResponse()
            }
            do {
                let action: ServerJSONValue = try await decodeBody(request, as: ServerJSONValue.self)
                let description = Self.previewDescription(for: action)
                let event = ServerEvent(
                    type: .simulationChanged,
                    payload: .object([
                        "kind": .string("action"),
                        "request": action,
                        "executed": .bool(false),
                        "description": .string(description),
                    ])
                )
                await events.publish(event)
                return jsonResponse(PreviewActionEnvelope(executed: false, description: description, event: event))
            } catch let error as EditorRequestBodyError {
                return bodyErrorResponse(error)
            } catch {
                return jsonErrorResponse(status: .badRequest, code: "invalid_json", message: "The simulated action is not valid JSON.")
            }
        }

        router.post("/api/v1/touchbar/calibration") { request, _ in
            guard security.allowsAPIRequest(request, requiresOrigin: true) else {
                return forbiddenResponse()
            }
            guard await mutationRateLimiter.allowRequest() else {
                return rateLimitedResponse()
            }
            guard acceptsJSON(request) else {
                return unsupportedMediaTypeResponse()
            }
            do {
                let calibration: ServerTouchBarCalibrationRequest = try await decodeBody(
                    request,
                    as: ServerTouchBarCalibrationRequest.self
                )
                if let offset = calibration.centerOffset,
                   !offset.isFinite || offset < -300 || offset > 300 {
                    return jsonErrorResponse(
                        status: .unprocessableContent,
                        code: "invalid_center_offset",
                        message: "centerOffset must be from -300 through 300 points."
                    )
                }
                if let scale = calibration.pointsPerMillimeter,
                   !scale.isFinite || scale < 2 || scale > 8 {
                    return jsonErrorResponse(
                        status: .unprocessableContent,
                        code: "invalid_physical_scale",
                        message: "pointsPerMillimeter must be from 2 through 8."
                    )
                }
                let state = try await provider.updateTouchBarCalibration(calibration)
                return jsonResponse(TouchBarCalibrationEnvelope(state: state))
            } catch let error as EditorRequestBodyError {
                return bodyErrorResponse(error)
            } catch {
                return await providerFailureResponse(error)
            }
        }

        return router
    }

    func buildWebSocketRouter() -> Router<BasicWebSocketRequestContext> {
        let router = Router(context: BasicWebSocketRequestContext.self)
        router.ws(
            "/api/v1/events",
            shouldUpgrade: { request, _ in
                security.allowsWebSocketUpgrade(request) ? .upgrade([:]) : .dontUpgrade
            },
            onUpgrade: { inbound, outbound, _ in
                guard await webSocketLimiter.acquireConnection() else { return }
                do {
                    try await handleWebSocketConnection(inbound: inbound, outbound: outbound)
                    await webSocketLimiter.releaseConnection()
                } catch {
                    await webSocketLimiter.releaseConnection()
                    throw error
                }
            }
        )
        return router
    }

    private func handleWebSocketConnection(
        inbound: WebSocketInboundStream,
        outbound: WebSocketOutboundWriter
    ) async throws {
        let stream = await events.stream()

        do {
            let snapshot = try await provider.configurationSnapshot()
            let initial = ServerEvent(
                type: snapshot.valid ? .configChanged : .configInvalid,
                revision: snapshot.revision,
                payload: Self.jsonValue(ConfigurationEnvelope(snapshot: snapshot))
            )
            try await outbound.write(.text(Self.encodedEvent(initial)))
        } catch {
            let initial = ServerEvent(
                type: .serverError,
                payload: .object(["message": .string("The configuration service is unavailable.")])
            )
            try await outbound.write(.text(Self.encodedEvent(initial)))
        }

        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                for try await _ in inbound.messages(maxSize: configuration.bodyLimit) {
                    guard await webSocketLimiter.allowMessage() else {
                        throw EditorWebSocketLimitError.rateExceeded
                    }
                }
            }
            group.addTask {
                for await event in stream {
                    try Task.checkCancellation()
                    try await outbound.write(.text(Self.encodedEvent(event)))
                }
            }
            _ = try await group.next()
            group.cancelAll()
            try await group.waitForAll()
        }
    }

    private func decodeBody<Value: Decodable>(_ request: Request, as type: Value.Type) async throws -> Value {
        if let contentLength = request.headers[.contentLength].flatMap({ Int($0) }), contentLength > configuration.bodyLimit {
            throw EditorRequestBodyError.tooLarge
        }
        do {
            var data = Data()
            data.reserveCapacity(
                min(
                    request.headers[.contentLength].flatMap(Int.init) ?? 0,
                    configuration.bodyLimit
                )
            )
            for try await fragment in request.body {
                guard fragment.readableBytes <= configuration.bodyLimit - data.count else {
                    throw EditorRequestBodyError.tooLarge
                }
                data.append(contentsOf: fragment.readableBytesView)
            }
            do {
                return try JSONDecoder().decode(type, from: data)
            } catch {
                throw EditorRequestBodyError.malformedJSON
            }
        } catch let bodyError as EditorRequestBodyError {
            throw bodyError
        } catch {
            throw EditorRequestBodyError.unreadable
        }
    }

    private func acceptsJSON(_ request: Request) -> Bool {
        guard let contentType = request.headers[.contentType]?.lowercased() else { return false }
        return contentType == "application/json" || contentType.hasPrefix("application/json;")
    }

    private func providerFailureResponse(_ error: any Error) async -> Response {
        await events.publish(
            ServerEvent(
                type: .serverError,
                payload: .object(["message": .string(String(describing: error))])
            )
        )
        return jsonErrorResponse(
            status: .internalServerError,
            code: "configuration_service_unavailable",
            message: "The configuration service is unavailable."
        )
    }

    private func forbiddenResponse() -> Response {
        jsonErrorResponse(status: .forbidden, code: "forbidden", message: "This editor is available only to its local MMTMR session.")
    }

    private func unsupportedMediaTypeResponse() -> Response {
        jsonErrorResponse(status: .unsupportedMediaType, code: "unsupported_media_type", message: "Content-Type must be application/json.")
    }

    private func rateLimitedResponse() -> Response {
        jsonErrorResponse(status: .tooManyRequests, code: "rate_limited", message: "Too many editor mutations. Try again shortly.")
    }

    private func bodyErrorResponse(_ error: EditorRequestBodyError) -> Response {
        switch error {
        case .tooLarge:
            return jsonErrorResponse(status: .contentTooLarge, code: "body_too_large", message: "The request body exceeds the editor limit.")
        case .malformedJSON:
            return jsonErrorResponse(status: .badRequest, code: "invalid_json", message: "The request body is not valid JSON.")
        case .unreadable:
            return jsonErrorResponse(status: .badRequest, code: "unreadable_body", message: "The request body could not be read.")
        }
    }

    private func notFoundResponse() -> Response {
        jsonErrorResponse(status: .notFound, code: "not_found", message: "The requested editor asset does not exist.")
    }

    private func jsonErrorResponse(status: HTTPResponse.Status, code: String, message: String) -> Response {
        jsonResponse(ErrorEnvelope(error: ErrorDescription(code: code, message: message)), status: status)
    }

    private func jsonResponse<Value: Encodable>(_ value: Value, status: HTTPResponse.Status = .ok) -> Response {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes]
        guard let data = try? encoder.encode(value) else {
            let fallback = Data(#"{"error":{"code":"response_encoding_failed","message":"The server could not encode its response."}}"#.utf8)
            return response(
                data: fallback,
                contentType: "application/json; charset=utf-8",
                cacheControl: "no-store",
                status: .internalServerError
            )
        }
        return response(
            data: data,
            contentType: "application/json; charset=utf-8",
            cacheControl: "no-store",
            status: status
        )
    }

    private func assetResponse(_ asset: ServerEditorAsset, cacheControl: String) -> Response {
        response(data: asset.data, contentType: asset.contentType, cacheControl: cacheControl, status: .ok)
    }

    private func response(
        data: Data,
        contentType: String,
        cacheControl: String,
        status: HTTPResponse.Status
    ) -> Response {
        var headers: HTTPFields = [
            .contentType: contentType,
            .cacheControl: cacheControl,
            .contentSecurityPolicy: Self.contentSecurityPolicy(configuration: configuration),
            .xContentTypeOptions: "nosniff",
        ]
        headers[.contentLength] = String(data.count)
        return Response(status: status, headers: headers, body: .init(byteBuffer: ByteBuffer(bytes: data)))
    }

    private static func revision(fromIfMatch value: String?) -> Int? {
        guard var value else { return nil }
        value = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.hasPrefix("W/"), value != "*" else { return nil }
        if value.hasPrefix("\"") && value.hasSuffix("\"") && value.count >= 2 {
            value.removeFirst()
            value.removeLast()
        }
        guard let revision = Int(value), revision >= 0 else { return nil }
        return revision
    }

    private static func eTag(for revision: Int) -> String { "\"\(revision)\"" }

    private static func contentSecurityPolicy(configuration: MMTMREditorServerConfiguration) -> String {
        "default-src 'self'; base-uri 'none'; object-src 'none'; frame-ancestors 'none'; form-action 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; img-src 'self' data:; font-src 'self'; connect-src 'self' ws://\(MMTMREditorServerConfiguration.bindHost):\(configuration.port)"
    }

    private static func previewDescription(for action: ServerJSONValue) -> String {
        let object = action.objectValue
        let item = object?["itemID"]?.stringValue.map { "item \($0)" } ?? "the selected item"
        let trigger = object?["trigger"]?.stringValue.map { " via \($0)" } ?? ""
        guard let configured = object?["action"]?.objectValue,
              let actionType = configured["action"]?.stringValue else {
            return "No configured action was found for \(item)\(trigger). Nothing was executed."
        }

        let operation: String
        switch actionType {
        case "typeText":
            let text = configured["text"]?.stringValue ?? ""
            let preview = text.count > 60 ? String(text.prefix(60)) + "…" : text
            operation = "type the Unicode text “\(preview)”"
        case "keyPress", "hidKey":
            let keycode = configured["keycode"]?.numberValue.map { String(Int($0)) } ?? "?"
            operation = "send \(actionType) keycode \(keycode)"
        case "appleScript":
            operation = "run the configured AppleScript"
        case "shellScript":
            let executable = configured["executablePath"]?.stringValue ?? "the configured executable"
            operation = "launch \(executable)"
        case "openUrl":
            operation = "open \(configured["url"]?.stringValue ?? "the configured URL")"
        default:
            operation = "invoke action \(actionType)"
        }
        return "Would \(operation) for \(item)\(trigger). No system action was executed."
    }

    private static func jsonValue<Value: Encodable>(_ value: Value) -> ServerJSONValue {
        guard let data = try? JSONEncoder().encode(value),
              let json = try? JSONDecoder().decode(ServerJSONValue.self, from: data)
        else {
            return .null
        }
        return json
    }

    private static func encodedEvent(_ event: ServerEvent) -> String {
        guard let data = try? JSONEncoder().encode(event) else {
            return #"{"type":"server.error","payload":{"message":"Event encoding failed."},"timestamp":"1970-01-01T00:00:00Z"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private static let editorUnavailableAsset = ServerEditorAsset(
        data: Data(
            """
            <!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>MMTMR</title></head><body><main><h1>MMTMR editor unavailable</h1><p>The bundled Editor assets could not be loaded.</p></main></body></html>
            """.utf8
        ),
        contentType: "text/html; charset=utf-8"
    )
}

private enum EditorWebSocketLimitError: Error {
    case rateExceeded
}

private enum EditorRequestBodyError: Error {
    case tooLarge
    case malformedJSON
    case unreadable
}

private struct SourceRequest: Decodable {
    let source: String
}

private struct StatusEnvelope: Encodable {
    let version: String
    let port: Int
    let configPath: String
    let revision: Int
    let valid: Bool
    let serverURL: String
}

private struct ConfigurationEnvelope: Codable {
    let source: String
    let document: ServerJSONValue?
    let revision: Int
    let diagnostics: [ServerDiagnostic]
    let valid: Bool

    init(snapshot: ServerConfigurationSnapshot) {
        source = snapshot.source
        document = snapshot.document
        revision = snapshot.revision
        diagnostics = snapshot.diagnostics
        valid = snapshot.valid
    }
}

private struct ValidationEnvelope: Codable {
    let valid: Bool
    let document: ServerJSONValue?
    let diagnostics: [ServerDiagnostic]

    init(result: ServerValidationResult) {
        valid = result.valid
        document = result.document
        diagnostics = result.diagnostics
    }
}

private struct PreviewContextEnvelope: Encodable {
    let context: ServerJSONValue
}

private struct SessionEnvelope: Encodable {
    let ok: Bool
}

private struct PreviewActionEnvelope: Encodable {
    let executed: Bool
    let description: String
    let event: ServerEvent
}

private struct TouchBarCalibrationEnvelope: Encodable {
    let state: ServerTouchBarCalibrationState
}

private struct ErrorDescription: Codable {
    let code: String
    let message: String
}

private struct ErrorEnvelope: Encodable {
    let error: ErrorDescription
}

private struct ConflictEnvelope: Encodable {
    let error: ErrorDescription
    let revision: Int
    let current: ConfigurationEnvelope
}
