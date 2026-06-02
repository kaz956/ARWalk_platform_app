import Foundation
import SwiftUI

struct ExplorePage: Identifiable {
    let id: String
    let title: String
    let body: String
    let links: [String]
}

struct PageExplorationChallenge {
    let targetTitle: String
    let currentPage: ExplorePage
    let spawnedAt: Date
    let expiresAt: Date
}

final class PageExplorationTaskManager: ObservableObject, ExperimentalSubTask {
    @Published private(set) var currentChallenge: PageExplorationChallenge?
    @Published private(set) var lastResult: Bool? = nil
    @Published private(set) var scrollLine: Int = 0

    private var eventLogger: ((TaskEventPayload) -> Void)?
    private var isRunning = false
    private var nextChallengeDate: Date?
    private var visitedPages: Set<String> = []
    
    private let pages: [String: ExplorePage] = {
        let list: [ExplorePage] = [
            .init(id: "solar_system", title: "Solar System", body: "The Solar System is a gravitationally bound system comprising the Sun and the objects that orbit it. It consists of 8 planets: Mercury, Venus, Earth, Mars, Jupiter, Saturn, Uranus, and Neptune, each having unique scientific characteristics.", links: ["Ocean", "Artificial Intelligence", "Photosynthesis", "Classical Music"]),
            .init(id: "ocean", title: "Ocean", body: "Oceans cover about 70% of the Earth's surface and form a massive hydrosphere. They are home to diverse organisms and play a crucial role in regulating Earth's climate. Historically, they served as stages for trade and exploration, and continue to greatly impact modern economy and society.", links: ["Solar System", "Photosynthesis", "Fermentation", "Spice"]),
            .init(id: "ai", title: "Artificial Intelligence", body: "Artificial Intelligence (AI) is technology that enables computers to perform human-like intelligent information processing. It has revolutionized various fields like science, economics, society, and culture, and is deeply linked to modern biotechnology and neuroscience.", links: ["Solar System", "Renaissance", "Traditional Arts", "Classical Music"]),
            .init(id: "photosynthesis", title: "Photosynthesis", body: "Photosynthesis is the reaction by which plants and algae synthesize organic compounds using light energy. It is the root of energy for life on Earth, and is studied as a crucial life phenomenon from scientific and biotechnological perspectives.", links: ["Solar System", "Ocean", "Fermentation", "Spice"]),
            .init(id: "renaissance", title: "Renaissance", body: "The Renaissance was a cultural movement that occurred in Europe from the 14th to 16th centuries. It became a major turning point in art, science, history, and culture, where individual creativity and inquiry fundamentally transformed society and artistic expression.", links: ["Artificial Intelligence", "Impressionism", "Jazz", "Traditional Arts"]),
            .init(id: "fermentation", title: "Fermentation", body: "Fermentation is the process by which microorganisms decompose organic matter to produce specific substances. Historically used in cooking and food preservation, it now receives scientific attention in biotechnology and health.", links: ["Ocean", "Photosynthesis", "Spice", "Traditional Arts"]),
            .init(id: "spice", title: "Spice", body: "Spices are seasonings derived from plant seeds, bark, etc. In addition to adding flavor to cooking, they historically triggered trade and cultural exchanges, exerting a massive influence on the world economy and society.", links: ["Ocean", "Photosynthesis", "Fermentation", "Traditional Arts"]),
            .init(id: "impressionism", title: "Impressionism", body: "Impressionism is an art movement that began in 19th-century France. Seeking new expressions to capture light movement and color changes, it transformed traditional art and continues to heavily impact modern culture and expression.", links: ["Renaissance", "Jazz", "Classical Music", "Traditional Arts"]),
            .init(id: "jazz", title: "Jazz", body: "Jazz is a music genre characterized by improvisation. With a rich historical background, it is appreciated worldwide as a unique expression born from cultural fusion, heavily influencing modern society and art.", links: ["Renaissance", "Impressionism", "Classical Music", "Traditional Arts"]),
            .init(id: "classic_mus", title: "Classical Music", body: "Classical music is a western traditional music form. Having developed throughout history, countless masterpieces have been passed down as heritage of art and culture. It also attracts attention in health for its relaxing effects on the brain.", links: ["Solar System", "Artificial Intelligence", "Impressionism", "Jazz"]),
            .init(id: "traditional", title: "Traditional Arts", body: "Traditional arts are forms of art and culture inherited from of old in a society. Embodying language, history, and social identity, they are cherished as a source of new creative inspiration today.", links: ["Artificial Intelligence", "Renaissance", "Fermentation", "Spice", "Impressionism", "Jazz"])
        ]
        return Dictionary(uniqueKeysWithValues: list.map { ($0.title, $0) })
    }()

