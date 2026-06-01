import Foundation
import SwiftUI

private let sharedISOFormatter = ISO8601DateFormatter()

protocol ExperimentalSubTask {
    func start()
    func stop()
    func pause()
    func resume()
}

enum ExperimentalTaskType: String, CaseIterable, Identifiable, Hashable {
    case arcade
    case arithmetic
    case textEntry = "text_entry"
    case pageExplore = "page_explore"
    case nBack = "n_back"

    var id: String { rawValue }
}

enum ExperimentRunState: String, CaseIterable {
    case idle = "Idle"
    case running = "Running"
    case finished = "Finished"
}

struct ExperimentMetadata {
    let participantID: String
    let conditionID: String
    let los: String
    let startedAt: Date
}

struct TaskEventPayload {
    let elapsedTime: TimeInterval
    let eventType: String
    let taskType: ExperimentalTaskType
    let targetID: String?
    let targetColor: String?
    let targetShape: String?
    let targetSymbol: String?
    let targetNumber: String?
    let rule: String?
    let isCorrect: String?
    let reactionTime: TimeInterval?
    let targetX: Double?
    let targetY: Double?
    let arithmeticQuestion: String?
    let arithmeticCorrectAnswer: String?
    let arithmeticSelectedAnswer: String?
    let arithmeticOptions: String?
    let arithmeticOperator: String?
    let arithmeticDifficulty: String?
    let detail1: String?
    let detail2: String?
    let detail3: String?
    let detail4: String?

    init(
        elapsedTime: TimeInterval,
        eventType: String,
        taskType: ExperimentalTaskType,
        targetID: String? = nil,
        targetColor: String? = nil,
        targetShape: String? = nil,
        targetSymbol: String? = nil,
        targetNumber: String? = nil,
        rule: String? = nil,
        isCorrect: String? = nil,
        reactionTime: TimeInterval? = nil,
        targetX: Double? = nil,
        targetY: Double? = nil,
        arithmeticQuestion: String? = nil,
        arithmeticCorrectAnswer: String? = nil,
        arithmeticSelectedAnswer: String? = nil,
        arithmeticOptions: String? = nil,
        arithmeticOperator: String? = nil,
        arithmeticDifficulty: String? = nil,
        detail1: String? = nil,
        detail2: String? = nil,
        detail3: String? = nil,
        detail4: String? = nil
    ) {
        self.elapsedTime = elapsedTime
        self.eventType = eventType
        self.taskType = taskType
        self.targetID = targetID
        self.targetColor = targetColor
        self.targetShape = targetShape
        self.targetSymbol = targetSymbol
        self.targetNumber = targetNumber
        self.rule = rule
        self.isCorrect = isCorrect
        self.reactionTime = reactionTime
        self.targetX = targetX
        self.targetY = targetY
        self.arithmeticQuestion = arithmeticQuestion
        self.arithmeticCorrectAnswer = arithmeticCorrectAnswer
        self.arithmeticSelectedAnswer = arithmeticSelectedAnswer
        self.arithmeticOptions = arithmeticOptions
        self.arithmeticOperator = arithmeticOperator
        self.arithmeticDifficulty = arithmeticDifficulty
        self.detail1 = detail1
        self.detail2 = detail2
        self.detail3 = detail3
        self.detail4 = detail4
    }
}

struct ExportableLogFile: Identifiable {
    let id = UUID()
    let title: String
    let url: URL
}

struct TaskMetricSummary {
    var responseTimeSum: Double = 0
    var responseCount: Int = 0
    var correctCount: Int = 0
    var wrongCount: Int = 0
    var missCount: Int = 0
}

@MainActor
final class ExperimentTaskManager: ObservableObject {
    /// 実験 UI で直接操作する状態
    @Published var participantNumber = 1
    @Published var conditionNumber = 1
    @Published var state: ExperimentRunState = .idle
    @Published var elapsedTime: TimeInterval = 0
    @Published var arithmeticDifficulty: ArithmeticDifficulty = .easy
    @Published var selectiveConfig = SelectiveAttentionConfig()
    @Published var arithmeticConfig = ArithmeticTaskConfig()
    @Published var textEntryConfig = TextEntryTaskConfig()
    @Published var nBackConfig = NBackTaskConfig()
    @Published var errorMessage: String?
    @Published private(set) var hudRefreshToken = UUID()
    @Published private(set) var pathResetToken = UUID()
    @Published private(set) var arcadeScore = 0
    @Published private(set) var comboCount = 0
    @Published private(set) var bestCombo = 0
    @Published private(set) var exportedSessionFile: ExportableLogFile?
    @Published private(set) var exportedSummaryFile: ExportableLogFile?
    @Published var hasIncrementedForCurrentRun = false
    @Published var isCSVSaved = false
    @Published var shouldTriggerCSVExport = false

