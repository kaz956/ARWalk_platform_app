import Foundation

struct ArithmeticTaskConfig {
    var displayDuration: Double = 9999.0
    var interQuestionInterval: Double = 0.8
}

enum ArithmeticDifficulty: String, CaseIterable, Identifiable {
    case easy
    case medium
    case hard

    var id: String { rawValue }
}

struct ArithmeticQuestion: Identifiable {
    let id: UUID
    let prompt: String
    let correctAnswer: Int
    let options: [Int]
    let operatorSymbol: String
    let difficulty: ArithmeticDifficulty
    let spawnedAt: Date
    let expiresAt: Date
}

final class ArithmeticTaskManager: ObservableObject, ExperimentalSubTask {
    @Published private(set) var currentQuestion: ArithmeticQuestion?
    @Published private(set) var lastQuestion: ArithmeticQuestion?
    @Published private(set) var lastResult: Bool?
    @Published private(set) var lastSelectedAnswer: Int?

    private var difficulty: ArithmeticDifficulty = .easy
    private var config = ArithmeticTaskConfig()
    private var eventLogger: ((TaskEventPayload) -> Void)?
    private var isRunning = false
    private var continuousSpawning = true
    private var nextQuestionDate: Date?
    private var hasSpawnedInSingleMode = false

    func configure(
        difficulty: ArithmeticDifficulty,
        config: ArithmeticTaskConfig,
        eventLogger: @escaping (TaskEventPayload) -> Void
    ) {
        self.difficulty = difficulty
        self.config = config
        self.eventLogger = eventLogger
    }

    func start() {
        start(continuousSpawning: true)
    }

    func start(continuousSpawning: Bool) {
        self.continuousSpawning = continuousSpawning
        isRunning = true
        currentQuestion = nil
        lastQuestion = nil
        nextQuestionDate = Date()
        hasSpawnedInSingleMode = false
        lastResult = nil
        lastSelectedAnswer = nil
    }

    func stop() {
        isRunning = false
        currentQuestion = nil
        lastQuestion = nil
        nextQuestionDate = nil
        hasSpawnedInSingleMode = false
        lastResult = nil
        lastSelectedAnswer = nil
    }

    func pause() {
        isRunning = false
    }

    func resume() {
        isRunning = true
        if nextQuestionDate == nil {
            nextQuestionDate = Date()
        }
    }

    var isPresentationComplete: Bool {
        !continuousSpawning && hasSpawnedInSingleMode && currentQuestion == nil
    }

    @discardableResult
    func update(now: Date, elapsedTime: TimeInterval) -> Bool {
        var changed = false

        if let question = currentQuestion, question.expiresAt <= now {
            eventLogger?(
                TaskEventPayload(
                    elapsedTime: elapsedTime,
                    eventType: "arithmetic_miss",
                    taskType: .arithmetic,
                    rule: "4択で回答",
                    isCorrect: "false",
                    reactionTime: nil,
                    arithmeticQuestion: question.prompt,
                    arithmeticCorrectAnswer: String(question.correctAnswer),
                    arithmeticSelectedAnswer: nil,
                    arithmeticOptions: question.options.map(String.init).joined(separator: "|"),
                    arithmeticOperator: question.operatorSymbol,
                    arithmeticDifficulty: question.difficulty.rawValue
                )
            )
            currentQuestion = nil
            lastResult = false
            lastSelectedAnswer = nil
            changed = true
            if continuousSpawning {
                nextQuestionDate = now.addingTimeInterval(config.interQuestionInterval)
            }
        }

        guard isRunning else { return changed }
        guard currentQuestion == nil else { return changed }
        guard let nextQuestionDate, now >= nextQuestionDate else { return changed }

        let question = makeQuestion(now: now)
        currentQuestion = question
        changed = true
        eventLogger?(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: "arithmetic_spawn",
                taskType: .arithmetic,
                rule: "4択で回答",
                isCorrect: nil,
                reactionTime: nil,
                arithmeticQuestion: question.prompt,
                arithmeticCorrectAnswer: String(question.correctAnswer),
                arithmeticSelectedAnswer: nil,
                arithmeticOptions: question.options.map(String.init).joined(separator: "|"),
                arithmeticOperator: question.operatorSymbol,
                arithmeticDifficulty: question.difficulty.rawValue
            )
        )

