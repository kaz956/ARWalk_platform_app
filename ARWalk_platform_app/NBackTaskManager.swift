import Foundation
import UIKit

struct NBackTaskConfig {
    var nValue: Int = 2
    var stimulusDuration: Double = 1.8
    var interStimulusInterval: Double = 0.7
}

enum NBackBallColor: String, CaseIterable {
    case red
    case blue
    case green
    case yellow
    case purple

    var uiColor: UIColor {
        switch self {
        case .red: return .systemRed
        case .blue: return .systemBlue
        case .green: return .systemGreen
        case .yellow: return .systemYellow
        case .purple: return .systemPurple
        }
    }
}

struct NBackStimulus: Identifiable {
    let id: UUID
    let color: NBackBallColor
    let sequenceIndex: Int
    let isMatch: Bool
    let spawnedAt: Date
    let expiresAt: Date
}

/// 色付き球の n-back タスク
final class NBackTaskManager: ObservableObject, ExperimentalSubTask {
    @Published private(set) var currentStimulus: NBackStimulus?
    @Published private(set) var history: [NBackBallColor] = []

    private var config = NBackTaskConfig()
    private var eventLogger: ((TaskEventPayload) -> Void)?
    private var isRunning = false
    private var nextStimulusDate: Date?
    private var sequenceIndex = 0
    private(set) var selectedColor: NBackBallColor?
    private(set) var lastResult: Bool?

    func configure(config: NBackTaskConfig, eventLogger: @escaping (TaskEventPayload) -> Void) {
        self.config = config
        self.eventLogger = eventLogger
    }

    func start() {
        isRunning = true
        currentStimulus = nil
        history = []
        sequenceIndex = 0
        selectedColor = nil
        lastResult = nil
        nextStimulusDate = Date()
    }

    func stop() {
        isRunning = false
        currentStimulus = nil
        history = []
        nextStimulusDate = nil
        sequenceIndex = 0
        selectedColor = nil
        lastResult = nil
    }

    func pause() {
        isRunning = false
    }

    func resume() {
        isRunning = true
        if nextStimulusDate == nil {
            nextStimulusDate = Date()
        }
    }

    @discardableResult
    func update(now: Date, elapsedTime: TimeInterval) -> Bool {
        var changed = false

        guard isRunning else { return changed }
        guard currentStimulus == nil else { return changed }
        guard let nextStimulusDate, now >= nextStimulusDate else { return changed }

        let color = makeNextColor()
        let isMatch = history.count >= config.nValue && history[history.count - config.nValue] == color
        let stimulus = NBackStimulus(
            id: UUID(),
            color: color,
            sequenceIndex: sequenceIndex,
            isMatch: isMatch,
            spawnedAt: now,
            expiresAt: Date.distantFuture
        )
        currentStimulus = stimulus
        history.append(color)
        if history.count > 6 {
            history.removeFirst(history.count - 6)
        }
        sequenceIndex += 1
        selectedColor = nil
        lastResult = nil

        eventLogger?(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: "nback_spawn",
                taskType: .nBack,
                rule: "\(config.nValue)-back color match",
                detail1: color.rawValue,
                detail2: String(stimulus.sequenceIndex)
            )
        )
        return true
    }

    var canAnswer: Bool {
        return history.count > config.nValue
    }

    @discardableResult
    func handleResponse(color: NBackBallColor, elapsedTime: TimeInterval) -> Bool {
        guard currentStimulus != nil else { return false }
        guard canAnswer else { return false }
        
        selectedColor = color
        return true
    }

    @discardableResult
    func handleNext(elapsedTime: TimeInterval) -> Bool {
        guard let stimulus = currentStimulus else { return false }
        
        if canAnswer {
            if let color = selectedColor {
                let correctColor = history[history.count - 1 - config.nValue]
                let isCorrect = color == correctColor
                lastResult = isCorrect

                eventLogger?(
                    TaskEventPayload(
                        elapsedTime: elapsedTime,
                        eventType: isCorrect ? "nback_correct" : "nback_wrong",
                        taskType: .nBack,
                        rule: "\(config.nValue)-back color match",
                        isCorrect: isCorrect ? "true" : "false",
                        reactionTime: Date().timeIntervalSince(stimulus.spawnedAt),
                        detail1: stimulus.color.rawValue,
                        detail2: String(stimulus.sequenceIndex),
                        detail3: color.rawValue,
                        detail4: correctColor.rawValue
                    )
                )
            } else {
                lastResult = false
                eventLogger?(
                    TaskEventPayload(
                        elapsedTime: elapsedTime,
                        eventType: "nback_miss",
                        taskType: .nBack,
                        rule: "\(config.nValue)-back color match",
                        isCorrect: "false",
                        detail1: stimulus.color.rawValue,
                        detail2: String(stimulus.sequenceIndex)
                    )
                )
            }
        }

        currentStimulus = nil
        selectedColor = nil
        nextStimulusDate = Date().addingTimeInterval(0.2) // Next押したらすぐ次へ
        return true
    }

    private func makeNextColor() -> NBackBallColor {
        return NBackBallColor.allCases.randomElement() ?? .red
    }
}
