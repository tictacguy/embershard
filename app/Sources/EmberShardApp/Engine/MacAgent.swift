import Foundation

// The reasoning protocol behind the macOS Helper. The model sees the tool menu
// plus when-to-use guidance, and replies with ONE line: either an ACTION (a tool
// call as JSON) or a FINAL answer. The loop runs read-only tools immediately and
// feeds results back; mutating tools are previewed for the user first. Kept very
// explicit so small local models can follow it.
enum MacAgent {
    struct Args {
        var query = "", path = "", source = "", destination = "", name = ""
        var days: Int? = nil
    }
    enum Step { case action(MacToolID, Args); case final(String) }

    static func system() -> String {
        let tools = MacTool.all.map { "• \($0.id.rawValue): \($0.modelDesc)" }.joined(separator: "\n")
        return """
        You are macOS Helper: a careful assistant that operates the user's Mac through tools.
        On each turn reply with EXACTLY ONE line, in one of these two forms:

        ACTION {"tool":"<id>", ...args}
        FINAL <a short message to the user>

        Use ACTION to run a tool. Use FINAL when the task is done or no tool is needed
        (greetings, questions, after you've reported results).

        Tools (pick the single best one):
        \(tools)

        Argument keys by tool: findFiles→query[,path]; largestFiles/folderSizes/findDuplicates→path;
        recentFiles→path,days; tidyFolder/organizeByDate→path; cleanOldDownloads→days;
        moveItem→source,destination; createFolder→path; quitApp→name. Others take none.
        Use absolute paths (you may use ~ for home). Never invent files — discover them with a tool first.
        Run as FEW tools as possible — usually exactly one. Never repeat a tool you already ran.
        As soon as you have what the user asked for, reply FINAL with a short summary.

        Examples:
        User: clean up my desktop
        ACTION {"tool":"tidyDesktop"}
        User: find my tax pdf
        ACTION {"tool":"findFiles","query":"tax"}
        User: move report.pdf to ~/Documents/Work
        ACTION {"tool":"moveItem","source":"~/Desktop/report.pdf","destination":"~/Documents/Work"}
        User: what's eating my disk?
        ACTION {"tool":"folderSizes","path":"~"}
        User: thanks!
        FINAL You're welcome!
        """
    }

    private static func toolMenu() -> String {
        let tools = MacTool.all.map { "• \($0.id.rawValue): \($0.modelDesc)" }.joined(separator: "\n")
        return tools + """

        Argument keys by tool: findFiles→query[,path]; largestFiles/folderSizes/findDuplicates/tidyFolder/organizeByDate→path;
        recentFiles→path,days; cleanOldDownloads→days; moveItem→source,destination; createFolder→path; quitApp→name. Others take none.
        Use absolute paths (~ allowed).
        """
    }

    // Resolve: pick exactly one tool (or none) for the request. One call per turn.
    static func resolveSystem() -> String {
        """
        You are Pomme, a macOS assistant. Choose the SINGLE best tool to fulfil the user's
        request, or reply {"tool":"none"} for a greeting, a general question, or anything no
        tool covers. Reply with ONLY a JSON object on one line: {"tool":"<id>", ...args}
        If a file or folder is attached, use its path for the relevant argument.
        Tools:
        \(toolMenu())
        """
    }

    // Short conversational reply when no tool is needed.
    static func chatSystem() -> String {
        "You are Pomme, a friendly macOS helper. Answer in 1–3 short sentences. "
        + "If the user wants a file operation, tell them to describe it and you'll preview it. "
        + "Wrap any shell commands in ```bash fences."
    }

    // Step 3 — verify the result/plan actually answers the request.
    static func verifySystem() -> String {
        """
        You verify whether the action's result correctly fulfils the user's request.
        Reply with YES or NO on the first line, then a one-line reason. Be strict but fair.
        """
    }

    // Step 5 — write the short user-facing reply from the gathered result.
    static func answerSystem() -> String {
        """
        You are macOS Helper. Using the result provided, write a short, friendly reply to
        the user (1–3 sentences). Use Markdown; wrap any shell commands in ```bash fences.
        Do not mention tools, plans, or internal steps.
        """
    }

    static func plannerSystem() -> String {
        let names = MacTool.all.map { $0.id.rawValue }.joined(separator: ", ")
        return """
        You are macOS Helper. Before doing anything, briefly plan your approach in 1–3
        short numbered steps, naming which tool(s) you'll use. Do NOT call tools yet and
        do not output JSON — just the plan. Available tools: \(names).
        """
    }

    // First balanced {...} object — tolerant of prose or junk around/after it.
    private static func firstJSONObject(_ text: String) -> String? {
        guard let open = text.firstIndex(of: "{") else { return nil }
        var depth = 0, inString = false, escaped = false
        var i = open
        while i < text.endIndex {
            let c = text[i]
            if escaped { escaped = false }
            else if c == "\\" { escaped = true }
            else if c == "\"" { inString.toggle() }
            else if !inString && c == "{" { depth += 1 }
            else if !inString && c == "}" { depth -= 1; if depth == 0 { return String(text[open...i]) } }
            i = text.index(after: i)
        }
        return nil
    }

    static func parse(_ raw: String) -> Step {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Prefer an explicit FINAL unless a JSON action is clearly present.
        let hasJSON = text.firstIndex(of: "{") != nil
        if let r = text.range(of: "FINAL"), !hasJSON || text.distance(from: text.startIndex, to: r.lowerBound) == 0 {
            let msg = String(text[r.upperBound...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return .final(msg.isEmpty ? text : msg)
        }
        guard let json = firstJSONObject(text),
              let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let toolStr = obj["tool"] as? String,
              let tool = MacToolID(rawValue: toolStr) else {
            // Model ignored the protocol — treat its prose as the final answer.
            return .final(text)
        }
        var a = Args()
        a.query = obj["query"] as? String ?? ""
        a.path = obj["path"] as? String ?? ""
        a.source = obj["source"] as? String ?? ""
        a.destination = obj["destination"] as? String ?? ""
        a.name = obj["name"] as? String ?? ""
        if let d = obj["days"] as? Int { a.days = d }
        else if let ds = obj["days"] as? String { a.days = Int(ds) }
        return .action(tool, a)
    }
}
