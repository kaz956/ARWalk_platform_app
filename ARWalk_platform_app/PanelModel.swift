import SwiftUI
import Foundation
import simd

class PanelModel: ObservableObject {
    struct OptimalZoneConfig: Equatable {
        var isGuideVisible: Bool = false
        var minZ: Float = 1.25
        var maxZ: Float = 5.0
        var baseZ: Float = 2.0
        
        var minPitch: Float = -40.0
        var maxPitch: Float = 10.0
        var basePitch: Float = -10.0
        
        var minYaw: Float = -35.0
        var maxYaw: Float = 35.0
        var baseYaw: Float = 0.0
        
        var minVoF: Float = 40.0
        var maxVoF: Float = 60.0
        var baseVoF: Float = 40.0
    }

    struct PanelInfo: Identifiable, Equatable {
        let id: String
        var angleX: Float
        var angleY: Float
        var distanceZ: Float
        var aspectRatio: Float // Width / Height
        var vofDegrees: Float
        var isVisible: Bool
        var color: Color
        var textColor: Color = .white
        var opacity: Double
        
        var worldPosition: SIMD3<Float> {
            let d = distanceZ
            
            // 球面座標変換用のラジアン値
            let theta = angleX * Float.pi / 180.0
            let phi = angleY * Float.pi / 180.0
            
            // 3Dデカルト座標の算出
            let x = d * sin(theta) * cos(phi)
            let y = d * sin(phi)
            let z = -d * cos(theta) * cos(phi)
            
            return SIMD3<Float>(x, y, z)
        }

        var renderSize: SIMD2<Float> {
            let d = distanceZ
            let vofRad = vofDegrees * Float.pi / 180.0
            let width = 2.0 * d * tan(vofRad / 2.0)
            let height = width / aspectRatio
            return SIMD2<Float>(width, height)
        }
    }

    enum HUDTrackingMode: String, CaseIterable, Identifiable {
        case pathLocked = "Path-Locked"
        case headLocked = "Head-Locked"
        case lazyFollow = "Lazy Follow"
        case bodyLocked = "Body-Locked"
        case pitchLockedYawFollow = "Pitch-Locked, Yaw-Follow"
        case yawLockedPitchFollow = "Yaw-Locked, Pitch-Follow"
        case snapFollow = "Snap Follow"
        case worldOriented = "World-Oriented"

        var id: String { rawValue }
    }
    
    enum PedestrianAlgorithm: String, CaseIterable, Identifiable {
        case customLaneBased = "Custom Lane-Based"
        case socialForceModel = "Social Force Model (SFM)"
        case rvo = "ORCA / RVO"
        case hybrid = "Hybrid (SFM + Predictive Avoidance)"
        
        var id: String { rawValue }
    }
    
    enum PedestrianDirectionMode: String, CaseIterable, Identifiable {
        case oneWay = "One-Way (Oncoming Only)"
        case twoWay = "Two-Way"

        var id: String { rawValue }
    }

    // HUD パネル
    @Published var panels: [PanelInfo] = [
        PanelInfo(
            id: "Whack",
            angleX: 0.0, angleY: -10.0, distanceZ: 2.0,
            aspectRatio: 16.0 / 9.0, vofDegrees: 40.0,
            isVisible: false, color: .black, textColor: .white, opacity: 0.5
        ),
        PanelInfo(
            id: "Calc",
            angleX: 0.0, angleY: -10.0, distanceZ: 2.0,
            aspectRatio: 16.0 / 9.0, vofDegrees: 40.0,
            isVisible: false, color: .black, textColor: .white, opacity: 0.5
        ),
        PanelInfo(
            id: "Input",
            angleX: 0.0, angleY: -10.0, distanceZ: 2.0,
            aspectRatio: 16.0 / 9.0, vofDegrees: 40.0,
            isVisible: true, color: .black, textColor: .white, opacity: 0.5
        ),
        PanelInfo(
            id: "Explore",
            angleX: 0.0, angleY: -10.0, distanceZ: 2.0,
            aspectRatio: 16.0 / 9.0, vofDegrees: 60.0,
            isVisible: false, color: .black, textColor: .white, opacity: 0.5
        ),
        PanelInfo(
            id: "NBack",
            angleX: 0.0, angleY: -10.0, distanceZ: 2.0,
            aspectRatio: 16.0 / 9.0, vofDegrees: 40.0,
            isVisible: false, color: .black, textColor: .white, opacity: 0.5
        ),
        PanelInfo(
            id: "Notes",
            angleX: 0.0, angleY: -10.0, distanceZ: 2.0,
            aspectRatio: 9.0 / 16.0, vofDegrees: 20.0,
            isVisible: false, color: .black, textColor: .white, opacity: 0.5
        )
    ]
    
    // レイアウトプリセット保存用ディクショナリ
    @Published var presets: [String: [PanelInfo]] = [:]

