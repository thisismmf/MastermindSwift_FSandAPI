import Foundation

struct MastermindGame {
    let codeLength: Int = 4
    let digitRange: ClosedRange<Int> = 1...6
    let allowDuplicates: Bool = true

    private(set) var secret: [Int]
    private(set) var attempts: Int = 0

    init(seed: UInt64? = nil) {
        let len = codeLength
        let range = digitRange

        if let seed = seed {
            var generator = SeededGenerator(seed: seed)
            var arr = [Int]()
            arr.reserveCapacity(len)
            for _ in 0..<len {
                arr.append(Int.random(in: range, using: &generator))
            }
            self.secret = arr
        } else {
            var arr = [Int]()
            arr.reserveCapacity(len)
            for _ in 0..<len {
                arr.append(Int.random(in: range))
            }
            self.secret = arr
        }
    }

    func evaluate(guess: [Int]) -> (black: Int, white: Int) {
        precondition(guess.count == codeLength, "Guess length must be \(codeLength)")
        var black = 0
        var secretUnused: [Int] = []
        var guessUnused: [Int] = []
        for (g, s) in zip(guess, secret) {
            if g == s { black += 1 } else {
                secretUnused.append(s)
                guessUnused.append(g)
            }
        }
        var white = 0
        if !guessUnused.isEmpty {
            var freq: [Int:Int] = [:]
            for s in secretUnused { freq[s, default: 0] += 1 }
            for g in guessUnused {
                if let f = freq[g], f > 0 {
                    white += 1
                    freq[g] = f - 1
                }
            }
        }
        return (black, white)
    }

    mutating func take(guess: [Int]) -> (black: Int, white: Int) {
        attempts += 1
        return evaluate(guess: guess)
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 0xDEADBEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state >> 12
        state ^= state << 25
        state ^= state >> 27
        return state &* 2685821657736338717
    }
}

enum GameError: Error, CustomStringConvertible {
    case invalidGuessLength(expected: Int)
    case invalidCharacters
    case outOfRange(allowed: ClosedRange<Int>)

    var description: String {
        switch self {
        case .invalidGuessLength(let expected):
            return "Input length must be exactly \(expected) digits."
        case .invalidCharacters:
            return "Input must only contain digits (e.g., 1234)."
        case .outOfRange(let allowed):
            return "Each digit must be between \(allowed.lowerBound) and \(allowed.upperBound)."
        }
    }
}

func parseGuess(_ line: String, codeLength: Int, allowed: ClosedRange<Int>) throws -> [Int] {
    let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { throw GameError.invalidGuessLength(expected: codeLength) }
    let digitsOnly = trimmed.replacingOccurrences(of: " ", with: "")
    guard digitsOnly.count == codeLength else { throw GameError.invalidGuessLength(expected: codeLength) }
    guard CharacterSet.decimalDigits.isSuperset(of: CharacterSet(charactersIn: digitsOnly)) else {
        throw GameError.invalidCharacters
    }
    let nums = digitsOnly.compactMap { Int(String($0)) }
    for n in nums { if !(allowed.contains(n)) { throw GameError.outOfRange(allowed: allowed) } }
    return nums
}

func feedbackString(black: Int, white: Int) -> String {
    let b = String(repeating: "B", count: black)
    let w = String(repeating: "W", count: white)
    let s = "\(b)\(w)"
    return s.isEmpty ? "-" : s
}

struct CLIOptions {
    enum Mode: String { case local, api }
    var seed: UInt64?
    var cheat: Bool = false
    var maxAttempts: Int? = nil
    var mode: Mode = .local
    var baseURL: URL = URL(string: "https://mastermind.darkube.app")!
    var apiKey: String? = nil
    var verbose: Bool = false
    var autodelete: Bool = false
}

func parseCLIArguments() -> CLIOptions {
    var opts = CLIOptions()
    var it = CommandLine.arguments.dropFirst().makeIterator()
    while let arg = it.next() {
        switch arg {
        case "--seed":
            if let s = it.next(), let v = UInt64(s) { opts.seed = v }
        case "--cheat":
            opts.cheat = true
        case "--max":
            if let m = it.next(), let v = Int(m), v > 0 { opts.maxAttempts = v }
        case "--mode":
            if let m = it.next(), let mode = CLIOptions.Mode(rawValue: m.lowercased()) { opts.mode = mode }
        case "--base":
            if let b = it.next(), let u = URL(string: b) { opts.baseURL = u }
        case "--apikey":
            if let k = it.next() { opts.apiKey = k }
        case "--verbose", "-v":
            opts.verbose = true
        case "--autodelete":
            opts.autodelete = true
        case "--help", "-h":
            printHelpAndExit()
        default:
            continue
        }
    }
    if let env = ProcessInfo.processInfo.environment["MM_BASE_URL"], let u = URL(string: env) {
        opts.baseURL = u
    }
    if let k = ProcessInfo.processInfo.environment["MM_API_KEY"] {
        opts.apiKey = k
    }
    return opts
}

