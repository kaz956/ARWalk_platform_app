import SwiftUI
import Foundation
import simd

class PanelModel: ObservableObject {
    enum PanelOrientation: String, CaseIterable, Identifiable {
        case landscape
        case portrait

        var id: String { rawValue }
        var label: String { self == .landscape ? "横" : "縦" }
    }

    enum PanelScalePreset: String, CaseIterable, Identifiable {
        case small
        case medium
        case large

        var id: String { rawValue }
        var label: String {
            switch self {
            case .small: return "小 (20°)"
            case .medium: return "中 (40°)"
            case .large: return "大 (60°)"
            }
        }

        var vofDegrees: Float {
            switch self {
            case .small: return 20.0
            case .medium: return 40.0
            case .large: return 60.0
            }
        }
    }

    enum PanelGridX: String, CaseIterable, Identifiable {
        case left = "左 (-35°)"
        case center = "中央 (0°)"
        case right = "右 (35°)"
        
        var id: String { rawValue }
        var angleDegrees: Float {
            switch self {
            case .left: return -35.0
            case .center: return 0.0
            case .right: return 35.0
            }
        }
    }
    
    enum PanelGridY: String, CaseIterable, Identifiable {
        case top = "上 (10°)"
        case center = "中央 (-10°)"
        case bottom = "下 (-40°)"
        
        var id: String { rawValue }
        var angleDegrees: Float {
            switch self {
            case .top: return 10.0
            case .center: return -10.0
            case .bottom: return -40.0
            }
        }
    }
    
    enum PanelGridZ: String, CaseIterable, Identifiable {
        case near = "手前 (1.25m)"
        case mid = "中 (2.0m)"
        case far = "奥 (5.0m)"
        
        var id: String { rawValue }
        var distance: Float {
            switch self {
            case .near: return 1.25
            case .mid: return 2.0
            case .far: return 5.0
            }
        }
    }

    struct PanelInfo: Identifiable, Equatable {
        let id: String
        var gridX: PanelGridX
        var gridY: PanelGridY
        var gridZ: PanelGridZ
        var orientation: PanelOrientation
        var scalePreset: PanelScalePreset
        var isVisible: Bool
        var color: Color
        var opacity: Double
        
        var worldPosition: SIMD3<Float> {
            let d = gridZ.distance
            let size = renderSize
            
            // ユーザーから見たパネルの横・縦のハーフ視野角（半角）をラジアンで算出
            let halfAngleXRad = atan((size.x / 2.0) / d)
            let halfAngleYRad = atan((size.y / 2.0) / d)
            
            // 度数法に変換
            let halfAngleX = halfAngleXRad * 180.0 / Float.pi
            let halfAngleY = halfAngleYRad * 180.0 / Float.pi
            
            // 左右角度（Theta）の補正
            var thetaDeg = gridX.angleDegrees
            switch gridX {
            case .left:
                // 左端が -35° に接するように、中心を右（プラス方向）にシフト
                thetaDeg = -35.0 + halfAngleX
            case .right:
                // 右端が 35° に接するように、中心を左（マイナス方向）にシフト
                thetaDeg = 35.0 - halfAngleX
            case .center:
                thetaDeg = 0.0
            }
            
            // 上下角度（Phi）の補正
            var phiDeg = gridY.angleDegrees
            switch gridY {
            case .bottom:
                // 下端が -40° に接するように、中心を上（プラス方向）にシフト
                phiDeg = -40.0 + halfAngleY
            case .top:
                // 上端が 10° に接するように、中心を下（マイナス方向）にシフト
                phiDeg = 10.0 - halfAngleY
            case .center:
                // 中央（ベースライン）は指定値通り -10° のまま
                phiDeg = -10.0
            }
            
            // 球面座標変換用のラジアン値
            let theta = thetaDeg * Float.pi / 180.0
            let phi = phiDeg * Float.pi / 180.0
            
            // 3Dデカルト座標の算出
            let x = d * sin(theta) * cos(phi)
            let y = d * sin(phi)
            let z = -d * cos(theta) * cos(phi)
            
            return SIMD3<Float>(x, y, z)
        }

        var renderSize: SIMD2<Float> {
            let d = gridZ.distance
            let vofRad = scalePreset.vofDegrees * Float.pi / 180.0
            let width = 2.0 * d * tan(vofRad / 2.0)
            let landscapeHeight = width * 9.0 / 16.0
            switch orientation {
            case .landscape:
                return SIMD2<Float>(width, landscapeHeight)
            case .portrait:
                return SIMD2<Float>(landscapeHeight, width)
            }
        }
    }

    // HUD パネル（Whack / Calc / Input / Explore / NBack / Notes）
    @Published var panels: [PanelInfo] = [
        PanelInfo(
            id: "Whack",
            gridX: .center, gridY: .center, gridZ: .mid,
            orientation: .landscape,
            scalePreset: .medium,
            isVisible: false,
            color: .black,
            opacity: 0.5
        ),
        PanelInfo(
            id: "Calc",
            gridX: .center, gridY: .center, gridZ: .mid,
            orientation: .landscape,
            scalePreset: .medium,
            isVisible: false,
            color: .black,
            opacity: 0.5
        ),
        PanelInfo(
            id: "Input",
            gridX: .center, gridY: .center, gridZ: .mid,
            orientation: .landscape,
            scalePreset: .medium,
            isVisible: true,
            color: .black,
            opacity: 0.5
        ),
        PanelInfo(
            id: "Explore",
            gridX: .center, gridY: .center, gridZ: .mid,
            orientation: .landscape,
            scalePreset: .large,
            isVisible: false,
            color: .black,
            opacity: 0.5
        ),
        PanelInfo(
            id: "NBack",
            gridX: .center, gridY: .center, gridZ: .mid,
            orientation: .landscape,
            scalePreset: .medium,
            isVisible: false,
            color: .black,
            opacity: 0.5
        ),
        PanelInfo(
            id: "Notes",
            gridX: .center, gridY: .center, gridZ: .mid,
            orientation: .portrait,
            scalePreset: .small,
            isVisible: false,
            color: .black,
            opacity: 0.5
        )
    ]