    func configure(eventLogger: @escaping (TaskEventPayload) -> Void) {
        self.eventLogger = eventLogger
    }

    func start() {
        isRunning = true
        currentChallenge = nil
        nextChallengeDate = Date.distantPast
    }

    func stop() {
        isRunning = false
        currentChallenge = nil
        nextChallengeDate = nil
    }

    func pause() {
        isRunning = false
    }

    func resume() {
        isRunning = true
        if currentChallenge == nil && nextChallengeDate == nil {
            nextChallengeDate = Date.distantPast
        }
    }

    @discardableResult
    func update(now: Date, elapsedTime: TimeInterval) -> Bool {
        guard isRunning else { return false }
        
        if let challenge = currentChallenge, challenge.expiresAt <= now {
            lastResult = false
            currentChallenge = nil
            nextChallengeDate = now.addingTimeInterval(2.0)
            return true
        }
        
        if currentChallenge == nil, let next = nextChallengeDate, now >= next {
            spawnChallenge(now: now)
            nextChallengeDate = nil
            return true
        }
        
        return false
    }

    private func spawnChallenge(now: Date) {
        let allTitles = Array(pages.keys)
        guard let startTitle = allTitles.randomElement(),
              let startPage = pages[startTitle] else { return }
        
        var targetTitle = allTitles.randomElement() ?? startTitle
        while targetTitle == startTitle {
            targetTitle = allTitles.randomElement() ?? startTitle
        }
        
        currentChallenge = PageExplorationChallenge(
            targetTitle: targetTitle,
            currentPage: startPage,
            spawnedAt: now,
            expiresAt: now.addingTimeInterval(30.0)
        )
        scrollLine = 0
        visitedPages = [startTitle]
    }

    @discardableResult
    func handleTap(targetID: String, elapsedTime: TimeInterval) -> Bool {
        guard let challenge = currentChallenge else { return false }
        
        if targetID == "Explore.ScrollUp" {
            scrollLine = max(0, scrollLine - 1)
            return true
        }
        if targetID == "Explore.ScrollDown" {
            scrollLine += 1
            return true
        }
        
        if targetID.hasPrefix("PageLink.") {
            let title = targetID.replacingOccurrences(of: "PageLink.", with: "")
            if let nextPage = pages[title] {
                let reactionTime = elapsedTime - (currentChallenge?.spawnedAt.timeIntervalSinceReferenceDate ?? 0) // rough
                
                if title == challenge.targetTitle {
                    lastResult = true
                    currentChallenge = nil
                    nextChallengeDate = Date().addingTimeInterval(2.0)
                    
                    eventLogger?(TaskEventPayload(
                        elapsedTime: elapsedTime,
                        eventType: "page_correct",
                        taskType: .pageExplore,
                        reactionTime: Date().timeIntervalSince(challenge.spawnedAt)
                    ))
                } else {
                    if visitedPages.contains(title) {
                        eventLogger?(TaskEventPayload(
                            elapsedTime: elapsedTime,
                            eventType: "page_wrong",
                            taskType: .pageExplore
                        ))
                    } else {
                        visitedPages.insert(title)
                    }
                    currentChallenge = PageExplorationChallenge(
                        targetTitle: challenge.targetTitle,
                        currentPage: nextPage,
                        spawnedAt: challenge.spawnedAt,
                        expiresAt: challenge.expiresAt
                    )
                    scrollLine = 0
                }
                return true
            }
        }
        return false
    }
}
