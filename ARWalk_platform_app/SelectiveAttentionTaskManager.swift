import Foundation
import SwiftUI

struct SelectiveAttentionConfig {
    var spawnInterval: Double = 0.5
    var displayDuration: Double = 1.2
    var simultaneousTargetCount: Int = 2
    var correctTargetRatio: Double = 0.65
}

enum AttentionColor: String, CaseIterable {
    case green
    case red

    var uiColor: UIColor {
        switch self {
        case .green: return .systemGreen
        case .red: return .systemRed
        }
    }
}

enum AttentionShape: String, CaseIterable {
    case circle
    case diamond
}

enum AttentionSymbol: String, CaseIterable {
    case hit = "HIT"
    case avoid = "NO"
}

struct AttentionTarget: Identifiable {
    let id: UUID
    let color: AttentionColor
    let shape: AttentionShape
    let symbol: AttentionSymbol
    let number: Int
    let position: CGPoint
    let spawnedAt: Date
    let expiresAt: Date
    let isCorrect: Bool
}

/// シンプルなモグラ叩きタスク。叩く対象と、叩いてはいけない対象だけを出す。
final class SelectiveAttentionTaskManager: ObservableObject, ExperimentalSubTask {
    @Published private(set) var activeTargets: [AttentionTarget] = []
    @Published private(set) var lastHitPosition: CGPoint?
    private var lastHitDate: Date?

    private var config = SelectiveAttentionConfig()
    private var isRunning = false
    private var nextSpawnDate: Date?
    private var eventLogger: ((TaskEventPayload) -> Void)?

    func configure(config: SelectiveAttentionConfig, eventLogger: @escaping (TaskEventPayload) -> Void) {
        self.config = config
        self.eventLogger = eventLogger
    }

    func start() {
        isRunning = true
        activeTargets.removeAll()
        nextSpawnDate = Date()
    }

    func stop() {
        isRunning = false
        activeTargets.removeAll()
        nextSpawnDate = nil
        lastHitPosition = nil
        lastHitDate = nil
    }

    func pause() {
        isRunning = false
    }

    func resume() {
        isRunning = true
        if nextSpawnDate == nil {
            nextSpawnDate = Date()
        }
    }

    var ruleDescription: String {
        "Tap only green HIT targets"
    }

    @discardableResult
    func update(now: Date, elapsedTime: TimeInterval) -> Bool {
        var changed = false
        
        if let hDate = lastHitDate, now.timeIntervalSince(hDate) > 0.12 {
            lastHitPosition = nil
            lastHitDate = nil
            changed = true
        }

        if let first = activeTargets.first, first.expiresAt <= now {
            if first.isCorrect {
                eventLogger?(
                    TaskEventPayload(
                        elapsedTime: elapsedTime,
                        eventType: "miss",
                        taskType: .arcade,
                        targetID: first.id.uuidString,
                        targetColor: first.color.rawValue,
                        targetShape: first.shape.rawValue,
                        targetSymbol: first.symbol.rawValue,
                        targetNumber: String(first.number),
                        rule: ruleDescription,
                        isCorrect: "true",
                        targetX: Double(first.position.x),
                        targetY: Double(first.position.y)
                    )
                )
            }
            activeTargets.removeAll()
            nextSpawnDate = now.addingTimeInterval(max(0.05, config.spawnInterval * 0.35))
            changed = true
        }

        guard isRunning else { return changed }
        guard activeTargets.isEmpty else { return changed }
        guard let nextSpawnDate, now >= nextSpawnDate else { return changed }

        let target = makeTarget(now: now)
        activeTargets = [target]
        eventLogger?(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: "target_spawn",
                taskType: .arcade,
                targetID: target.id.uuidString,
                targetColor: target.color.rawValue,
                targetShape: target.shape.rawValue,
                targetSymbol: target.symbol.rawValue,
                targetNumber: String(target.number),
                rule: ruleDescription,
                isCorrect: target.isCorrect ? "true" : "false",
                targetX: Double(target.position.x),
                targetY: Double(target.position.y)
            )
        )
        self.nextSpawnDate = target.expiresAt
        return true
    }

    @discardableResult
    func handleTap(targetID: UUID, elapsedTime: TimeInterval) -> Bool {
        guard let target = activeTargets.first, target.id == targetID else { return false }
        
        lastHitPosition = target.position
        lastHitDate = Date()
        
        activeTargets.removeAll()

        let reactionTime = Date().timeIntervalSince(target.spawnedAt)
        eventLogger?(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: target.isCorrect ? "correct_tap" : "wrong_tap",
                taskType: .arcade,
                targetID: target.id.uuidString,
                targetColor: target.color.rawValue,
                targetShape: target.shape.rawValue,
                targetSymbol: target.symbol.rawValue,
                targetNumber: String(target.number),
                rule: ruleDescription,
                isCorrect: target.isCorrect ? "true" : "false",
                reactionTime: reactionTime,
                targetX: Double(target.position.x),
                targetY: Double(target.position.y)
            )
        )

        nextSpawnDate = Date().addingTimeInterval(max(0.05, config.spawnInterval * 0.25))
        return true
    }

    private func makeTarget(now: Date) -> AttentionTarget {
        let isCorrect = Double.random(in: 0...1) < config.correctTargetRatio
        let shape: AttentionShape = .circle
        let color: AttentionColor = isCorrect ? .green : .red
        let symbol: AttentionSymbol = isCorrect ? .hit : .avoid

        return AttentionTarget(
            id: UUID(),
            color: color,
            shape: shape,
            symbol: symbol,
            number: isCorrect ? 1 : 0,
            position: CGPoint(x: CGFloat.random(in: 0.0...0.12), y: CGFloat.random(in: -0.05...0.05)),
            spawnedAt: now,
            expiresAt: now.addingTimeInterval(config.displayDuration),
            isCorrect: isCorrect
        )
    }
}
