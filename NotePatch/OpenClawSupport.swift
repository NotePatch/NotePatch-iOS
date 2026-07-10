import Foundation

func extractOpenClawAnswer(_ resultText: String?) -> String {
    formatOpenClawTaskResult(resultText)
}

func formatOpenClawTaskResult(_ resultText: String?) -> String {
    let text = resultText?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
    guard !text.isEmpty, let data = text.data(using: .utf8) else {
        return ""
    }
    guard
        let object = try? JSONSerialization.jsonObject(with: data),
        let dictionary = object as? [String: Any]
    else {
        return text
    }

    if let answer = dictionary["answer"] as? String, !answer.isEmpty {
        return answer
    }

    var lines: [String] = []
    if let runner = dictionary["runner"] as? String, !runner.isEmpty {
        lines.append("runner: \(runner)")
    }
    if let outputKey = dictionary["output_key"] as? String, !outputKey.isEmpty {
        lines.append("output_key: \(outputKey)")
    }
    if let outputKeys = dictionary["output_keys"] as? [Any] {
        let keys = outputKeys.compactMap { $0 as? String }.filter { !$0.isEmpty }
        if !keys.isEmpty {
            lines.append("output_keys: \(keys.joined(separator: ", "))")
        }
    }
    return lines.joined(separator: "\n")
}