    // Summary metrics tracking
    private var inputKeyPressCount = 0
    private var inputDelPressCount = 0
    private var inputLastKeyPressTime: Date?
    private var inputKeyPressIntervals: [TimeInterval] = []
    private var inputPromptDurations: [TimeInterval] = []
    
    // IMU stats tracking (User Acceleration Magnitude)
    // Now handled inside MotionRecorder to avoid high-frequency MainActor dispatches.
    let selectiveAttentionTaskManager = SelectiveAttentionTaskManager()
    let arithmeticTaskManager = ArithmeticTaskManager()
    let textEntryTaskManager = TextEntryTaskManager()
    let pageExplorationTaskManager = PageExplorationTaskManager()
    let nBackTaskManager = NBackTaskManager()

    /// ログ記録と HUD 更新の中核
    private let motionRecorder = MotionRecorder()
    private var sessionLogger: UnifiedSessionLogger?
    private var experimentMetadata: ExperimentMetadata?
    private var taskTimer: Timer?
    private var lastSummaryRule = ""
    private var liveElapsedTime: TimeInterval = 0
    private var publishedElapsedTime: TimeInterval = 0
    @Published var collisionCount = 0
    @Published var handOnlyCollisionCount = 0
    @Published var bothCollisionCount = 0
    @Published var leftHandHitCount = 0
    @Published var rightHandHitCount = 0

    enum CollisionType {
        case bodyOnly
        case handOnly
        case both
    }
    private var taskMetrics: [ExperimentalTaskType: TaskMetricSummary] = [:]

    var canStart: Bool {
        state != .running
    }

    var canEnd: Bool {
        state == .running
    }

    var statusText: String {
        state.rawValue
    }

    var participantIDText: String {
        String(format: "P%02d", participantNumber)
    }

    var conditionIDText: String {
        String(format: "C%02d", conditionNumber)
    }

    var conditionName: String {
        switch conditionNumber {
        case 1: return "ベースライン"
        case 2: return "縦画面"
        case 3: return "小"
        case 4: return "大"
        case 5: return "0%"
        case 6: return "100%"
        case 7: return "右"
        case 8: return "左"
        case 9: return "上"
        case 10: return "下"
        case 11: return "手前"
        case 12: return "奥"
        default: return ""
        }
    }

    var arcadeRuleDescription: String {
        selectiveAttentionTaskManager.ruleDescription
    }

    var displayedTargets: [AttentionTarget] {
        selectiveAttentionTaskManager.activeTargets
    }

    var displayedQuestion: ArithmeticQuestion? {
        arithmeticTaskManager.currentQuestion
    }

    var textEntryPrompt: TextEntryPrompt? {
        textEntryTaskManager.currentPrompt
    }

    var pageExplorationChallenge: PageExplorationChallenge? {
        pageExplorationTaskManager.currentChallenge
    }

    var currentNBackStimulus: NBackStimulus? {
        nBackTaskManager.currentStimulus
    }

    var recentNBackColors: [NBackBallColor] {
        nBackTaskManager.history
    }

    init() {
        configureManagers()
    }

    func refreshConfigurations() {
        configureManagers()
        lastSummaryRule = activeRuleSummary(for: allKnownTaskTypes)
        bumpHUD()
    }

    func incrementParticipant() {
        participantNumber += 1
    }

    func decrementParticipant() {
        participantNumber = max(1, participantNumber - 1)
    }

    func incrementCondition() {
        if conditionNumber >= 12 {
            conditionNumber = 1
        } else {
            conditionNumber += 1
        }
    }

    func decrementCondition() {
        if conditionNumber <= 1 {
            conditionNumber = 12
        } else {
            conditionNumber -= 1
        }
    }

    func advanceConditionAndRotateLOS(panelModel: PanelModel) {
        if conditionNumber == 12 {
            conditionNumber = 1
            let currentLOS = panelModel.currentLOSLabel
            if currentLOS == "LOS_F" {
                panelModel.peopleSpawnInterval = panelModel.tA
            } else if currentLOS == "LOS_A" {
                panelModel.peopleSpawnInterval = panelModel.tB
            } else if currentLOS == "LOS_B" {
                panelModel.peopleSpawnInterval = panelModel.tC
            } else if currentLOS == "LOS_C" {
                panelModel.peopleSpawnInterval = panelModel.tD
            } else if currentLOS == "LOS_D" {
                panelModel.peopleSpawnInterval = panelModel.tE
            } else {
                panelModel.peopleSpawnInterval = panelModel.tF
            }
        } else {
            conditionNumber = min(12, conditionNumber + 1)
        }
    }

