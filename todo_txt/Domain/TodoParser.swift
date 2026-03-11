import Foundation

enum TodoParseError: Error, LocalizedError {
    case emptyLine
    case invalidCompletedPrefix
    case invalidDate
    case invalidPriority
    case invalidFormat

    var errorDescription: String? {
        switch self {
        case .emptyLine: return "Empty line"
        case .invalidCompletedPrefix: return "Completed tasks must start with 'x '"
        case .invalidDate: return "Invalid YYYY-MM-DD date"
        case .invalidPriority: return "Priority must be (A)-(Z) and appear first"
        case .invalidFormat: return "Line does not match todo.txt strict format"
        }
    }
}

struct TodoParser {
    static let posix = Locale(identifier: "en_US_POSIX")
    static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = posix
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter
    }()

    private static let completedRegex = try! NSRegularExpression(
        pattern: #"^x (\d{4}-\d{2}-\d{2})(?: (\d{4}-\d{2}-\d{2}))? (.+)$"#
    )
    private static let incompleteRegex = try! NSRegularExpression(
        pattern: #"^(?:\(([A-Z])\) )?(?:(\d{4}-\d{2}-\d{2}) )?(.+)$"#
    )

    static func parse(line: String) throws -> TodoTask {
        let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { throw TodoParseError.emptyLine }

        if trimmed.hasPrefix("x ") {
            guard let match = completedRegex.firstMatch(
                in: trimmed,
                range: NSRange(location: 0, length: trimmed.utf16.count)
            ) else {
                throw TodoParseError.invalidCompletedPrefix
            }

            let completionDate = try date(from: trimmed, match: match, at: 1)
            let creationDate = try dateOptional(from: trimmed, match: match, at: 2)
            let rest = substring(trimmed, match.range(at: 3))
            let (base, projects, contexts, extras) = splitRest(rest)

            return TodoTask(
                completed: true,
                completionDate: completionDate,
                priority: nil,
                creationDate: creationDate,
                baseDescription: base,
                projects: projects,
                contexts: contexts,
                extras: extras
            )
        }

        guard let match = incompleteRegex.firstMatch(
            in: trimmed,
            range: NSRange(location: 0, length: trimmed.utf16.count)
        ) else {
            throw TodoParseError.invalidFormat
        }

        let priority = substringOptional(trimmed, match.range(at: 1))?.first
        let creationDate = try dateOptional(from: trimmed, match: match, at: 2)
        let rest = substring(trimmed, match.range(at: 3))
        let (base, projects, contexts, extras) = splitRest(rest)

        return TodoTask(
            completed: false,
            completionDate: nil,
            priority: priority,
            creationDate: creationDate,
            baseDescription: base,
            projects: projects,
            contexts: contexts,
            extras: extras
        )
    }

    static func serialize(_ task: TodoTask) -> String {
        var parts: [String] = []

        if task.completed {
            parts.append("x")
            parts.append(dateFormatter.string(from: task.completionDate ?? Date()))
            if let creationDate = task.creationDate {
                parts.append(dateFormatter.string(from: creationDate))
            }
        } else {
            if let priority = task.priority {
                parts.append("(\(priority))")
            }
            if let creationDate = task.creationDate {
                parts.append(dateFormatter.string(from: creationDate))
            }
        }

        parts.append(restString(task))
        return parts.joined(separator: " ")
    }

    static func restString(_ task: TodoTask) -> String {
        var output = task.baseDescription

        if !task.projects.isEmpty {
            output += " " + task.projects.map { "+\($0)" }.joined(separator: " ")
        }
        if !task.contexts.isEmpty {
            output += " " + task.contexts.map { "@\($0)" }.joined(separator: " ")
        }
        if !task.extras.isEmpty {
            output += " " + task.extras.sorted { $0.key < $1.key }
                .map { "\($0.key):\($0.value)" }
                .joined(separator: " ")
        }

        return output
    }

    static func parseRest(_ rest: String) -> (String, [String], [String], [String: String]) {
        splitRest(rest)
    }

    private static func splitRest(_ rest: String) -> (String, [String], [String], [String: String]) {
        var baseTokens: [String] = []
        var projects: [String] = []
        var contexts: [String] = []
        var extras: [String: String] = [:]

        for token in rest.split(separator: " ") {
            if token.hasPrefix("+"), token.count > 1 {
                projects.append(String(token.dropFirst()))
            } else if token.hasPrefix("@"), token.count > 1 {
                contexts.append(String(token.dropFirst()))
            } else if let colon = token.firstIndex(of: ":"),
                      colon != token.startIndex,
                      colon != token.index(before: token.endIndex) {
                let key = String(token[..<colon])
                let value = String(token[token.index(after: colon)...])
                if !key.isEmpty, !value.isEmpty, !key.contains(":"), !value.contains(":") {
                    extras[key] = value
                } else {
                    baseTokens.append(String(token))
                }
            } else {
                baseTokens.append(String(token))
            }
        }

        return (baseTokens.joined(separator: " "), projects, contexts, extras)
    }

    private static func date(from source: String, match: NSTextCheckingResult, at index: Int) throws -> Date {
        let value = substring(source, match.range(at: index))
        guard let date = dateFormatter.date(from: value) else {
            throw TodoParseError.invalidDate
        }
        return date
    }

    private static func dateOptional(from source: String, match: NSTextCheckingResult, at index: Int) throws -> Date? {
        let value = substringOptional(source, match.range(at: index))
        if let value, let date = dateFormatter.date(from: value) {
            return date
        }
        if value == nil {
            return nil
        }
        throw TodoParseError.invalidDate
    }

    private static func substring(_ source: String, _ range: NSRange) -> String {
        guard let range = Range(range, in: source) else { return "" }
        return String(source[range])
    }

    private static func substringOptional(_ source: String, _ range: NSRange) -> String? {
        if range.location == NSNotFound {
            return nil
        }
        guard let range = Range(range, in: source) else {
            return nil
        }
        return String(source[range])
    }
}