    @Published var hudPanelsAreShown: Bool = true
    @Published var pathHUDZDistance: Double = 2.0
    @Published var pathHUDYAngleDegrees: Double = -10.0
    @Published var pathHUDXAngleDegrees: Double = 0.0
    @Published var pathHUDVoF: Double = 80.0
    
    // スナップ追従用パラメータ
    @Published var snapThresholdDegrees: Double = 30.0

    // 人オブジェクト制御用パラメータ
    @Published var peopleIsPlaying: Bool = false
    @Published var peopleSpeedMultiplier: Double = 1.0
    /// 出現間隔（平均）[秒]
    @Published var peopleSpawnInterval: Double = 0.305116
    /// 左右方向の最大オフセット [m]（レーンの半幅）
    @Published var peopleHorizontalRange: Double = 1.4
    
    /// 歩行アルゴリズムの選択
    @Published var pedestrianAlgorithm: PedestrianAlgorithm = .customLaneBased
    /// 線分の平行移動 X [m]
    @Published var spawnLineCenterX: Double = 15.0
    /// 線分の平行移動 Z [m]
    @Published var spawnLineCenterZ: Double = 0.0
    /// 線分の長さ [m]
    @Published var spawnLineLength: Double = 30.0
    /// 線分の角度 [deg]。0 で +X 方向
    @Published var spawnLineAngleDegrees: Double = 0.0
    /// 身長方向の補正 [m]（床からどれくらい浮かせるか）
    @Published var peopleHeightOffset: Double = -0.52
    /// 衝突判定の可視化フラグ
    @Published var showCollisionVisuals: Bool = false
    
    /// HUDの追従パターン
    @Published var trackingMode: HUDTrackingMode = .pathLocked
    
    /// 歩行者の進行方向
    @Published var pedestrianDirectionMode: PedestrianDirectionMode = .oneWay
    
    /// 最適視野ガイド設定
    @Published var optimalZone = OptimalZoneConfig()

    /// 歩行者・シードのリセット要求回数
    @Published var resetCount: Int = 0
    /// 自身の当たり判定位置のリセット要求回数
    @Published var resetCollisionRequestCount: Int = 0

    var tA: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 0.08)))
    }
    
    var tB: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 0.22)))
    }

    var tC: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 0.36)))
    }

    var tD: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 0.58)))
    }

    var tE: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 0.90)))
    }
    
    var tF: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 1.33)))
    }
    
    var currentLOSLabel: String {
        if abs(peopleSpawnInterval - tA) < 0.1 {
            return "LOS_A"
        } else if abs(peopleSpawnInterval - tB) < 0.1 {
            return "LOS_B"
        } else if abs(peopleSpawnInterval - tC) < 0.1 {
            return "LOS_C"
        } else if abs(peopleSpawnInterval - tD) < 0.1 {
            return "LOS_D"
        } else if abs(peopleSpawnInterval - tE) < 0.1 {
            return "LOS_E"
        } else if abs(peopleSpawnInterval - tF) < 0.1 {
            return "LOS_F"
        } else {
            return "Custom"
        }
    }

    func resetPanelsToDefault() {
        panels = [
            PanelInfo(id: "Whack", angleX: 0.0, angleY: -10.0, distanceZ: 2.0, aspectRatio: 16.0 / 9.0, vofDegrees: 40.0, isVisible: false, color: .black, textColor: .white, opacity: 0.5),
            PanelInfo(id: "Calc", angleX: 0.0, angleY: -10.0, distanceZ: 2.0, aspectRatio: 16.0 / 9.0, vofDegrees: 40.0, isVisible: false, color: .black, textColor: .white, opacity: 0.5),
            PanelInfo(id: "Input", angleX: 0.0, angleY: -10.0, distanceZ: 2.0, aspectRatio: 16.0 / 9.0, vofDegrees: 40.0, isVisible: true, color: .black, textColor: .white, opacity: 0.5),
            PanelInfo(id: "Explore", angleX: 0.0, angleY: -10.0, distanceZ: 2.0, aspectRatio: 16.0 / 9.0, vofDegrees: 60.0, isVisible: false, color: .black, textColor: .white, opacity: 0.5),
            PanelInfo(id: "NBack", angleX: 0.0, angleY: -10.0, distanceZ: 2.0, aspectRatio: 16.0 / 9.0, vofDegrees: 40.0, isVisible: false, color: .black, textColor: .white, opacity: 0.5),
            PanelInfo(id: "Notes", angleX: 0.0, angleY: -10.0, distanceZ: 2.0, aspectRatio: 9.0 / 16.0, vofDegrees: 20.0, isVisible: false, color: .black, textColor: .white, opacity: 0.5)
        ]
    }
    
    func savePreset(name: String) {
        presets[name] = panels
    }
    
    func loadPreset(name: String) {
        if let saved = presets[name] {
            panels = saved
        }
    }

    func applyCondition(_ conditionNumber: Int) {
        // Platform app does not require strict override of conditions, 
        // but we can preserve basic behavior or ignore it.
        // For now, we will simply not override continuous values.
    }
}