    func startTask(panelModel: PanelModel) {
        errorMessage = nil
        let visibleTaskTypes = visibleTaskTypes(from: panelModel)
        guard canStart else { return }
        guard !visibleTaskTypes.isEmpty else {
            errorMessage = "表示が ON のタスクパネルがありません。"
            return
        }

        refreshConfigurations()
        resetArcadeMetrics()
        resetTaskMetrics()
        resetSummaryMetrics()
        exportedSessionFile = nil
        exportedSummaryFile = nil
        hasIncrementedForCurrentRun = false
        isCSVSaved = false
        lastSummaryRule = activeRuleSummary(for: visibleTaskTypes)

        let startDate = Date()
        let metadata = ExperimentMetadata(
            participantID: participantIDText,
            conditionID: conditionIDText,
            los: panelModel.currentLOSLabel,
            startedAt: startDate
        )

        do {
            let logger = try makeSessionLogger(metadata: metadata)
            sessionLogger = logger
            experimentMetadata = metadata
            try appendConditionSummary(metadata: metadata, panelModel: panelModel)
            try appendConditionSummary(metadata: metadata, panelModel: panelModel)
            try motionRecorder.startRecording(metadata: metadata, startDate: startDate, sessionLogger: logger)
        } catch {
            errorMessage = "記録ファイルの作成に失敗しました: \(error.localizedDescription)"
            sessionLogger = nil
            experimentMetadata = nil
            return
        }

        stopAllTasks()
        startVisibleTasks(visibleTaskTypes)

        state = .running
        elapsedTime = 0
        liveElapsedTime = 0
        publishedElapsedTime = 0

        logTaskEvent(
            TaskEventPayload(
                elapsedTime: 0,
                eventType: "task_start",
                taskType: primaryTaskType(for: visibleTaskTypes),
                rule: activeRuleSummary(for: visibleTaskTypes)
            )
        )

        startTaskTimer()
        bumpHUD()
        
        // タスク開始時に歩行者の移動再生を確実にオンにし、歩行者リセット（初期ランダム配置を含む）をトリガーする
        panelModel.peopleIsPlaying = true
        panelModel.resetCount += 1
    }

    func endTask(panelModel: PanelModel) {
        guard state == .running else { return }

        let now = Date()
        if let startedAt = experimentMetadata?.startedAt {
            let finalElapsedTime = now.timeIntervalSince(startedAt)
            liveElapsedTime = finalElapsedTime
            elapsedTime = finalElapsedTime
        }

        let visibleTaskTypes = visibleTaskTypes(from: panelModel)
        logTaskEvent(
            TaskEventPayload(
                elapsedTime: elapsedTime,
                eventType: "task_end",
                taskType: primaryTaskType(for: visibleTaskTypes),
                rule: activeRuleSummary(for: visibleTaskTypes)
            )
        )

        taskTimer?.invalidate()
        taskTimer = nil
        state = .finished

        stopAllTasks()
        motionRecorder.stopRecording()
        try? appendTaskMetricSummaries()
        try? sessionLogger?.flush()
        try? sessionLogger?.close()

        if let url = sessionLogger?.fileURL {
            exportedSessionFile = ExportableLogFile(title: "session.csv", url: url)
        }

        if let summaryURL = try? generateSummaryCSV() {
            exportedSummaryFile = ExportableLogFile(title: "summary.csv", url: summaryURL)
        }

        isCSVSaved = false
        shouldTriggerCSVExport = false
        sessionLogger = nil
        experimentMetadata = nil
        panelModel.peopleIsPlaying = false

        // 実験終了後、そのまま折り返して実験ができるようにコースの進行方向を180度反転
        // HUDパネルが飛ばないよう、pathResetTokenを同時に更新してHUDアンカーを再初期化させる
        var newAngle = panelModel.spawnLineAngleDegrees + 180.0
        if newAngle > 180.0 { newAngle -= 360.0 }
        panelModel.spawnLineAngleDegrees = newAngle
        pathResetToken = UUID()

        bumpHUD()
    }

