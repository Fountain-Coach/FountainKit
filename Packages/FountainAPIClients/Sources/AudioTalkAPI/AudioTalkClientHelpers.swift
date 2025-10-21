import Foundation
import OpenAPIRuntime
import OpenAPIURLSession

public enum AudioTalkClientFactory {
    public static func make(baseURL: URL, session: URLSession = .shared) -> Client {
        let transport = URLSessionTransport(configuration: .init(session: session))
        return Client(serverURL: baseURL, transport: transport)
    }
}