    @Published var hudPanelsAreShown: Bool = true
    @Published var pathHUDZDistance: Double = 2.0
    @Published var pathHUDYAngleDegrees: Double = -10.0
    @Published var pathHUDXAngleDegrees: Double = 0.0
    @Published var pathHUDVoF: Double = 80.0

    // 人オブジェクト制御用パラメータ
    @Published var peopleIsPlaying: Bool = false
    @Published var peopleSpeedMultiplier: Double = 1.0
    /// 出現間隔（平均）[秒]
    @Published var peopleSpawnInterval: Double = 0.305116
    /// 左右方向の最大オフセット [m]（レーンの半幅）
    @Published var peopleHorizontalRange: Double = 1.4
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
    /// 歩行者・シードのリセット要求回数
    @Published var resetCount: Int = 0
    /// 自身の当たり判定位置のリセット要求回数
    @Published var resetCollisionRequestCount: Int = 0

    var tAB: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 0.09)))
    }
    
    var tCD: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 0.45)))
    }
    
    var tEF: Double {
        let width = Double(peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(peopleSpeedMultiplier)
        let safeWidth = max(0.1, width)
        let safeVelocity = max(0.1, avgVelocity)
        return max(0.3, min(10.0, 1.0 / (safeVelocity * safeWidth * 1.33)))
    }
    
    var currentLOSLabel: String {
        if abs(peopleSpawnInterval - tAB) < 0.1 {
            return "LOS_A_B"
        } else if abs(peopleSpawnInterval - tCD) < 0.1 {
            return "LOS_C_D"
        } else if abs(peopleSpawnInterval - tEF) < 0.1 {
            return "LOS_E_F"
        } else {
            return "Custom"
        }
    }

    func resetPanelsToDefault() {
        self.panels = [
            PanelInfo(
                id: "Whack",
                gridX: .center, gridY: .center, gridZ: .mid,
                orientation: .landscape,
                scalePreset: .medium,
                isVisible: false,
                color: .black,
                opacity: 0.5
            ),
            PanelInfo(
                id: "Calc",
                gridX: .center, gridY: .center, gridZ: .mid,
                orientation: .landscape,
                scalePreset: .medium,
                isVisible: false,
                color: .black,
                opacity: 0.5
            ),
            PanelInfo(
                id: "Input",
                gridX: .center, gridY: .center, gridZ: .mid,
                orientation: .landscape,
                scalePreset: .medium,
                isVisible: true,
                color: .black,
                opacity: 0.5
            ),
            PanelInfo(
                id: "Explore",
                gridX: .center, gridY: .center, gridZ: .mid,
                orientation: .landscape,
                scalePreset: .large,
                isVisible: false,
                color: .black,
                opacity: 0.5
            ),
            PanelInfo(
                id: "NBack",
                gridX: .center, gridY: .center, gridZ: .mid,
                orientation: .landscape,
                scalePreset: .medium,
                isVisible: false,
                color: .black,
                opacity: 0.5
            ),
            PanelInfo(
                id: "Notes",
                gridX: .center, gridY: .center, gridZ: .mid,
                orientation: .portrait,
                scalePreset: .small,
                isVisible: false,
                color: .black,
                opacity: 0.5
            )
        ]
    }

    func applyCondition(_ conditionNumber: Int) {
        for i in 0..<panels.count {
            // 1. まずベースライン（C1基準値）にリセット（isVisible と color は保持）
            panels[i].gridX = .center
            panels[i].gridY = .center
            panels[i].gridZ = .mid
            panels[i].orientation = .landscape
            panels[i].scalePreset = .medium
            panels[i].opacity = 0.5
            
            // 2. 指定の条件に合わせて「1項目だけ」上書き
            switch conditionNumber {
            case 1:
                // C1: ベースライン (リセット状態で一致するため何もしない)
                break
            case 2:
                // C2: 縦画面
                panels[i].orientation = .portrait
            case 3:
                // C3: 小
                panels[i].scalePreset = .small
            case 4:
                // C4: 大
                panels[i].scalePreset = .large
            case 5:
                // C5: 0% 透過度 (不透明 = opacity 1.0)
                panels[i].opacity = 1.0
            case 6:
                // C6: 100% 透過度 (透明 = opacity 0.0)
                panels[i].opacity = 0.0
            case 7:
                // C7: 右
                panels[i].gridX = .right
            case 8:
                // C8: 左
                panels[i].gridX = .left
            case 9:
                // C9: 上
                panels[i].gridY = .top
            case 10:
                // C10: 下
                panels[i].gridY = .bottom
            case 11:
                // C11: 手前
                panels[i].gridZ = .near
            case 12:
                // C12: 奥
                panels[i].gridZ = .far
            default:
                break
            }
        }
    }
}