    func syncVisibleTasks(panelModel: PanelModel) {
        if state == .running {
            let visibleTaskTypes = visibleTaskTypes(from: panelModel)
            stopHiddenTasks(visibleTaskTypes)
            startVisibleTasks(visibleTaskTypes)
        }
        bumpHUD()
    }

    func handleEntityTap(_ entityName: String, panelModel: PanelModel) {
        if entityName.hasSuffix(".StartTask") {
            startTask(panelModel: panelModel)
            return
        }

        if entityName == "Condition.Decrement" {
            decrementCondition()
            panelModel.applyCondition(conditionNumber)
            bumpHUD()
            return
        }

        if entityName == "Condition.Increment" {
            incrementCondition()
            panelModel.applyCondition(conditionNumber)
            bumpHUD()
            return
        }

        if entityName == "Crowd.Toggle" {
            let iv = panelModel.peopleSpawnInterval
            if abs(iv - panelModel.tA) < 0.1 {
                panelModel.peopleSpawnInterval = panelModel.tB
            } else if abs(iv - panelModel.tB) < 0.1 {
                panelModel.peopleSpawnInterval = panelModel.tC
            } else if abs(iv - panelModel.tC) < 0.1 {
                panelModel.peopleSpawnInterval = panelModel.tD
            } else if abs(iv - panelModel.tD) < 0.1 {
                panelModel.peopleSpawnInterval = panelModel.tE
            } else if abs(iv - panelModel.tE) < 0.1 {
                panelModel.peopleSpawnInterval = panelModel.tF
            } else {
                panelModel.peopleSpawnInterval = panelModel.tA
            }
            bumpHUD()
            return
        }

        if entityName == "Summary.Save" {
            DispatchQueue.main.async {
                if self.exportedSummaryFile == nil {
                    if let summaryURL = try? self.generateSummaryCSV() {
                        self.exportedSummaryFile = ExportableLogFile(title: "summary.csv", url: summaryURL)
                    }
                }
                if self.exportedSummaryFile != nil {
                    self.isCSVSaved = true
                    self.shouldTriggerCSVExport = true
                    self.bumpHUD()
                }
            }
            return
        }

        guard state == .running else { return }

        if entityName == "TextEntry.End" {
            endTask(panelModel: panelModel)
            return
        }

        if entityName.hasPrefix("AttentionTarget."),
           let id = UUID(uuidString: entityName.replacingOccurrences(of: "AttentionTarget.", with: "")) {
            if selectiveAttentionTaskManager.handleTap(targetID: id, elapsedTime: liveElapsedTime) {
                bumpHUD()
            }
            return
        }

        if entityName.hasPrefix("ArithmeticOption.") {
            let parts = entityName.components(separatedBy: ".")
            if parts.count == 3,
               let questionID = UUID(uuidString: parts[1]),
               let answer = Int(parts[2]),
               arithmeticTaskManager.handleSelection(questionID: questionID, answer: answer, elapsedTime: liveElapsedTime) {
                bumpHUD()
            }
            return
        }

        if entityName == "TextEntry.Submit" || entityName == "TextEntry.Next" {
            if textEntryTaskManager.handleSubmit(elapsedTime: liveElapsedTime) {
                bumpHUD()
            }
            return
        }

        if entityName == "TextEntry.Delete" {
            inputDelPressCount += 1
            if textEntryTaskManager.handleKey("DELETE", elapsedTime: liveElapsedTime) {
                bumpHUD()
            }
            return
        }

        if entityName.hasPrefix("TextEntryKey.") {
            let key = entityName.replacingOccurrences(of: "TextEntryKey.", with: "")
            inputKeyPressCount += 1
            let now = Date()
            if let last = inputLastKeyPressTime {
                inputKeyPressIntervals.append(now.timeIntervalSince(last))
            }
            inputLastKeyPressTime = now
            if textEntryTaskManager.handleKey(key, elapsedTime: liveElapsedTime) {
                bumpHUD()
            }
            return
        }

        if entityName.hasPrefix("PageLink.") || entityName.hasPrefix("Explore.Scroll") {
            if pageExplorationTaskManager.handleTap(targetID: entityName, elapsedTime: liveElapsedTime) {
                bumpHUD()
            }
            return
        }

        if entityName.hasPrefix("NBack.Color.") {
            let rest = entityName.replacingOccurrences(of: "NBack.Color.", with: "")
            let colorStr = rest.components(separatedBy: "_").first ?? ""
            if let color = NBackBallColor(rawValue: colorStr) {
                if nBackTaskManager.handleResponse(color: color, elapsedTime: liveElapsedTime) {
                    bumpHUD()
                }
            }
            return
        }

        if entityName == "NBack.Next" {
            if nBackTaskManager.handleNext(elapsedTime: liveElapsedTime) {
                bumpHUD()
            }
        }
    }

