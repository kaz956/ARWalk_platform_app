import Foundation

struct TextEntryTaskConfig {
    var displayDuration: Double = 9999.0
    var interPromptInterval: Double = 1.0
}

struct TextEntryPrompt: Identifiable {
    let id: UUID
    let targetText: String
    let enteredText: String
    let options: [String]
    let spawnedAt: Date
    let expiresAt: Date
}

/// 指定文字列をボタン入力で完成させるタスク
final class TextEntryTaskManager: ObservableObject, ExperimentalSubTask {
    @Published private(set) var currentPrompt: TextEntryPrompt?
    @Published private(set) var lastResult: Bool?
    @Published private(set) var isReadyToSubmit: Bool = false

    private let prompts = [
        "ABOUT", "ABOVE", "ACCEPT", "ACTION", "ACTIVE", "ACTUAL", "ADD", "ADDRESS", "ADMIT", "ADULT", "ADVICE", "AFFORD", "AFTER", "AGAIN", "AGAINST", "AGE", "AGREE", "AHEAD", "AIR", "ALLOW",
        "BABY", "BACK", "BAD", "BAG", "BALANCE", "BALL", "BAND", "BANK", "BAR", "BASE", "BASIC", "BATTLE", "BEACH", "BEAR", "BEAUTY", "BECAUSE", "BECOME", "BED", "BEFORE", "BEGIN",
        "CABIN", "CALL", "CAMERA", "CAMP", "CAN", "CANCEL", "CANDLE", "CAPITAL", "CAR", "CARD", "CARE", "CARRY", "CASE", "CAST", "CAT", "CATCH", "CAUSE", "CELL", "CENTER", "CHAIN",
        "DAILY", "DANCE", "DANGER", "DARK", "DATA", "DATE", "DAUGHTER", "DAY", "DEAD", "DEAL", "DEAR", "DEBATE", "DECIDE", "DEEP", "DEGREE", "DELAY", "DEMAND", "DEPTH", "DESK", "DETAIL",
        "EACH", "EAR", "EARLY", "EARTH", "EASE", "EAST", "EASY", "EAT", "EDGE", "EDITOR", "EFFECT", "EFFORT", "EGG", "EIGHT", "EITHER", "ELBOW", "ELITE", "ELSE", "EMPTY", "END",
        "FACE", "FACT", "FACTORY", "FAIL", "FAIR", "FALL", "FAMILY", "FAMOUS", "FAR", "FARM", "FAST", "FATHER", "FAULT", "FEAR", "FEED", "FEEL", "FELLOW", "FEMALE", "FEW", "FIELD",
        "GAIN", "GAME", "GAP", "GARDEN", "GAS", "GATE", "GATHER", "GEAR", "GENERAL", "GENTLE", "GIFT", "GIRL", "GIVE", "GLAD", "GLASS", "GLOBAL", "GOAL", "GOAT", "GOLD", "GOOD",
        "HABIT", "HAIR", "HALF", "HALL", "HAND", "HANG", "HAPPY", "HARBOR", "HARD", "HAT", "HAVE", "HEAD", "HEAL", "HEAR", "HEART", "HEAT", "HEAVY", "HEIGHT", "HELLO", "HELP",
        "ICE", "IDEA", "IDEAL", "IDENTITY", "IMAGE", "IMPACT", "IMPORT", "INCH", "INCOME", "INDEED", "INDEX", "INDUSTRY", "INFANT", "INK", "INPUT", "INSECT", "INSIDE", "INTENT", "INVENT", "IRON",
        "JACKET", "JAIL", "JAM", "JAR", "JAW", "JAZZ", "JEANS", "JELLY", "JOB", "JOIN", "JOINT", "JOKE", "JOURNAL", "JOURNEY", "JOY", "JUDGE", "JUICE", "JUMP", "JUNGLE", "JURY",
        "KEEP", "KETTLE", "KEY", "KEYBOARD", "KICK", "KID", "KILOGRAM", "KILOMETER", "KIND", "KING", "KITCHEN", "KITE", "KITTEN", "KNEE", "KNIFE", "KNOCK", "KNOT", "KNOW", "KNOWLEDGE", "KOALA",
        "LABEL", "LABOR", "LACE", "LADDER", "LADY", "LAKE", "LAMP", "LAND", "LANE", "LANGUAGE", "LARGE", "LAST", "LATE", "LATELY", "LAUGH", "LAUNCH", "LAW", "LAWYER", "LAY", "LAYER",
        "MACHINE", "MAD", "MAGAZINE", "MAGIC", "MAIL", "MAIN", "MAJOR", "MAKE", "MALE", "MAN", "MANAGE", "MANY", "MAP", "MARBLE", "MARCH", "MARK", "MARKET", "MARRY", "MASK", "MASS",
        "NAIL", "NAME", "NARROW", "NATION", "NATURE", "NEAR", "NEARBY", "NEAT", "NECK", "NEED", "NEEDLE", "NEGATIVE", "NEIGHBOR", "NEST", "NET", "NETWORK", "NEVER", "NEW", "NEWS", "NEXT",
        "OAK", "OBEY", "OBJECT", "OBSERVE", "OBVIOUS", "OCCUR", "OCEAN", "ODD", "OFFER", "OFFICE", "OFFICER", "OFTEN", "OIL", "OKAY", "OLD", "ONCE", "ONLY", "OPEN", "OPTION", "ORANGE",
        "PACE", "PACK", "PACKAGE", "PAGE", "PAIN", "PAINT", "PAIR", "PALACE", "PALM", "PANEL", "PANIC", "PAPER", "PARADE", "PARENT", "PARK", "PART", "PARTNER", "PARTY", "PASS",
        "QUAKE", "QUALITY", "QUANTITY", "QUARREL", "QUART", "QUARTER", "QUARTZ", "QUEEN", "QUEST", "QUESTION", "QUICK", "QUICKLY", "QUIET", "QUIETLY", "QUILT", "QUIT", "QUITE", "QUOTE",
        "RABBIT", "RACE", "RADAR", "RADIO", "RADIUS", "RAGE", "RAIL", "RAIN", "RAISE", "RANGE", "RAPID", "RARE", "RATE", "RATHER", "RATIO", "RAW", "REACH", "REACT", "READ", "READY",
        "SAD", "SAFE", "SAFETY", "SAIL", "SAILOR", "SALE", "SALT", "SAME", "SAMPLE", "SAND", "SATURDAY", "SAVE", "SAY", "SCALE", "SCAN", "SCENE", "SCENT", "SCHOOL", "SCIENCE", "SCORE",
        "TABLE", "TAIL", "TAKE", "TALENT", "TALK", "TALL", "TANK", "TAPE", "TARGET", "TASK", "TASTE", "TAX", "TAXI", "TEA", "TEACH", "TEAM", "TEAR", "TEETH", "TELEPHONE", "TEMPLE",
        "UGLY", "UMBRELLA", "UNABLE", "UNCLE", "UNDER", "UNIT", "UNITE", "UNITY", "UNIVERSE", "UNIVERSITY", "UNKNOWN", "UNLESS", "UNTIL", "UPON", "UPPER", "UPSET", "URBAN", "URGE", "USE", "USER",
        "VACANT", "VACATION", "VAGUE", "VAIN", "VALLEY", "VALUE", "VAN", "VANISH", "VAPOR", "VARY", "VASE", "VAST", "VEGETABLE", "VEHICLE", "VELOCITY", "VERB", "VERSE", "VERSION", "VERY", "VICTORY",
        "WAGON", "WAIST", "WAIT", "WAITER", "WAKE", "WALK", "WALL", "WALLET", "WANDER", "WANT", "WAR", "WARM", "WARN", "WASH", "WASTE", "WATCH", "WATER", "WAVE", "WAY", "WEAK",
        "XRAY", "XYLOPHONE",
        "YACHT", "YARD", "YARN", "YAWN", "YEAR", "YEARLY", "YEAST", "YELL", "YELLOW", "YES", "YESTERDAY", "YET", "YIELD", "YOGA", "YOGURT", "YOU", "YOUNG", "YOUR", "YOURSELF", "YOUTH",
        "ZEBRA", "ZERO", "ZIGZAG", "ZIP", "ZIPPER", "ZONE", "ZOO", "ZOOM"
    ]

