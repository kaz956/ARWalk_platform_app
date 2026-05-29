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
    
    private let pages: [String: ExplorePage] = {
        let list: [ExplorePage] = [
            .init(id: "solar_system", title: "太陽系", body: "太陽系は太陽とその重力によって周囲を回る天体から構成される惑星系です。水星、金星、地球、火星、木星、土星、天王星、海王星の8つの惑星があり、それぞれが独自の科学的特徴を持っています。", links: ["宇宙", "科学", "歴史", "地球"]),
            .init(id: "ocean", title: "海洋", body: "海洋は地球の表面の約70%を占める巨大な水圏です。多様な生物の生息地であり、地球の気候調節に重要な役割を果たしています。歴史的に貿易や探検の舞台となり、現代でも経済や社会に大きな影響を与えています。", links: ["地球", "生物", "歴史", "経済学", "社会"]),
            .init(id: "ai", title: "人工知能", body: "人工知能（AI）は、コンピュータに人間のような知的な情報処理を行わせる技術です。科学、経済学、社会、文化などあらゆる分野に革命をもたらし、現代のバイオテクノロジーや脳科学の研究とも深く関連しています。", links: ["科学", "経済学", "社会", "文化", "バイオテクノロジー", "脳"]),
            .init(id: "photosynthesis", title: "光合成", body: "光合成は植物や藻類が光エネルギーを利用して有機物を合成する反応です。地球上の生物にとってエネルギーの根源であり、科学やバイオテクノロジーの視点からも重要な生命現象として研究されています。", links: ["植物", "生物", "科学", "バイオテクノロジー", "地球"]),
            .init(id: "renaissance", title: "ルネサンス", body: "ルネサンスは14世紀から16世紀にかけてヨーロッパで起こった文化運動です。芸術、科学、歴史、文化の大きな転換点となり、個人の創造性や探求心が社会や表現のあり方を根本から変えました。", links: ["文化", "芸術", "科学", "歴史", "社会"]),
            .init(id: "fermentation", title: "発酵", body: "発酵は微生物が有機物を分解して特定の物質を作る過程です。歴史的に料理や食品保存に利用され、現代ではバイオテクノロジーや健康維持の分野でも科学的に注目されています。", links: ["生物", "料理", "健康", "歴史", "バイオテクノロジー", "科学"]),
            .init(id: "spice", title: "スパイス", body: "スパイスは植物の種子や樹皮などを用いた調味料です。料理に風味を与えるだけでなく、歴史の中で貿易や文化交流のきっかけとなり、世界経済や社会に大きな影響を及ぼしました。", links: ["植物", "料理", "歴史", "経済学", "文化", "社会"]),
            .init(id: "impressionism", title: "印象派", body: "印象派は19世紀フランスに始まった芸術運動です。光の動きや色の変化を捉える新しい表現を追求し、それまでの伝統的な芸術のあり方を変え、現代の文化や表現に大きな影響を与えています。", links: ["芸術", "歴史", "文化", "科学"]),
            .init(id: "jazz", title: "ジャズ", body: "ジャズは即興演奏を特徴とする音楽ジャンルです。歴史的な背景を持ち、文化の融合から生まれた独自の表現として世界中で親しまれ、現代の社会や芸術に多大な影響を与えています。", links: ["音楽", "文化", "歴史", "社会", "芸術"]),
            .init(id: "classic_mus", title: "クラシック音楽", body: "クラシック音楽は西洋の伝統的な音楽形式です。歴史を通じて発展し、数多くの名曲が芸術や文化の遺産として人類に受け継がれています。脳へのリラックス効果など健康面でも注目されます。", links: ["音楽", "芸術", "文化", "歴史", "脳", "健康"]),
            .init(id: "traditional", title: "伝統芸能", body: "伝統芸能はある社会で古くから継承されてきた芸術や文化の形式です。言語や歴史、社会のアイデンティティを体現し、現代でも新たな創造の源泉として大切にされています。", links: ["文化", "歴史", "社会", "芸術", "言語"])
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
                if title == challenge.targetTitle {
                    lastResult = true
                    currentChallenge = nil
                    nextChallengeDate = Date().addingTimeInterval(2.0)
                } else {
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