func printHelpAndExit() -> Never {
    let help = """
    Mastermind (Terminal) — Swift

    Usage:
      mastermind [--mode local|api] [--seed <n>] [--cheat] [--max <attempts>] [--base <url>] [--apikey <token>] [--autodelete] [-v]

    Options:
      --mode <m>      Run in local or api mode. Default: local
      --seed <n>      Generate code with a fixed seed (local mode only).
      --cheat         Display the secret code (local mode only).
      --max <k>       Limit the number of attempts to k.
      --base <url>    API server base URL (Default: https://mastermind.darkube.app).
      --apikey <t>    API key, if required.
      --autodelete    DELETE /game/{gameID} after the game ends.
      -v, --verbose   Enable verbose logging.
      -h, --help      Show this help message.

    Rules:
      • You must guess a 4-digit code with digits from 1-6.
      • Feedback includes B and W: B=correct digit in correct position, W=correct digit in wrong position.
      • Type 'exit' at any time to quit.
    """
    print(help)
    exit(0)
}

actor APIClient {
    struct CreateGameResponse: Decodable {
        let gameID: String?
        let gameId: String?
        let id: String?
        let game_id: String?
    }

    struct GuessResponse: Decodable {
        let black: Int?
        let white: Int?
        let result: String?
        let status: String?
        let error: String?
    }

    enum APIError: Error, CustomStringConvertible {
        case invalidResponse
        case http(Int, String)
        case decode(Error)
        case network(Error)

        var description: String {
            switch self {
            case .invalidResponse: return "Invalid response from server."
            case .http(let code, let body): return "HTTP Error \(code): \(body)"
            case .decode(let e): return "Decode Error: \(e)"
            case .network(let e): return "Network Error: \(e.localizedDescription)"
            }
        }
    }

    let base: URL
    let apiKey: String?
    let verbose: Bool
    let session: URLSession

    init(base: URL, apiKey: String?, verbose: Bool) {
        self.base = base
        self.apiKey = apiKey
        self.verbose = verbose
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 30
        self.session = URLSession(configuration: config)
    }

    func log(_ s: String) {
        if verbose { print(" [API] \(s)") }
    }

    func requestRaw(path: String, method: String, body: Data?) async throws -> (Data, HTTPURLResponse) {
        var url = base
        let cleaned = path.hasPrefix("/") ? String(path.dropFirst()) : path
        url.appendPathComponent(cleaned)
        var req = URLRequest(url: url)
        req.httpMethod = method
        if let body = body {
            req.setValue("application/json", forHTTPHeaderField: "Content-Type")
            req.httpBody = body
        }
        if let key = apiKey, !key.isEmpty {
            req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization")
            req.setValue(key, forHTTPHeaderField: "X-API-Key")
        }
        log("\(method) \(url.absoluteString) body=\(body.flatMap { String(data: $0, encoding: .utf8) } ?? "<none>")")
        do {
            let (respData, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse else { throw APIError.invalidResponse }
            if !(200...299).contains(http.statusCode) {
                let text = String(data: respData, encoding: .utf8) ?? ""
                log("HTTP \(http.statusCode) body=\(text)")
                throw APIError.http(http.statusCode, text)
            }
            log("HTTP \(http.statusCode) OK")
            return (respData, http)
        } catch {
            throw APIError.network(error)
        }
    }

    func createGame() async throws -> String {
        let empty = try JSONSerialization.data(withJSONObject: [:], options: [])
        let (data, _) = try await requestRaw(path: "/game", method: "POST", body: empty)
        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        if let obj = try? dec.decode(CreateGameResponse.self, from: data) {
            if let gid = obj.gameID ?? obj.gameId ?? obj.id {
                return gid
            }
        }
        if let any = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = any as? [String: Any] {
            if let gid = dict["game_id"] as? String ?? dict["gameId"] as? String ?? dict["gameID"] as? String ?? dict["id"] as? String {
                return gid
            }
        }
        if let text = String(data: data, encoding: .utf8), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return text.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        throw APIError.invalidResponse
    }

    func deleteGame(gameID: String) async {
        do {
            _ = try await requestRaw(path: "/game/\(gameID)", method: "DELETE", body: nil)
            log("DELETE /game/\(gameID) OK")
        } catch {
            log("DELETE /game/\(gameID) failed: \(error)")
        }
    }

    func submitGuess(gameID: String, guess: String) async throws -> (black: Int, white: Int, status: String?) {
        let payload: [String: Any] = ["guess": guess, "game_id": gameID, "gameId": gameID, "gameID": gameID]
        let body = try JSONSerialization.data(withJSONObject: payload, options: [])
        let (data, _) = try await requestRaw(path: "/guess", method: "POST", body: body)

        let dec = JSONDecoder()
        dec.keyDecodingStrategy = .convertFromSnakeCase
        if let r = try? dec.decode(GuessResponse.self, from: data) {
            if let err = r.error, !err.isEmpty {
                throw APIError.http(400, err)
            }
            if let b = r.black, let w = r.white { return (b, w, r.status) }
            if let res = r.result {
                let b = res.filter { $0 == "B" }.count
                let w = res.filter { $0 == "W" }.count
                return (b, w, r.status)
            }
        }
        if let any = try? JSONSerialization.jsonObject(with: data, options: []),
           let dict = any as? [String: Any] {
            if let err = dict["error"] as? String, !err.isEmpty {
                throw APIError.http(400, err)
            }
            if let b = dict["black"] as? Int, let w = dict["white"] as? Int {
                return (b, w, dict["status"] as? String)
            }
            if let res = dict["result"] as? String {
                let b = res.filter { $0 == "B" }.count
                let w = res.filter { $0 == "W" }.count
                return (b, w, dict["status"] as? String)
            }
        }
        let text = String(data: data, encoding: .utf8) ?? ""
        if !text.isEmpty {
            let b = text.filter { $0 == "B" }.count
            let w = text.filter { $0 == "W" }.count
            return (b, w, nil)
        }
        throw APIError.invalidResponse
    }
}

@main
struct Main {
    static func main() async {
        let opts = parseCLIArguments()

        print(" Mastermind — Terminal Version (Swift)")
        print("— — — — — — — — — — — — — — — — — — —")
        print("Rules: Guess the 4-digit code with digits from 1 to 6. You get B/W feedback after each guess.")
        print("Type 'exit' to quit at any time. For help, use --help")
        if let max = opts.maxAttempts { print("Number of attempts is limited to \(max).") }

        switch opts.mode {
        case .local:
            await runLocal(opts: opts)
        case .api:
            await runAPI(opts: opts)
        }
    }

    static func runLocal(opts: CLIOptions) async {
        var game = MastermindGame(seed: opts.seed)
        if opts.cheat { print(" Secret (for testing only): \(game.secret.map(String.init).joined())") }
        while true {
            if let max = opts.maxAttempts, game.attempts >= max {
                print(" You have reached the maximum number of attempts.")
                break
            }
            print("\nEnter your guess (4 digits, 1-6) >", terminator: " ")
            guard let line = readLine() else {
                print("Invalid input. Type 'exit' to quit."); continue
            }
            if line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "exit" {
                print("Exiting the game. Goodbye! "); break
            }
            do {
                let guess = try parseGuess(line, codeLength: game.codeLength, allowed: game.digitRange)
                let (b, w) = game.take(guess: guess)
                let fb = feedbackString(black: b, white: w)
                print("Result: \(fb)   [B=\(b), W=\(w)]   Attempt #\(game.attempts)")
                if b == game.codeLength { print(" Congratulations! You found the code."); break }
            } catch let err as GameError {
                print(" Error: \(err.description) (Type 'exit' to quit)")
            } catch {
                print(" An unknown error occurred. Please try again.")
            }
        }
    }

    static func runAPI(opts: CLIOptions) async {
        let api = APIClient(base: opts.baseURL, apiKey: opts.apiKey, verbose: opts.verbose)
        print(" API Mode — Server: \(opts.baseURL.absoluteString)")
        var createdID: String? = nil
        do {
            let gameId = try await api.createGame()
            createdID = gameId
            print(" Game created: \(gameId)")
            var attempts = 0
            while true {
                if let max = opts.maxAttempts, attempts >= max {
                    print(" You have reached the maximum number of attempts.")
                    break
                }
                print("\nEnter your guess (4 digits, 1-6) >", terminator: " ")
                guard let line = readLine() else {
                    print("Invalid input. Type 'exit' to quit."); continue
                }
                if line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() == "exit" {
                    print("Exiting the game. Goodbye! "); break
                }
                do {
                    let guessArray = try parseGuess(line, codeLength: 4, allowed: 1...6)
                    if Set(guessArray).count != guessArray.count {
                        print(" This API requires unique digits (duplicates are not allowed). Please enter a different guess.")
                        continue
                    }
                    let guessStr = guessArray.map(String.init).joined()
                    attempts += 1
                    let (b, w, status) = try await api.submitGuess(gameID: gameId, guess: guessStr)
                    let fb = feedbackString(black: b, white: w)
                    print("Result: \(fb)   [B=\(b), W=\(w)]   Attempt #\(attempts)")
                    if b == 4 || status?.lowercased() == "win" || status?.lowercased() == "won" {
                        print(" Congratulations! You found the code."); break
                    }
                } catch let e as APIClient.APIError {
                    print(" API Error: \(e.description)")
                } catch let err as GameError {
                    print(" Error: \(err.description)")
                } catch {
                    print(" An unknown error occurred.")
                }
            }
        } catch let e as APIClient.APIError {
            print(" Failed to create game: \(e.description)")
        } catch {
            print(" Error starting API mode: \(error.localizedDescription)")
        }

        if let gid = createdID, opts.autodelete {
            await api.deleteGame(gameID: gid)
        }
    }
}