    private var config = TextEntryTaskConfig()
    private var eventLogger: ((TaskEventPayload) -> Void)?
    private var isRunning = false
    private var nextPromptDate: Date?
    private var currentTargetText = ""
    private var enteredText = ""

    func configure(config: TextEntryTaskConfig, eventLogger: @escaping (TaskEventPayload) -> Void) {
        self.config = config
        self.eventLogger = eventLogger
    }

    func start() {
        isRunning = true
        currentPrompt = nil
        nextPromptDate = Date()
        currentTargetText = ""
        enteredText = ""
        lastResult = nil
        isReadyToSubmit = false
    }

    func stop() {
        isRunning = false
        currentPrompt = nil
        nextPromptDate = nil
        currentTargetText = ""
        enteredText = ""
        lastResult = nil
        isReadyToSubmit = false
    }

    func pause() {
        isRunning = false
    }

    func resume() {
        isRunning = true
        if nextPromptDate == nil {
            nextPromptDate = Date()
        }
    }

    @discardableResult
    func update(now: Date, elapsedTime: TimeInterval) -> Bool {
        var changed = false

        if let prompt = currentPrompt, prompt.expiresAt <= now {
            eventLogger?(
                TaskEventPayload(
                    elapsedTime: elapsedTime,
                    eventType: "text_entry_miss",
                    taskType: .textEntry,
                    rule: "指定文字列を入力",
                    isCorrect: "false",
                    detail1: prompt.targetText,
                    detail2: prompt.enteredText
                )
            )
            currentPrompt = nil
            currentTargetText = ""
            enteredText = ""
            lastResult = nil
            isReadyToSubmit = false
            nextPromptDate = now.addingTimeInterval(config.interPromptInterval)
            changed = true
        }

        guard isRunning else { return changed }
        guard currentPrompt == nil else { return changed }
        guard let nextPromptDate, now >= nextPromptDate else { return changed }

        let target = prompts.randomElement() ?? "VISION"
        currentTargetText = target
        enteredText = ""
        lastResult = nil
        isReadyToSubmit = false
        currentPrompt = TextEntryPrompt(
            id: UUID(),
            targetText: target,
            enteredText: enteredText,
            options: makeOptions(for: target),
            spawnedAt: now,
            expiresAt: now.addingTimeInterval(config.displayDuration)
        )

        eventLogger?(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: "text_entry_spawn",
                taskType: .textEntry,
                rule: "指定文字列を入力",
                detail1: target
            )
        )
        return true
    }

    @discardableResult
    func handleKey(_ key: String, elapsedTime: TimeInterval) -> Bool {
        guard let prompt = currentPrompt else { return false }

        if key == "DELETE" {
            if !enteredText.isEmpty {
                enteredText.removeLast()
                isReadyToSubmit = (enteredText == currentTargetText)
                refreshPrompt(from: prompt)
                return true
            }
            return false
        }

        enteredText.append(key)
        // 文字列が完全一致した時のみ提出可能フラグを立てる
        isReadyToSubmit = (enteredText == currentTargetText)
        refreshPrompt(from: prompt)
        return true
    }

    @discardableResult
    func handleSubmit(elapsedTime: TimeInterval) -> Bool {
        guard let prompt = currentPrompt else { return false }
        guard isReadyToSubmit else { return false }

        let isCorrect = (enteredText == currentTargetText)
        eventLogger?(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: isCorrect ? "text_entry_correct" : "text_entry_wrong",
                taskType: .textEntry,
                rule: "指定文字列を入力",
                isCorrect: isCorrect ? "true" : "false",
                reactionTime: Date().timeIntervalSince(prompt.spawnedAt),
                detail1: currentTargetText,
                detail2: enteredText
            )
        )
        lastResult = isCorrect
        currentPrompt = nil
        currentTargetText = ""
        enteredText = ""
        isReadyToSubmit = false
        nextPromptDate = Date().addingTimeInterval(0.5)
        return true
    }

    private func refreshPrompt(from prompt: TextEntryPrompt) {
        currentPrompt = TextEntryPrompt(
            id: prompt.id,
            targetText: currentTargetText,
            enteredText: enteredText,
            options: prompt.options,
            spawnedAt: prompt.spawnedAt,
            expiresAt: prompt.expiresAt
        )
    }

    private func makeOptions(for target: String) -> [String] {
        let targetChars = Array(Set(target.map(String.init)))
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map(String.init)
        var options = targetChars
        while options.count < 8 {
            let candidate = alphabet.randomElement() ?? "A"
            if !options.contains(candidate) {
                options.append(candidate)
            }
        }
        options.append("DELETE")
        return options.shuffled()
    }
}
