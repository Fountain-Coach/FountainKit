import Foundation

public enum OpenAPICuratorKit {
    public static let defaultSubmitter: @Sendable (OpenAPI) -> Void = { _ in }

    public static func run(specs: [Spec],
                           rules: Rules = Rules(),
                           submit: Bool = false,
                           reviewer: ((OpenAPI, CuratorReport) -> Void)? = nil,
                           submitter: ((OpenAPI) -> Void)? = nil) -> (spec: OpenAPI, report: CuratorReport) {
        let result = curate(specs: specs, rules: rules)
        reviewer?(result.spec, result.report)
        if submit {
            let handler = submitter ?? defaultSubmitter
            handler(result.spec)
        }
        return result
    }
}

