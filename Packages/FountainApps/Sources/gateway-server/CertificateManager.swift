import Foundation

/// Manages periodic execution of a certificate renewal script.
public final class CertificateManager {
    /// Dispatch timer scheduling periodic renewals.
    private var timer: DispatchSourceTimer?
    /// Absolute path to the renewal script executed.
    private let scriptPath: String
    /// Delay between script executions.
    private let interval: TimeInterval

    /// Creates a new manager with optional script path and repeat interval.
    /// - Parameters:
    ///   - scriptPath: Shell script used for renewal.
    ///   - interval: Time between renewals in seconds.
    public init(scriptPath: String = "./scripts/renew-certs.sh", interval: TimeInterval = 86_400) {
        self.scriptPath = scriptPath
        self.interval = interval
    }

    /// Starts automatic certificate renewal on a timer.
    /// Invokes the configured shell script every ``interval`` seconds on a
    /// background queue until ``stop()`` is called.
    public func start() {
        let env = ProcessInfo.processInfo.environment
        if (env["GATEWAY_ENABLE_CERT_RENEWAL"] ?? "1") == "0" {
            print("[gateway] Certificate renewal disabled by GATEWAY_ENABLE_CERT_RENEWAL=0")
            return
        }

        // Resolve script path from env override or provided default. Try common fallback too.
        let candidate = env["GATEWAY_CERT_RENEW_SCRIPT"] ?? scriptPath
        let fallback = "./Scripts/renew-certs.sh"
        let fm = FileManager.default
        let resolved: String
        if fm.isExecutableFile(atPath: candidate) {
            resolved = candidate
        } else if fm.isExecutableFile(atPath: fallback) {
            resolved = fallback
        } else {
            print("[gateway] Certificate renewal script not found or not executable; skipping (tried: \(candidate), \(fallback))")
            return
        }

        let timer = DispatchSource.makeTimerSource()
        // Schedule first run after the interval to avoid immediate noise on startup.
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler {
            let task = Process()
            task.executableURL = URL(fileURLWithPath: resolved)
            do { try task.run() } catch {
                // Log once per failure without spamming
                print("[gateway] Certificate renewal failed: \(error)")
            }
        }
        self.timer = timer
        timer.resume()
    }

    /// Stops the timer and cancels future renewals.
    /// Safe to call multiple times; subsequent calls have no effect.
    public func stop() {
        timer?.cancel()
        timer = nil
    }

    /// Immediately runs the renewal script once outside the normal schedule.
    /// Any error is printed to standard output.
    public func triggerNow() {
        let env = ProcessInfo.processInfo.environment
        if (env["GATEWAY_ENABLE_CERT_RENEWAL"] ?? "1") == "0" { return }
        let candidate = env["GATEWAY_CERT_RENEW_SCRIPT"] ?? scriptPath
        let fallback = "./Scripts/renew-certs.sh"
        let fm = FileManager.default
        guard fm.isExecutableFile(atPath: candidate) || fm.isExecutableFile(atPath: fallback) else { return }
        let resolved = fm.isExecutableFile(atPath: candidate) ? candidate : fallback
        let task = Process()
        task.executableURL = URL(fileURLWithPath: resolved)
        try? task.run()
    }
}

// © 2025 Contexter alias Benedikt Eickhoff 🛡️ All rights reserved.
