import SwiftUI

struct LLMChatInstrument: View {
    @State private var systemPrompt: String = "You are a helpful assistant."
    @State private var userInput: String = "Summarize why PatchBay uses MIDI 2.0."
    @State private var response: String = ""
    @State private var isSending: Bool = false
    @State private var error: String?

    private var endpoint: URL {
        if let s = ProcessInfo.processInfo.environment["LLM_URL"], let u = URL(string: s) { return u }
        // Default to Gateway’s LLM endpoint
        return URL(string: "http://127.0.0.1:8010/chat")!
    }
    private var model: String { ProcessInfo.processInfo.environment["OPENAI_MODEL"] ?? "gpt-4o-mini" }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LLM Chat").font(.system(size: 12, weight: .semibold))
            TextField("System", text: $systemPrompt, axis: .vertical)
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
            TextField("Message", text: $userInput, axis: .vertical)
                .font(.system(size: 12))
                .textFieldStyle(.roundedBorder)
            HStack(spacing: 8) {
                Button(action: send) {
                    if isSending { ProgressView().scaleEffect(0.6) } else { Text("Send").font(.system(size: 11, weight: .medium)) }
                }.buttonStyle(.borderedProminent)
                Text(endpoint.absoluteString).font(.system(size: 10)).foregroundColor(.secondary)
            }
            if let error { Text(error).font(.system(size: 11)).foregroundColor(.red) }
            ScrollView {
                Text(response.isEmpty ? "Response will appear here." : response)
                    .font(.system(size: 12))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }.frame(minHeight: 80)
        }
    }

    private func send() {
        isSending = true; error = nil; response = ""
        let messages: [[String: String]] = [
            ["role": "system", "content": systemPrompt],
            ["role": "user", "content": userInput]
        ]
        let body: [String: Any] = ["model": model, "messages": messages]
        guard let data = try? JSONSerialization.data(withJSONObject: body) else { isSending = false; error = "serialize"; return }
        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.httpBody = data
        URLSession.shared.dataTask(with: req) { d, resp, err in
            Task { @MainActor in
                isSending = false
                if let err { error = err.localizedDescription; return }
                guard let d = d else { error = "no data"; return }
                // Try OpenAI-like shape first
                if let obj = try? JSONSerialization.jsonObject(with: d) as? [String: Any] {
                    if let choices = obj["choices"] as? [[String: Any]], let first = choices.first {
                        if let msg = first["message"] as? [String: Any], let content = msg["content"] as? String { response = content; return }
                        if let text = first["text"] as? String { response = text; return }
                    }
                    // Fallback: pretty-print raw JSON
                    if let pretty = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted]), let s = String(data: pretty, encoding: .utf8) { response = s; return }
                }
                response = String(data: d, encoding: .utf8) ?? "<binary>"
            }
        }.resume()
    }
}