    func registerCollisionContact(type: CollisionType, isLeftHandHit: Bool, isRightHandHit: Bool) {
        registerOrUpdateCollisionContact(oldType: nil, newType: type, isLeftHandHit: isLeftHandHit, isRightHandHit: isRightHandHit)
    }

    func registerOrUpdateCollisionContact(oldType: CollisionType?, newType: CollisionType, isLeftHandHit: Bool, isRightHandHit: Bool) {
        if let old = oldType {
            if old != newType {
                // Decrement old
                switch old {
                case .bodyOnly:
                    break
                case .handOnly:
                    handOnlyCollisionCount = max(0, handOnlyCollisionCount - 1)
                case .both:
                    bothCollisionCount = max(0, bothCollisionCount - 1)
                }
                // Increment new
                switch newType {
                case .bodyOnly:
                    break
                case .handOnly:
                    handOnlyCollisionCount += 1
                case .both:
                    bothCollisionCount += 1
                }
            }
        } else {
            collisionCount += 1 // Total
            switch newType {
            case .bodyOnly:
                break
            case .handOnly:
                handOnlyCollisionCount += 1
            case .both:
                bothCollisionCount += 1
            }
        }
        if isLeftHandHit { leftHandHitCount += 1 }
        if isRightHandHit { rightHandHitCount += 1 }
        hudRefreshToken = UUID()
    }