        if continuousSpawning {
            self.nextQuestionDate = now.addingTimeInterval(question.expiresAt.timeIntervalSince(now) + config.interQuestionInterval)
        } else {
            self.nextQuestionDate = nil
            hasSpawnedInSingleMode = true
        }
        return changed
    }

    @discardableResult
    func handleSelection(questionID: UUID, answer: Int, elapsedTime: TimeInterval) -> Bool {
        guard let question = currentQuestion, question.id == questionID else { return false }

        let isCorrect = answer == question.correctAnswer
        lastResult = isCorrect
        lastSelectedAnswer = answer
        lastQuestion = question
        let reactionTime = Date().timeIntervalSince(question.spawnedAt)

        eventLogger?(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: isCorrect ? "arithmetic_correct" : "arithmetic_wrong",
                taskType: .arithmetic,
                rule: "4択で回答",
                isCorrect: isCorrect ? "true" : "false",
                reactionTime: reactionTime,
                arithmeticQuestion: question.prompt,
                arithmeticCorrectAnswer: String(question.correctAnswer),
                arithmeticSelectedAnswer: String(answer),
                arithmeticOptions: question.options.map(String.init).joined(separator: "|"),
                arithmeticOperator: question.operatorSymbol,
                arithmeticDifficulty: question.difficulty.rawValue
            )
        )

        currentQuestion = nil
        if continuousSpawning {
            nextQuestionDate = Date().addingTimeInterval(config.interQuestionInterval)
        }
        return true
    }

    private func makeQuestion(now: Date) -> ArithmeticQuestion {
        let generated = generateProblem()
        let options = makeOptions(correctAnswer: generated.answer)
        return ArithmeticQuestion(
            id: UUID(),
            prompt: generated.prompt,
            correctAnswer: generated.answer,
            options: options.shuffled(),
            operatorSymbol: generated.operatorSymbol,
            difficulty: difficulty,
            spawnedAt: now,
            expiresAt: now.addingTimeInterval(config.displayDuration)
        )
    }

    private func generateProblem() -> (prompt: String, answer: Int, operatorSymbol: String) {
        switch difficulty {
        case .easy:
            let lhs = Int.random(in: 1...9)
            let rhs = Int.random(in: 1...9)
            if Bool.random() {
                return ("\(lhs) + \(rhs) = ?", lhs + rhs, "+")
            }
            let maxValue = max(lhs, rhs)
            let minValue = min(lhs, rhs)
            return ("\(maxValue) - \(minValue) = ?", maxValue - minValue, "-")

        case .medium:
            let operation = Int.random(in: 0...2)
            if operation == 2 {
                let lhs = Int.random(in: 2...9)
                let rhs = Int.random(in: 2...9)
                return ("\(lhs) × \(rhs) = ?", lhs * rhs, "×")
            }
            let lhs = Int.random(in: 5...30)
            let rhs = Int.random(in: 1...20)
            if operation == 0 {
                return ("\(lhs) + \(rhs) = ?", lhs + rhs, "+")
            }
            let maxValue = max(lhs, rhs)
            let minValue = min(lhs, rhs)
            return ("\(maxValue) - \(minValue) = ?", maxValue - minValue, "-")

        case .hard:
            let operation = Int.random(in: 0...3)
            switch operation {
            case 0:
                let lhs = Int.random(in: 12...49)
                let rhs = Int.random(in: 11...39)
                return ("\(lhs) + \(rhs) = ?", lhs + rhs, "+")
            case 1:
                let lhs = Int.random(in: 20...80)
                let rhs = Int.random(in: 5...40)
                let maxValue = max(lhs, rhs)
                let minValue = min(lhs, rhs)
                return ("\(maxValue) - \(minValue) = ?", maxValue - minValue, "-")
            case 2:
                let lhs = Int.random(in: 4...12)
                let rhs = Int.random(in: 3...12)
                return ("\(lhs) × \(rhs) = ?", lhs * rhs, "×")
            default:
                let rhs = Int.random(in: 2...9)
                let answer = Int.random(in: 2...12)
                let lhs = rhs * answer
                return ("\(lhs) ÷ \(rhs) = ?", answer, "÷")
            }
        }
    }

    private func makeOptions(correctAnswer: Int) -> [Int] {
        var options = Set([correctAnswer])
        while options.count < 4 {
            let candidate = correctAnswer + Int.random(in: -6...6)
            if candidate >= 0 {
                options.insert(candidate)
            }
        }
        return Array(options)
    }
}