    private func configureManagers() {
        let eventLogger: (TaskEventPayload) -> Void = { [weak self] payload in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.logTaskEvent(payload)
            }
        }
        selectiveAttentionTaskManager.configure(config: selectiveConfig, eventLogger: eventLogger)
        arithmeticTaskManager.configure(difficulty: arithmeticDifficulty, config: arithmeticConfig, eventLogger: eventLogger)
        textEntryTaskManager.configure(config: textEntryConfig, eventLogger: eventLogger)
        pageExplorationTaskManager.configure(eventLogger: eventLogger)
        nBackTaskManager.configure(config: nBackConfig, eventLogger: eventLogger)
    }

    private func resetArcadeMetrics() {
        arcadeScore = 0
        comboCount = 0
        bestCombo = 0
    }

    private func resetTaskMetrics() {
        collisionCount = 0
        handOnlyCollisionCount = 0
        bothCollisionCount = 0
        leftHandHitCount = 0
        rightHandHitCount = 0
        taskMetrics = [:]
    }

    private func resetSummaryMetrics() {
        inputKeyPressCount = 0
        inputDelPressCount = 0
        inputLastKeyPressTime = nil
        inputKeyPressIntervals = []
        inputPromptDurations = []
    }

    private func generateSummaryCSV() throws -> URL? {
        guard let metadata = experimentMetadata else { return nil }
        
        let textMetrics = taskMetrics[.textEntry] ?? TaskMetricSummary()
        let completedCount = textMetrics.correctCount
        
        let avgKeyPressesPerSecond = elapsedTime > 0 ? Double(inputKeyPressCount) / elapsedTime : 0
        let avgKeyPressTime = inputKeyPressIntervals.isEmpty ? 0 : inputKeyPressIntervals.reduce(0, +) / Double(inputKeyPressIntervals.count)
        
        let avgPromptTime = textMetrics.responseCount > 0 ? textMetrics.responseTimeSum / Double(textMetrics.responseCount) : 0
        
        // IMU SD calculation from MotionRecorder
        let stats = motionRecorder.getStats()
        var imuSD: Double = 0
        if stats.count > 1 {
            let mean = stats.sum / Double(stats.count)
            let variance = (stats.sumSq / Double(stats.count)) - (mean * mean)
            imuSD = sqrt(max(0, variance))
        }

        let headers = [
            "ParticipantID", "ConditionID", "LOS", "Timestamp",
            "TotalTaskDuration(s)",
            "CompletedPrompts", "TotalKeyPresses", "AvgKeyPressesPerSecond(KPS)",
            "AvgKeyPressInterval", "AvgPromptCompletionTime", "DelPressCount",
            "IMU_Accel_SD", "TotalCollisionCount", "HandOnlyCollisionCount", "BothCollisionCount",
            "LeftHandHitCount", "RightHandHitCount"
        ]
        
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: metadata.startedAt)
        
        let dataRow = [
            metadata.participantID,
            metadata.conditionID,
            metadata.los,
            timestamp,
            String(format: "%.2f", elapsedTime),
            "\(completedCount)",
            "\(inputKeyPressCount)",
            String(format: "%.2f", avgKeyPressesPerSecond),
            String(format: "%.4f", avgKeyPressTime),
            String(format: "%.4f", avgPromptTime),
            "\(inputDelPressCount)",
            String(format: "%.6f", imuSD),
            "\(collisionCount)",
            "\(handOnlyCollisionCount)",
            "\(bothCollisionCount)",
            "\(leftHandHitCount)",
            "\(rightHandHitCount)"
        ]

        let csvContent = headers.joined(separator: ",") + "\n" + dataRow.joined(separator: ",")
        
        let fileName = "summary_participant-\(metadata.participantID)_condition-\(metadata.conditionID)_los-\(metadata.los)_\(timestamp).csv"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        
        try csvContent.write(to: fileURL, atomically: true, encoding: .utf8)
        return fileURL
    }

    private func startTaskTimer() {
        taskTimer?.invalidate()
        guard let startedAt = experimentMetadata?.startedAt else { return }

        taskTimer = Timer.scheduledTimer(withTimeInterval: 0.08, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            MainActor.assumeIsolated {
                self.tick(from: startedAt)
            }
        }
    }

    private func tick(from startedAt: Date) {
        guard state == .running else { return }

        let now = Date()
        let currentElapsedTime = now.timeIntervalSince(startedAt)
        liveElapsedTime = currentElapsedTime

        let c1 = selectiveAttentionTaskManager.update(now: now, elapsedTime: currentElapsedTime)
        let c2 = arithmeticTaskManager.update(now: now, elapsedTime: currentElapsedTime)
        let c3 = textEntryTaskManager.update(now: now, elapsedTime: currentElapsedTime)
        let c4 = pageExplorationTaskManager.update(now: now, elapsedTime: currentElapsedTime)
        let c5 = nBackTaskManager.update(now: now, elapsedTime: currentElapsedTime)
        let changed = c1 || c2 || c3 || c4 || c5

        if currentElapsedTime - publishedElapsedTime >= 0.25 {
            publishedElapsedTime = currentElapsedTime
            elapsedTime = currentElapsedTime
        }
        
        if changed {
            bumpHUD()
        }
    }

    private var allKnownTaskTypes: Set<ExperimentalTaskType> {
        [.arcade, .arithmetic, .textEntry, .pageExplore, .nBack]
    }

    private func visibleTaskTypes(from panelModel: PanelModel) -> Set<ExperimentalTaskType> {
        var types = Set<ExperimentalTaskType>()
        if panelModel.panels.contains(where: { $0.id == "Whack" && $0.isVisible }) {
            types.insert(.arcade)
        }
        if panelModel.panels.contains(where: { $0.id == "Calc" && $0.isVisible }) {
            types.insert(.arithmetic)
        }
        if panelModel.panels.contains(where: { $0.id == "Input" && $0.isVisible }) {
            types.insert(.textEntry)
        }
        if panelModel.panels.contains(where: { $0.id == "Explore" && $0.isVisible }) {
            types.insert(.pageExplore)
        }
        if panelModel.panels.contains(where: { $0.id == "NBack" && $0.isVisible }) {
            types.insert(.nBack)
        }
        return types
    }

    private func activeRuleSummary(for visibleTaskTypes: Set<ExperimentalTaskType>) -> String {
        var rules: [String] = []
        if visibleTaskTypes.contains(.arcade) { rules.append(arcadeRuleDescription) }
        if visibleTaskTypes.contains(.arithmetic) { rules.append("4択で計算に回答") }
        if visibleTaskTypes.contains(.textEntry) { rules.append("指定文字列を入力") }
        if visibleTaskTypes.contains(.pageExplore) { rules.append("リンクを辿って目標ページへ到達") }
        if visibleTaskTypes.contains(.nBack) { rules.append("\(nBackConfig.nValue)-back で一致判定") }
        return rules.joined(separator: " / ")
    }

    private func primaryTaskType(for visibleTaskTypes: Set<ExperimentalTaskType>) -> ExperimentalTaskType {
        if visibleTaskTypes.contains(.arcade) { return .arcade }
        if visibleTaskTypes.contains(.arithmetic) { return .arithmetic }
        if visibleTaskTypes.contains(.textEntry) { return .textEntry }
        if visibleTaskTypes.contains(.pageExplore) { return .pageExplore }
        if visibleTaskTypes.contains(.nBack) { return .nBack }
        return .arcade
    }

    private func stopAllTasks() {
        selectiveAttentionTaskManager.stop()
        arithmeticTaskManager.stop()
        textEntryTaskManager.stop()
        pageExplorationTaskManager.stop()
        nBackTaskManager.stop()
    }

    private func startVisibleTasks(_ visibleTaskTypes: Set<ExperimentalTaskType>) {
        if visibleTaskTypes.contains(.arcade) { selectiveAttentionTaskManager.start() }
        if visibleTaskTypes.contains(.arithmetic) { arithmeticTaskManager.start() }
        if visibleTaskTypes.contains(.textEntry) { textEntryTaskManager.start() }
        if visibleTaskTypes.contains(.pageExplore) { pageExplorationTaskManager.start() }
        if visibleTaskTypes.contains(.nBack) { nBackTaskManager.start() }
    }

    private func stopHiddenTasks(_ visibleTaskTypes: Set<ExperimentalTaskType>) {
        if !visibleTaskTypes.contains(.arcade) { selectiveAttentionTaskManager.stop() }
        if !visibleTaskTypes.contains(.arithmetic) { arithmeticTaskManager.stop() }
        if !visibleTaskTypes.contains(.textEntry) { textEntryTaskManager.stop() }
        if !visibleTaskTypes.contains(.pageExplore) { pageExplorationTaskManager.stop() }
        if !visibleTaskTypes.contains(.nBack) { nBackTaskManager.stop() }
    }

    private func makeSessionLogger(metadata: ExperimentMetadata) throws -> UnifiedSessionLogger {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let timestamp = formatter.string(from: metadata.startedAt)
        let fileName = "session_participant-\(metadata.participantID)_condition-\(metadata.conditionID)_los-\(metadata.los)_\(timestamp).csv"
        let fileURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(fileName)
        return try UnifiedSessionLogger(fileURL: fileURL)
    }

    private func logTaskEvent(_ payload: TaskEventPayload) {
        guard let logger = sessionLogger, let metadata = experimentMetadata else { return }

        updateArcadeMetrics(with: payload)
        updateTaskMetrics(with: payload)

        let row: [String: String] = [
            "timestamp": sharedISOFormatter.string(from: Date()),
            "elapsed_time": payload.elapsedTime.csvString,
            "event_type": payload.eventType,
            "task_type": payload.taskType.rawValue,
            "target_id": payload.targetID ?? "",
            "target_color": payload.targetColor ?? "",
            "target_shape": payload.targetShape ?? "",
            "target_symbol": payload.targetSymbol ?? "",
            "target_number": payload.targetNumber ?? "",
            "rule": payload.rule ?? "",
            "is_correct": payload.isCorrect ?? "",
            "reaction_time": payload.reactionTime?.csvString ?? "",
            "target_x": payload.targetX?.csvString ?? "",
            "target_y": payload.targetY?.csvString ?? "",
            "arithmetic_question": payload.arithmeticQuestion ?? "",
            "arithmetic_correct_answer": payload.arithmeticCorrectAnswer ?? "",
            "arithmetic_selected_answer": payload.arithmeticSelectedAnswer ?? "",
            "arithmetic_options": payload.arithmeticOptions ?? "",
            "arithmetic_operator": payload.arithmeticOperator ?? "",
            "arithmetic_difficulty": payload.arithmeticDifficulty ?? "",
            "detail_1": payload.detail1 ?? "",
            "detail_2": payload.detail2 ?? "",
            "detail_3": payload.detail3 ?? "",
            "detail_4": payload.detail4 ?? "",
            "participant_id": metadata.participantID,
            "condition_id": metadata.conditionID,
            "los": metadata.los
        ]

        do {
            try logger.appendTaskEvent(row)
        } catch {
            errorMessage = "タスクイベント保存に失敗しました: \(error.localizedDescription)"
        }
    }

    private func updateTaskMetrics(with payload: TaskEventPayload) {
        var summary = taskMetrics[payload.taskType] ?? TaskMetricSummary()
        if let reactionTime = payload.reactionTime {
            summary.responseTimeSum += reactionTime
            summary.responseCount += 1
        }
        switch payload.eventType {
        case "correct_tap", "arithmetic_correct", "text_entry_correct", "page_goal", "nback_correct":
            summary.correctCount += 1
        case "wrong_tap", "arithmetic_wrong", "text_entry_wrong", "nback_wrong":
            summary.wrongCount += 1
        case "miss", "arithmetic_miss", "text_entry_miss", "page_miss", "nback_miss":
            summary.missCount += 1
        default:
            break
        }
        taskMetrics[payload.taskType] = summary
    }

    private func updateArcadeMetrics(with payload: TaskEventPayload) {
        guard payload.taskType == .arcade else { return }

        switch payload.eventType {
        case "correct_tap":
            comboCount += 1
            bestCombo = max(bestCombo, comboCount)
            arcadeScore += 100 + min(comboCount, 10) * 10
        case "wrong_tap":
            comboCount = 0
            arcadeScore = max(0, arcadeScore - 40)
        case "miss":
            comboCount = 0
            arcadeScore = max(0, arcadeScore - 20)
        default:
            break
        }
    }

    private func appendConditionSummary(metadata: ExperimentMetadata, panelModel: PanelModel) throws {
        guard let logger = sessionLogger else { return }

        let summaryJSON = try makeSummaryJSONString(metadata: metadata, panelModel: panelModel)
        let row: [String: String] = [
            "timestamp": sharedISOFormatter.string(from: metadata.startedAt),
            "event_type": "condition_summary",
            "detail_1": summaryJSON,
            "participant_id": metadata.participantID,
            "condition_id": metadata.conditionID,
            "los": metadata.los
        ]
        try logger.appendSummaryEvent(row)
        try logger.flush()
    }

    private func appendTaskMetricSummaries() throws {
        guard let logger = sessionLogger, let metadata = experimentMetadata else { return }

        for (taskType, summary) in taskMetrics {
            let avgReactionTime = summary.responseCount > 0 ? summary.responseTimeSum / Double(summary.responseCount) : 0
            let row: [String: String] = [
                "timestamp": sharedISOFormatter.string(from: Date()),
                "event_type": "task_metric_summary",
                "task_type": taskType.rawValue,
                "detail_1": "avg_reaction_time=\(avgReactionTime.csvString)",
                "detail_2": "correct_count=\(summary.correctCount)",
                "detail_3": "wrong_count=\(summary.wrongCount)",
                "detail_4": "miss_count=\(summary.missCount)",
                "participant_id": metadata.participantID,
                "condition_id": metadata.conditionID,
                "los": metadata.los
            ]
            try logger.appendSummaryEvent(row)
        }

        let collisionRow: [String: String] = [
            "timestamp": sharedISOFormatter.string(from: Date()),
            "event_type": "collision_summary",
            "detail_1": "collision_count=\(collisionCount)",
            "participant_id": metadata.participantID,
            "condition_id": metadata.conditionID,
            "los": metadata.los
        ]
        try logger.appendSummaryEvent(collisionRow)
    }

    private func makeSummaryJSONString(metadata: ExperimentMetadata, panelModel: PanelModel) throws -> String {
        struct PanelSummary: Codable {
            let id: String
            let panelSize: [Double]
            let panelOpacity: Double
            let panelColor: String
            let panelPosition: [Double]
            let conditionID: String
        }

        struct SessionSummary: Codable {
            let participantID: String
            let conditionID: String
            let activeRules: String
            let arithmeticDifficulty: String
            let arcadeSpawnInterval: Double
            let arcadeDisplayDuration: Double
            let textEntryDisplayDuration: Double
            let nBackValue: Int
            let nBackStimulusDuration: Double
            let panels: [PanelSummary]
        }

        let summary = SessionSummary(
            participantID: metadata.participantID,
            conditionID: metadata.conditionID,
            activeRules: lastSummaryRule,
            arithmeticDifficulty: arithmeticDifficulty.rawValue,
            arcadeSpawnInterval: selectiveConfig.spawnInterval,
            arcadeDisplayDuration: selectiveConfig.displayDuration,
            textEntryDisplayDuration: textEntryConfig.displayDuration,
            nBackValue: nBackConfig.nValue,
            nBackStimulusDuration: nBackConfig.stimulusDuration,
            panels: panelModel.panels.map { panel in
                let renderSize = panel.renderSize
                return PanelSummary(
                    id: panel.id,
                    panelSize: [Double(renderSize.x), Double(renderSize.y)],
                    panelOpacity: panel.opacity,
                    panelColor: String(describing: panel.color),
                    panelPosition: [Double(panel.worldPosition.x), Double(panel.worldPosition.y), Double(panel.worldPosition.z)],
                    conditionID: metadata.conditionID
                )
            }
        )

        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(summary)
        return String(decoding: data, as: UTF8.self)
    }

    private func bumpHUD() {
        hudRefreshToken = UUID()
    }
}

private extension Double {
    var csvString: String {
        String(format: "%.6f", self)
    }
}
