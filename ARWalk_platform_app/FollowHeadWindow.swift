import SwiftUI
import RealityKit
import ARKit
import QuartzCore
import ObjectiveC

private var configKey: UInt8 = 0

private final class EntityCachedConfig {
    let color: UIColor
    let collisionSize: SIMD3<Float>?
    init(color: UIColor, collisionSize: SIMD3<Float>?) {
        self.color = color
        self.collisionSize = collisionSize
    }
}

extension Entity {
    fileprivate var cachedConfig: EntityCachedConfig? {
        get { objc_getAssociatedObject(self, &configKey) as? EntityCachedConfig }
        set { objc_setAssociatedObject(self, &configKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC) }
    }
}

final class MovingEntity {
    var entity: Entity

    /// スポーン時の初期位置（ワールド座標）
    var origin: SIMD3<Float>

    /// 移動の軸方向（単位ベクトル）
    var axisDir: SIMD3<Float>

    /// 個体ごとの基準速度
    var speed: Float

    /// 移動が完了（消滅）するまでの最大距離
    var travelLimit: Float

    /// 移動開始点からの累積移動距離
    var traveled: Float = 0

    /// スポーン待機中（再利用待ち）のフラグ
    var isWaiting: Bool = false

    /// 個体のパーソナルスペース（回避判定の半径）
    var personalRadius: Float = 0.28

    /// 移動方向に垂直な横方向のベクトル
    var lateralDir: SIMD3<Float> = .zero

    /// 現在の横方向オフセット量（廊下の中心からのズレ）
    var lateralOffset: Float = 0

    /// 回避行動等による目標の横オフセット量
    var targetLateralOffset: Float = 0

    /// 横方向に移動可能な最大幅
    var maxAvoidanceOffset: Float = 0.35

    /// 現在の2D速度ベクトル (X, Z) - SFM/RVOで使用
    var velocity2D: SIMD2<Float> = .zero

    /// 回避時に左右どちらを優先するかのバイアス（-1:左, 1:右）
    var avoidanceBias: Float = 0

    /// 好みの巡航ライン（スポーン時に決定）
    var preferredCruiseOffset: Float = 0

    /// スポーン時の初期優先オフセット（本来歩きたいレーン）
    var initialPreferredOffset: Float = 0


    /// 一時停止（譲り合い）の残り持続フレーム
    var yieldFramesRemaining: Int = 0

    /// 手との接触によるリアクションのクールダウン
    var handContactCooldown: Int = 0

    /// 現在、ユーザーの手と接触しているか
    var isHandContacting: Bool = false

    /// 1回の接触イベントをカウント済みかどうかのフラグ
    var hasCountedUserContact: Bool = false

    /// 体との衝突があったか
    var hasBeenHitByBody: Bool = false

    /// 左手との衝突があったか
    var hasBeenHitByLeftHand: Bool = false

    /// 右手との衝突があったか
    var hasBeenHitByRightHand: Bool = false

    /// すでに登録した衝突タイプ
    var registeredCollisionType: ExperimentTaskManager.CollisionType? = nil

    /// 注意散漫状態（スマホ操作モデル等）
    var isDistracted: Bool = false

    /// 精密な衝突判定用の球体配列
    var collisionSpheres: [CollisionSphere] = []

    /// スタック（進行不能）判定用のカウンタ
    var stuckFrames: Int = 0

    /// 補間計算後の現在の移動速度
    var currentSpeed: Float = 0

    /// 現在の回避方向（-1, 0, 1）
    var currentAvoidanceDir: Float = 0

    /// 追い越し維持用のフレームカウンタ
    var overtakeFrameCount: Int = 0

    /// 急な進路変更を抑制するためのクールダウン時間
    var directionChangeCooldown: Int = 0

    var animationController: AnimationPlaybackController?

    /// コリジョンのワールド座標可視化グループ
    var visualGroup: Entity? = nil

    /// キャッシュされた衝突シリンダービジュアル
    var cylinderVisual: ModelEntity? = nil

    /// キャッシュされたパーソナルスペースディスクビジュアル
    var ringVisual: ModelEntity? = nil


    init(entity: Entity, origin: SIMD3<Float>, axisDir: SIMD3<Float>, speed: Float, travelLimit: Float, traveled: Float = 0, isWaiting: Bool = false, personalRadius: Float = 0.28, lateralDir: SIMD3<Float>, lateralOffset: Float = 0, targetLateralOffset: Float = 0, maxAvoidanceOffset: Float = 0.35, avoidanceBias: Float = 0, preferredCruiseOffset: Float = 0, yieldFramesRemaining: Int = 0, handContactCooldown: Int = 0, isHandContacting: Bool = false, hasCountedUserContact: Bool = false, isDistracted: Bool = false, collisionSpheres: [CollisionSphere] = [], stuckFrames: Int = 0, currentSpeed: Float = 0, currentAvoidanceDir: Float = 0, overtakeFrameCount: Int = 0, directionChangeCooldown: Int = 0, animationController: AnimationPlaybackController? = nil) {
        self.entity = entity
        self.origin = origin
        self.axisDir = axisDir
        self.speed = speed
        self.travelLimit = travelLimit
        self.traveled = traveled
        self.isWaiting = isWaiting
        self.personalRadius = personalRadius
        self.lateralDir = lateralDir
        self.lateralOffset = lateralOffset
        self.targetLateralOffset = targetLateralOffset
        self.maxAvoidanceOffset = maxAvoidanceOffset
        self.avoidanceBias = avoidanceBias
        self.preferredCruiseOffset = preferredCruiseOffset
        self.initialPreferredOffset = preferredCruiseOffset

        self.yieldFramesRemaining = yieldFramesRemaining
        self.handContactCooldown = handContactCooldown
        self.isHandContacting = isHandContacting
        self.hasCountedUserContact = hasCountedUserContact
        self.isDistracted = isDistracted
        self.collisionSpheres = collisionSpheres
        self.stuckFrames = stuckFrames
        self.currentSpeed = currentSpeed
        self.currentAvoidanceDir = currentAvoidanceDir
        self.overtakeFrameCount = overtakeFrameCount
        self.directionChangeCooldown = directionChangeCooldown
        self.animationController = animationController
        
        let initialSpeed = currentSpeed > 0 ? currentSpeed : speed
        self.velocity2D = SIMD2<Float>(axisDir.x, axisDir.z) * (initialSpeed * 60.0)
    }
}

struct CollisionSphere {
    var localOffset: SIMD3<Float>
    var radius: Float
}

class SeededRandom {
    private var state: UInt64
    init(seed: UInt64) { self.state = seed == 0 ? 1 : seed }

    func nextFloat() -> Float {
        state = (state &* 6364136223846793005) &+ 1442695040888963407
        return Float(Double(state & 0xFFFFFFFF) / Double(UInt32.max))
    }

    func random(in range: ClosedRange<Float>) -> Float {
        return range.lowerBound + nextFloat() * (range.upperBound - range.lowerBound)
    }

    func random(in range: ClosedRange<Double>) -> Double {
        return range.lowerBound + Double(nextFloat()) * (range.upperBound - range.lowerBound)
    }

    func randomBool() -> Bool {
        return nextFloat() > 0.5
    }

    func randomElement<T>(_ array: [T]) -> T? {
        guard !array.isEmpty else { return nil }
        let index = Int(nextFloat() * Float(array.count))
        return array[min(index, array.count - 1)]
    }

    func shuffled<T>(_ array: [T]) -> [T] {
        var result = array
        guard result.count > 1 else { return result }
        for i in 0..<(result.count - 1) {
            let j = i + Int(nextFloat() * Float(result.count - i))
            if i != j { result.swapAt(i, j) }
        }
        return result
    }
}

/// RealityKitの状態を管理するデータクラス
final class RealitySceneData {
    var modelTemplates: [String: Entity] = [:]
    var movingEntities: [MovingEntity] = []
    var hudPanelEntities: [String: ModelEntity] = [:]
    var hudContentRoots: [String: Entity] = [:]

    // Cache for user visuals to avoid expensive tree lookups on every frame
    var userBodyVisual: ModelEntity? = nil
    var userLeftHandVisual: ModelEntity? = nil
    var userRightHandVisual: ModelEntity? = nil

    // Cache for wall updates to avoid redundant transform operations
    var lastWallLength: Float = -1.0
    var lastPeopleHorizontalRange: Float = -1.0
    var lastPeopleHeightOffset: Float = -1.0
    var lastSpawnLineStartWorld: SIMD3<Float> = .zero
    var lastSpawnLineEndWorld: SIMD3<Float> = .zero
    var lastState: ExperimentRunState? = nil

    var spawnXOffsets: [Float] = [-2.2, -1.5, -0.8, 0.0, 0.8, 1.5, 2.2]
    var shuffledSpawnXOffsets: [Float] = []
    var spawnXIndex: Int = 0

    var spawnCountdown: Double = 0
    var handContactCount: Int = 0
    var frameCount: Int = 0
    var lastCheckedCollisionCount: Int = -1
    var lastVisualBodyRadius: Float = -1.0
    var lastVisualHandRadius: Float = -1.0

    var randomGen = SeededRandom(seed: 42)
    var needsInitialSpawn: Bool = true

    var pendingHUDToken: UUID? = nil
    var lastHUDToken: UUID? = nil
    var smoothedUserPosition: SIMD3<Float> = .zero
    var previousSmoothedUserPosition: SIMD3<Float> = .zero
    var pathAnchorPosition: SIMD3<Float> = .zero
    var smoothedPathForward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    var smoothedHeadForward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    var smoothedVelocity: SIMD3<Float> = .zero
    var locomotionHeading: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    var locomotionPositionHistory: [SIMD3<Float>] = []
    var sustainedHeadingCandidate: SIMD3<Float>? = nil
    var sustainedHeadingDuration: Float = 0
    var hasPathAnchorState: Bool = false
    var lastSnappedOrientation: simd_quatf = simd_quatf()

    var headAnchor = AnchorEntity()
    var leftHandAnchor = AnchorEntity(.hand(.left, location: .palm))
    var rightHandAnchor = AnchorEntity(.hand(.right, location: .palm))
    var worldAnchor = Entity()
    var pathAnchor = Entity()
    var hudRoot = Entity()

    var arkitSession = ARKitSession()
    var worldTracking = WorldTrackingProvider()
    var handTracking = HandTrackingProvider()
    var latestDevicePosition: SIMD3<Float> = .zero
    var latestDeviceForward: SIMD3<Float> = SIMD3<Float>(0, 0, -1)
    var latestDeviceOrientation: simd_quatf = simd_quatf()
    var hasDevicePosition: Bool = false

    var latestLeftHandPosition: SIMD3<Float> = .zero
    var latestRightHandPosition: SIMD3<Float> = .zero
    var hasLeftHandPosition: Bool = false
    var hasRightHandPosition: Bool = false

    var leftWall: Entity?
    var rightWall: Entity?

    var spawnLineEntity: ModelEntity?
    var spawnStartMarker: ModelEntity?
    var spawnEndMarker: ModelEntity?
    var spawnStartUILabel: ModelEntity?
    var spawnEndUILabel: ModelEntity?
}

struct HUDImmersiveView: View {
    @EnvironmentObject var panelModel: PanelModel
    @EnvironmentObject var experimentManager: ExperimentTaskManager

    private let defaultCollisionZ: Float = 0.04

    private let modelScales: [String: Float] = [
        "Man": 1.8,
        "Woman": 1.65,
        "Man_phone": 1.9,
        "Woman_phone": 1.7
    ]

    @State private var sceneData = RealitySceneData()

    @State private var updateSubscription: EventSubscription?
    @State private var isSceneReady: Bool = false
    @State private var latchedTapEntity: Entity?

    // MARK: - Spawn line geometry
    private var spawnLineDirection: SIMD3<Float> {
        // スライダー表示の基準点を調整するため、+180°のオフセットを加算する。
        // これによりスライダー0°=従来の180°方向（コースのデフォルト向き）となる。
        let radians = Float(panelModel.spawnLineAngleDegrees + 180.0) * .pi / 180
        return simd_normalize(SIMD3<Float>(cos(radians), 0, sin(radians)))
    }

    private var spawnLineCenterWorld: SIMD3<Float> {
        SIMD3<Float>(
            Float(panelModel.spawnLineCenterX),
            Float(panelModel.peopleHeightOffset),
            Float(panelModel.spawnLineCenterZ)
        )
    }

    private var spawnLineLength: Float {
        max(0.2, Float(panelModel.spawnLineLength))
    }

    private var spawnLineStartWorld: SIMD3<Float> {
        spawnLineCenterWorld - spawnLineDirection * (spawnLineLength * 0.5)
    }

    private var spawnLineEndWorld: SIMD3<Float> {
        spawnLineCenterWorld + spawnLineDirection * (spawnLineLength * 0.5)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            RealityView { content in
                sceneData.headAnchor = AnchorEntity(.head)
                sceneData.headAnchor.anchoring.trackingMode = .continuous
                content.add(sceneData.headAnchor)

                sceneData.leftHandAnchor = AnchorEntity(.hand(.left, location: .palm))
                sceneData.rightHandAnchor = AnchorEntity(.hand(.right, location: .palm))
                content.add(sceneData.leftHandAnchor)
                content.add(sceneData.rightHandAnchor)

                // ワールド固定オブジェクト用アンカー
                sceneData.worldAnchor = AnchorEntity(.world(transform: matrix_identity_float4x4))
                content.add(sceneData.worldAnchor)

                // HUD は headAnchor ではなく、ユーザーの歩行経路 Path に固定する。
                sceneData.pathAnchor = Entity()
                sceneData.pathAnchor.name = "PathAnchor"
                sceneData.worldAnchor.addChild(sceneData.pathAnchor)

                sceneData.hudRoot = Entity()
                sceneData.pathAnchor.addChild(sceneData.hudRoot)

                Task {
                    do {
                        try await sceneData.arkitSession.run([sceneData.worldTracking, sceneData.handTracking])
                    } catch {
                        print("Failed to start ARKit session: \(error)")
                    }
                }

                Task {
                    for await update in sceneData.handTracking.anchorUpdates {
                        let anchor = update.anchor
                        // アンカー自体（手首）のトラッキングが外れた場合は直ちに位置情報を無効化し、当たり判定と表示を消す
                        guard anchor.isTracked else {
                            if anchor.chirality == .left { sceneData.hasLeftHandPosition = false }
                            else { sceneData.hasRightHandPosition = false }
                            continue
                        }
                        
                        // ユーザーの要望により、遮蔽で外れやすい指関節ではなく、最もトラッキング精度が高く安定している「手首（アンカールート）」を直接の当たり判定に使用する
                        let wristTransform = anchor.originFromAnchorTransform
                        let position = SIMD3<Float>(wristTransform.columns.3.x, wristTransform.columns.3.y, wristTransform.columns.3.z)
                        
                        if anchor.chirality == .left {
                            sceneData.latestLeftHandPosition = position
                            sceneData.hasLeftHandPosition = true
                        } else {
                            sceneData.latestRightHandPosition = position
                            sceneData.hasRightHandPosition = true
                        }
                    }
                }

                isSceneReady = true
                refreshPausedPresentation()
                startMovementLoop(content: content)
                updateHUDPanels()

                if sceneData.modelTemplates.isEmpty {
                    for (name, _) in modelScales {
                        if let template = try? await Entity(named: name) {
                            sceneData.modelTemplates[name] = template
                        }
                    }
                }
            } update: { content in
                updateHUDPanels()
            }

/*
            VStack(alignment: .leading, spacing: 10) {
                Text("Spawn Line Settings")
                    .font(.headline)

                GroupBox("Length / Angle") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("L")
                                .frame(width: 16, alignment: .leading)
                            Slider(value: $panelModel.spawnLineLength, in: 0.2...80.0, step: 0.05)
                            TextField("", value: $panelModel.spawnLineLength, format: .number)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("A")
                                .frame(width: 16, alignment: .leading)
                            Slider(value: $panelModel.spawnLineAngleDegrees, in: -180...180, step: 1.0)
                            TextField("", value: $panelModel.spawnLineAngleDegrees, format: .number)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                GroupBox("Translate (world)") {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("X")
                                .frame(width: 16, alignment: .leading)
                            Slider(value: $panelModel.spawnLineCenterX, in: -10...10, step: 0.05)
                            TextField("", value: $panelModel.spawnLineCenterX, format: .number)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                        }
                        HStack {
                            Text("Z")
                                .frame(width: 16, alignment: .leading)
                            Slider(value: $panelModel.spawnLineCenterZ, in: -30...30, step: 0.05)
                            TextField("", value: $panelModel.spawnLineCenterZ, format: .number)
                                .frame(width: 80)
                                .textFieldStyle(.roundedBorder)
                        }
                    }
                }

                Text("Height (Y) は peopleHeightOffset で一括指定")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
            .padding(12)
            .frame(maxWidth: 420)
            .background(.thinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(12)
*/
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .targetedToAnyEntity()
                .onChanged { event in
                    guard latchedTapEntity == nil else { return }
                    latchedTapEntity = event.entity
                }
                .onEnded { _ in
                    if let entity = latchedTapEntity {
                        experimentManager.handleEntityTap(entity.name, panelModel: panelModel)
                    }
                    latchedTapEntity = nil
                }
        )
        .onChange(of: panelModel.hudPanelsAreShown) { _ in
            updateHUDPanels()
        }
        .onChange(of: experimentManager.hudRefreshToken) { newToken in
            sceneData.pendingHUDToken = newToken
        }
        .onChange(of: panelModel.optimalZone) { _ in
            updateHUDPanels()
        }
        .onChange(of: panelModel.panels) { _ in
            updateHUDPanels()
        }
        .onChange(of: panelModel.peopleIsPlaying) { _ in
            refreshPausedPresentation()
        }
        .onChange(of: panelModel.resetCount) { _ in
            resetPedestriansAndSeed()
        }
        .onChange(of: panelModel.resetCollisionRequestCount) { _ in
            resetUserCollisionAnchor()
        }
        .onChange(of: panelModel.spawnLineCenterX) { _ in
            updateSpawnLineVisualization(isVisible: true)
        }
        .onChange(of: panelModel.spawnLineCenterZ) { _ in
            updateSpawnLineVisualization(isVisible: true)
        }
        .onChange(of: panelModel.spawnLineLength) { _ in
            updateSpawnLineVisualization(isVisible: true)
        }
        .onChange(of: panelModel.spawnLineAngleDegrees) { _ in
            updateSpawnLineVisualization(isVisible: true)
        }
        .onChange(of: experimentManager.pathResetToken) { _ in
            // 180度反転などでコース方向が変わった直後にHUDアンカーをリセットする。
            // これによりパネルが「飛んで行く」バグが発生しなくなる。
            resetPathAnchorState()
        }
        .onDisappear {
            isSceneReady = false
            updateSubscription?.cancel()
            updateSubscription = nil
            sceneData.spawnLineEntity?.removeFromParent()
            sceneData.spawnStartMarker?.removeFromParent()
            sceneData.spawnEndMarker?.removeFromParent()
            sceneData.spawnStartUILabel?.removeFromParent()
            sceneData.spawnEndUILabel?.removeFromParent()
            sceneData.spawnLineEntity = nil
            sceneData.spawnStartMarker = nil
            sceneData.spawnEndMarker = nil
            sceneData.spawnStartUILabel = nil
            sceneData.spawnEndUILabel = nil
            sceneData.hudRoot.removeFromParent()
            sceneData.pathAnchor.removeFromParent()
            sceneData.hudPanelEntities.removeAll()
            sceneData.hudContentRoots.removeAll()
            resetPathAnchorState()
            latchedTapEntity = nil
        }
    }

    // MARK: - State Sync Helpers

    @discardableResult
    private func addOrUpdateTextEntity(id: String, text: String, fontSize: Float, color: UIColor, position: SIMD3<Float>, wrapWidth: Float? = nil, parent: Entity) -> ModelEntity? {
        let entityNameBase = "TextEntity_\(id)"
        let textTag = "::\(text)"

        if let existing = parent.children.first(where: { $0.name.hasPrefix(entityNameBase) }) as? ModelEntity {
            if existing.position != position {
                existing.position = position
            }
            if existing.name == entityNameBase + textTag {
                return existing
            }

            let frame = wrapWidth != nil ? CGRect(x: 0, y: 0, width: CGFloat(wrapWidth!), height: 10.0) : .zero
            if let mesh = try? MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: CGFloat(fontSize)), containerFrame: frame, alignment: .left, lineBreakMode: .byWordWrapping) {
                existing.model?.mesh = mesh
                existing.name = entityNameBase + textTag
                if var model = existing.components[ModelComponent.self] {
                    model.materials = [SimpleMaterial(color: color, isMetallic: false)]
                    existing.components.set(model)
                }
            }
            return existing
        }

        let frame = wrapWidth != nil ? CGRect(x: 0, y: 0, width: CGFloat(wrapWidth!), height: 10.0) : .zero
        guard let mesh = try? MeshResource.generateText(text, extrusionDepth: 0.001, font: .systemFont(ofSize: CGFloat(fontSize)), containerFrame: frame, alignment: .left, lineBreakMode: .byWordWrapping) else { return nil }

        let entity = ModelEntity(mesh: mesh, materials: [SimpleMaterial(color: color, isMetallic: false)])
        entity.name = entityNameBase + textTag
        entity.position = position
        parent.addChild(entity)
        return entity
    }

    private func addOrUpdateModelEntity(
        id: String,
        meshFactory: () -> MeshResource,
        color: UIColor,
        isMetallic: Bool = false,
        glassRoughness: Float? = nil,
        position: SIMD3<Float>,
        collisionSize: SIMD3<Float>? = nil,
        parent: Entity,
        setup: ((ModelEntity) -> Void)? = nil
    ) -> ModelEntity {
        if let existing = parent.children.first(where: { $0.name == id }) as? ModelEntity {
            if existing.position != position {
                existing.position = position
            }
            
            if let config = existing.cachedConfig,
               config.color == color,
               config.collisionSize == collisionSize {
                return existing
            }
            
            var material = SimpleMaterial(color: color, isMetallic: isMetallic)
            if let r = glassRoughness {
                material.roughness = .init(floatLiteral: r)
                material.metallic = 0.8
            }
            if var modelComponent = existing.components[ModelComponent.self] {
                modelComponent.materials = [material]
                existing.components.set(modelComponent)
            }
            
            if let size = collisionSize {
                let offsetZ: Float = size.z >= 0.20 ? (0.10 - size.z) / 2.0 : -(size.z - 0.01) / 2.0
                let shape = ShapeResource.generateBox(size: size).offsetBy(translation: [0, 0, offsetZ])
                existing.components.set(CollisionComponent(shapes: [shape]))
                existing.components.set(InputTargetComponent())
            } else {
                existing.components.remove(CollisionComponent.self)
                existing.components.remove(InputTargetComponent.self)
            }
            
            existing.cachedConfig = EntityCachedConfig(color: color, collisionSize: collisionSize)
            return existing
        }
        
        var material = SimpleMaterial(color: color, isMetallic: isMetallic)
        if let r = glassRoughness {
            material.roughness = .init(floatLiteral: r)
            material.metallic = 0.8
        }
        let entity = ModelEntity(mesh: meshFactory(), materials: [material])
        entity.name = id
        entity.position = position
        if let size = collisionSize {
            let offsetZ: Float = size.z >= 0.20 ? (0.10 - size.z) / 2.0 : -(size.z - 0.01) / 2.0
            let shape = ShapeResource.generateBox(size: size).offsetBy(translation: [0, 0, offsetZ])
            entity.components.set(CollisionComponent(shapes: [shape]))
            entity.components.set(InputTargetComponent())
        }
        entity.cachedConfig = EntityCachedConfig(color: color, collisionSize: collisionSize)
        setup?(entity)
        parent.addChild(entity)
        return entity
    }

    private func getLogicalSize(for panel: PanelModel.PanelInfo) -> SIMD2<Float> {
        let baseWidth: Float
        switch panel.id {
        case "Input", "Explore": baseWidth = 0.50
        case "Whack", "Calc", "NBack": baseWidth = 0.38
        case "Notes": baseWidth = 0.28
        default: baseWidth = 0.38
        }
        let baseHeight = baseWidth / panel.aspectRatio
        return SIMD2<Float>(baseWidth, baseHeight)
    }

    private func createLineEntity(from start: SIMD3<Float>, to end: SIMD3<Float>, thickness: Float, color: UIColor) -> ModelEntity {
        let length = distance(start, end)
        let mesh = MeshResource.generateBox(size: [thickness, thickness, length])
        let material = SimpleMaterial(color: color, isMetallic: false)
        let entity = ModelEntity(mesh: mesh, materials: [material])
        
        let direction = normalize(end - start)
        let midpoint = (start + end) / 2.0
        
        entity.position = midpoint
        let defaultForward = SIMD3<Float>(0, 0, 1)
        
        if length > 0.0001 {
            let axis = simd_cross(defaultForward, direction)
            let axisLength = simd_length(axis)
            if axisLength > 0.0001 {
                let angle = acos(simd_dot(defaultForward, direction))
                entity.orientation = simd_quatf(angle: angle, axis: axis / axisLength)
            } else if simd_dot(defaultForward, direction) < 0 {
                entity.orientation = simd_quatf(angle: .pi, axis: [0, 1, 0])
            }
        }
        
        return entity
    }

    private func updateOptimalZoneGuide() {
        let guideName = "OptimalZoneGuide"
        if let existing = sceneData.hudRoot.findEntity(named: guideName) {
            existing.removeFromParent()
        }
        
        guard panelModel.optimalZone.isGuideVisible else { return }
        
        let guideRoot = Entity()
        guideRoot.name = guideName
        sceneData.hudRoot.addChild(guideRoot)
        
        let config = panelModel.optimalZone
        
        func getPoint(yaw: Float, pitch: Float, dist: Float) -> SIMD3<Float> {
            let theta = yaw * Float.pi / 180.0
            let phi = pitch * Float.pi / 180.0
            let x = dist * sin(theta) * cos(phi)
            let y = dist * sin(phi)
            let z = -dist * cos(theta) * cos(phi)
            return SIMD3<Float>(x, y, z)
        }
        
        let segments = 12
        let mainColor = UIColor.cyan.withAlphaComponent(0.8)
        let subColor = UIColor.cyan.withAlphaComponent(0.3)
        let thickness: Float = 0.002
        
        // Draw arcs at minZ, baseZ, maxZ
        let distances = [(config.minZ, subColor), (config.baseZ, mainColor), (config.maxZ, subColor)]
        
        for (dist, color) in distances {
            // Horizontal arcs (top and bottom)
            for i in 0..<segments {
                let t1 = Float(i) / Float(segments)
                let t2 = Float(i + 1) / Float(segments)
                let yaw1 = config.minYaw + (config.maxYaw - config.minYaw) * t1
                let yaw2 = config.minYaw + (config.maxYaw - config.minYaw) * t2
                
                let p1 = getPoint(yaw: yaw1, pitch: config.maxPitch, dist: dist)
                let p2 = getPoint(yaw: yaw2, pitch: config.maxPitch, dist: dist)
                guideRoot.addChild(createLineEntity(from: p1, to: p2, thickness: thickness, color: color))
                
                let p3 = getPoint(yaw: yaw1, pitch: config.minPitch, dist: dist)
                let p4 = getPoint(yaw: yaw2, pitch: config.minPitch, dist: dist)
                guideRoot.addChild(createLineEntity(from: p3, to: p4, thickness: thickness, color: color))
            }
            // Vertical arcs (left and right)
            for i in 0..<segments {
                let t1 = Float(i) / Float(segments)
                let t2 = Float(i + 1) / Float(segments)
                let pitch1 = config.minPitch + (config.maxPitch - config.minPitch) * t1
                let pitch2 = config.minPitch + (config.maxPitch - config.minPitch) * t2
                
                let p1 = getPoint(yaw: config.minYaw, pitch: pitch1, dist: dist)
                let p2 = getPoint(yaw: config.minYaw, pitch: pitch2, dist: dist)
                guideRoot.addChild(createLineEntity(from: p1, to: p2, thickness: thickness, color: color))
                
                let p3 = getPoint(yaw: config.maxYaw, pitch: pitch1, dist: dist)
                let p4 = getPoint(yaw: config.maxYaw, pitch: pitch2, dist: dist)
                guideRoot.addChild(createLineEntity(from: p3, to: p4, thickness: thickness, color: color))
            }
        }
        
        // Connecting lines (corners) from minZ to maxZ
        let corners = [
            (config.minYaw, config.maxPitch),
            (config.maxYaw, config.maxPitch),
            (config.minYaw, config.minPitch),
            (config.maxYaw, config.minPitch)
        ]
        for (y, p) in corners {
            let pStart = getPoint(yaw: y, pitch: p, dist: config.minZ)
            let pEnd = getPoint(yaw: y, pitch: p, dist: config.maxZ)
            guideRoot.addChild(createLineEntity(from: pStart, to: pEnd, thickness: thickness, color: subColor))
        }
        
        // Center Crosshair
        let center = getPoint(yaw: config.baseYaw, pitch: config.basePitch, dist: config.baseZ)
        let chH1 = getPoint(yaw: config.baseYaw - 2.0, pitch: config.basePitch, dist: config.baseZ)
        let chH2 = getPoint(yaw: config.baseYaw + 2.0, pitch: config.basePitch, dist: config.baseZ)
        let chV1 = getPoint(yaw: config.baseYaw, pitch: config.basePitch - 2.0, dist: config.baseZ)
        let chV2 = getPoint(yaw: config.baseYaw, pitch: config.basePitch + 2.0, dist: config.baseZ)
        guideRoot.addChild(createLineEntity(from: chH1, to: chH2, thickness: thickness * 1.5, color: .yellow))
        guideRoot.addChild(createLineEntity(from: chV1, to: chV2, thickness: thickness * 1.5, color: .yellow))
    }

    func updateHUDPanels() {
        guard panelModel.hudPanelsAreShown else {
            for entity in sceneData.hudPanelEntities.values {
                entity.removeFromParent()
            }
            sceneData.hudPanelEntities.removeAll()
            sceneData.hudContentRoots.removeAll()
            return
        }

        let visiblePanels = panelModel.panels.filter(\.isVisible)
        let visibleIDs = Set(visiblePanels.map(\.id))

        let keysToRemove = sceneData.hudPanelEntities.keys.filter { !visibleIDs.contains($0) }
        for id in keysToRemove {
            sceneData.hudPanelEntities[id]?.removeFromParent()
            sceneData.hudPanelEntities.removeValue(forKey: id)
            sceneData.hudContentRoots.removeValue(forKey: id)
        }

        for panel in visiblePanels {
            let panelSize = panel.renderSize
            let logicalSize = getLogicalSize(for: panel)
            let uniformScale = min(panelSize.x / logicalSize.x, panelSize.y / logicalSize.y)

            let panelEntity: ModelEntity
            if let existing = sceneData.hudPanelEntities[panel.id] {
                panelEntity = existing
            } else {
                let created = ModelEntity()
                created.name = panel.id
                sceneData.hudRoot.addChild(created)

                let contentRoot = Entity()
                contentRoot.name = "\(panel.id).content"
                created.addChild(contentRoot)
                sceneData.hudPanelEntities[panel.id] = created
                sceneData.hudContentRoots[panel.id] = contentRoot
                panelEntity = created
            }

            let bgID = "Background_\(panelSize.x)_\(panelSize.y)"
            let borderThickness: Float = 0.0005
            let borderZ: Float = 0.0005 // Put slightly in front of background plane
            let opaqueColor = UIColor(panel.color).withAlphaComponent(1.0)
            
            let borderTopID = "BorderTop_\(panelSize.x)_\(panelSize.y)"
            let borderBottomID = "BorderBottom_\(panelSize.x)_\(panelSize.y)"
            let borderLeftID = "BorderLeft_\(panelSize.x)_\(panelSize.y)"
            let borderRightID = "BorderRight_\(panelSize.x)_\(panelSize.y)"

            for child in panelEntity.children {
                if child.name.hasPrefix("Background_") && child.name != bgID {
                    child.removeFromParent()
                }
                if child.name.hasPrefix("BorderTop_") && child.name != borderTopID {
                    child.removeFromParent()
                }
                if child.name.hasPrefix("BorderBottom_") && child.name != borderBottomID {
                    child.removeFromParent()
                }
                if child.name.hasPrefix("BorderLeft_") && child.name != borderLeftID {
                    child.removeFromParent()
                }
                if child.name.hasPrefix("BorderRight_") && child.name != borderRightID {
                    child.removeFromParent()
                }
            }

            _ = addOrUpdateModelEntity(
                id: bgID,
                meshFactory: { .generatePlane(width: panelSize.x, height: panelSize.y) },
                color: panel.useGlassmorphism ? UIColor(white: 1.0, alpha: 0.15) : UIColor(panel.color).withAlphaComponent(panel.opacity),
                glassRoughness: panel.useGlassmorphism ? panel.glassRoughness : nil,
                position: .zero,
                collisionSize: nil,
                parent: panelEntity
            )

            // Top Border
            _ = addOrUpdateModelEntity(
                id: borderTopID,
                meshFactory: { .generatePlane(width: panelSize.x, height: borderThickness) },
                color: opaqueColor,
                position: SIMD3<Float>(0, panelSize.y / 2 - borderThickness / 2, borderZ),
                collisionSize: nil,
                parent: panelEntity
            )

            // Bottom Border
            _ = addOrUpdateModelEntity(
                id: borderBottomID,
                meshFactory: { .generatePlane(width: panelSize.x, height: borderThickness) },
                color: opaqueColor,
                position: SIMD3<Float>(0, -panelSize.y / 2 + borderThickness / 2, borderZ),
                collisionSize: nil,
                parent: panelEntity
            )

            // Left Border
            _ = addOrUpdateModelEntity(
                id: borderLeftID,
                meshFactory: { .generatePlane(width: borderThickness, height: panelSize.y - 2 * borderThickness) },
                color: opaqueColor,
                position: SIMD3<Float>(-panelSize.x / 2 + borderThickness / 2, 0, borderZ),
                collisionSize: nil,
                parent: panelEntity
            )

            // Right Border
            _ = addOrUpdateModelEntity(
                id: borderRightID,
                meshFactory: { .generatePlane(width: borderThickness, height: panelSize.y - 2 * borderThickness) },
                color: opaqueColor,
                position: SIMD3<Float>(panelSize.x / 2 - borderThickness / 2, 0, borderZ),
                collisionSize: nil,
                parent: panelEntity
            )

            let panelLocalPosition = panel.worldPosition
            if panelEntity.position != panelLocalPosition {
                panelEntity.position = panelLocalPosition
            }

            guard let contentRoot = sceneData.hudContentRoots[panel.id] else { continue }
            let targetScale = SIMD3<Float>(repeating: uniformScale)
            if contentRoot.scale != targetScale {
                contentRoot.scale = targetScale
            }

            switch panel.id {
            case "Whack":
                addArcadeContents(on: panel, parent: contentRoot)
            case "Calc":
                addArithmeticContents(on: panel, parent: contentRoot)
            case "Input":
                addTextEntryContents(on: panel, parent: contentRoot)
            case "Explore":
                addExploreContents(on: panel, parent: contentRoot)
            case "NBack":
                addNBackContents(on: panel, parent: contentRoot)
            default:
                addInfoContents(on: panel, parent: contentRoot)
            }
        }
    }

    // --- Pedestrian movement/avoidance logic ---
    private func updatePedestrianAvoidanceAndMovement() {
        for i in sceneData.movingEntities.indices {
            var moving = sceneData.movingEntities[i]

            // --- Smooth overtake/avoidance decision ---
            // Smooth overtake behavior: once an overtake side is chosen, keep it for a while
            // instead of switching left/right every frame.
            let overtakeLockFrames = 75
            let directionSwitchCooldownFrames = 45
            let desiredOvertakeOffset: Float = moving.personalRadius * 2.4 + 0.22
            let maxOvertakeOffset = max(0.0, Float(panelModel.peopleHorizontalRange) - moving.personalRadius - 0.20)

            let currentSide: Float = moving.currentAvoidanceDir == 0 ? 0 : Float(moving.currentAvoidanceDir)
            let leftCandidate = max(-maxOvertakeOffset, moving.preferredCruiseOffset - desiredOvertakeOffset)
            let rightCandidate = min(maxOvertakeOffset, moving.preferredCruiseOffset + desiredOvertakeOffset)

            if moving.overtakeFrameCount > 0 {
                moving.overtakeFrameCount -= 1
            }
            if moving.directionChangeCooldown > 0 {
                moving.directionChangeCooldown -= 1
            }

            let shouldChooseNewSide = moving.currentAvoidanceDir == 0 || (moving.overtakeFrameCount <= 0 && moving.directionChangeCooldown <= 0)
            if shouldChooseNewSide {
                let currentX = moving.lateralOffset
                let leftClearance = abs(currentX - leftCandidate)
                let rightClearance = abs(rightCandidate - currentX)
                let newDir: Float = rightClearance >= leftClearance ? 1.0 : -1.0
                moving.currentAvoidanceDir = newDir
                moving.overtakeFrameCount = overtakeLockFrames
                moving.directionChangeCooldown = directionSwitchCooldownFrames
            }

            let lockedSide = moving.currentAvoidanceDir >= 0 ? Float(1) : Float(-1)
            let lockedTarget = moving.preferredCruiseOffset + lockedSide * desiredOvertakeOffset
            moving.targetLateralOffset = min(maxOvertakeOffset, max(-maxOvertakeOffset, lockedTarget))

            // --- Smooth lateral offset update ---
            let lateralDelta = moving.targetLateralOffset - moving.lateralOffset
            let maxLateralStep = max(0.0025, moving.currentSpeed * 0.85)
            let smoothStep = max(-maxLateralStep, min(maxLateralStep, lateralDelta * 0.12))
            moving.lateralOffset += smoothStep

            // --- Return to cruise offset only after overtake lock expires ---
            // (Do not set currentAvoidanceDir to 0 immediately when obstacle is not detected;
            // only after overtakeFrameCount <= 0)
            if moving.overtakeFrameCount <= 0 && moving.currentAvoidanceDir != 0 {
                moving.currentAvoidanceDir = 0
                moving.directionChangeCooldown = 0
                moving.targetLateralOffset = moving.preferredCruiseOffset
            }

            sceneData.movingEntities[i] = moving
        }
    }

    /// タスク開始前および終了後の共通操作UIを構築する
    private func addPreTaskControls(on panel: PanelModel.PanelInfo, parent: Entity) {
        let lSize = getLogicalSize(for: panel)
        var currentPreTaskIDs = Set<String>()
        
        // 1. ステータス表示 (衝突回数 または 準備完了)
        let count = experimentManager.collisionCount
        let statusText = count > 0 ? "衝突回数: \(count)回" : "準備完了"
        let statusEntity = addOrUpdateTextEntity(
            id: "PreStatus",
            text: statusText,
            fontSize: 0.016,
            color: UIColor(panel.textColor),
            position: [lSize.x / 2 - 0.20, lSize.y / 2 - 0.07, 0.004],
            parent: parent
        )
        if let s = statusEntity { currentPreTaskIDs.insert(s.name) }
        
        // 2. STARTボタン (右側の真ん中)
        let startButtonId = "\(panel.id).StartTask"
        let startButton = addOrUpdateModelEntity(
            id: startButtonId,
            meshFactory: { .generatePlane(width: 0.14, height: 0.045) },
            color: .systemBlue.withAlphaComponent(0.4),
            position: [lSize.x / 2 - 0.12, lSize.y / 2 - 0.13, 0.006],
            collisionSize: [0.14, 0.045, defaultCollisionZ],
            parent: parent
        )
        currentPreTaskIDs.insert(startButton.name)
        
        let startText = addOrUpdateTextEntity(
            id: "PreStartL",
            text: "START",
            fontSize: 0.018,
            color: UIColor(panel.textColor),
            position: [-0.03, -0.008, 0.001],
            parent: startButton
        )
        if let st = startText { currentPreTaskIDs.insert(st.name) }
        
        // 3. 実験条件 (Condition) コントローラー (左下)
        let condTextY = -lSize.y / 2 + 0.09
        let condBtnY = -lSize.y / 2 + 0.04
        
        let conditionLabel = "条件: \(experimentManager.conditionIDText)"
        let condTextEntity = addOrUpdateTextEntity(
            id: "PreCondText",
            text: conditionLabel,
            fontSize: 0.015,
            color: UIColor(panel.textColor),
            position: [-lSize.x / 2 + 0.03, condTextY, 0.004],
            parent: parent
        )
        if let c = condTextEntity { currentPreTaskIDs.insert(c.name) }
        
        // デクリメントボタン "-"
        let decButton = addOrUpdateModelEntity(
            id: "Condition.Decrement",
            meshFactory: { .generatePlane(width: 0.04, height: 0.03) },
            color: UIColor(panel.textColor).withAlphaComponent(0.20),
            position: [-lSize.x / 2 + 0.05, condBtnY, 0.006],
            collisionSize: [0.04, 0.03, defaultCollisionZ],
            parent: parent
        )
        currentPreTaskIDs.insert(decButton.name)
        let decText = addOrUpdateTextEntity(id: "PreDecText", text: "-", fontSize: 0.018, color: UIColor(panel.textColor), position: [-0.005, -0.008, 0.001], parent: decButton)
        if let dt = decText { currentPreTaskIDs.insert(dt.name) }
        
        // インクリメントボタン "+"
        let incButton = addOrUpdateModelEntity(
            id: "Condition.Increment",
            meshFactory: { .generatePlane(width: 0.04, height: 0.03) },
            color: UIColor(panel.textColor).withAlphaComponent(0.20),
            position: [-lSize.x / 2 + 0.11, condBtnY, 0.006],
            collisionSize: [0.04, 0.03, defaultCollisionZ],
            parent: parent
        )
        currentPreTaskIDs.insert(incButton.name)
        let incText = addOrUpdateTextEntity(id: "PreIncText", text: "+", fontSize: 0.018, color: UIColor(panel.textColor), position: [-0.005, -0.008, 0.001], parent: incButton)
        if let it = incText { currentPreTaskIDs.insert(it.name) }
        
        // 4. 混雑条件 (LOS) コントローラー (右下)
        let crowdTextY = -lSize.y / 2 + 0.09
        let crowdBtnY = -lSize.y / 2 + 0.04
        
        let crowdLabelStr: String
        let iv = panelModel.peopleSpawnInterval
        if abs(iv - panelModel.tA) < 0.1 { crowdLabelStr = "混雑: LOS A" }
        else if abs(iv - panelModel.tB) < 0.1 { crowdLabelStr = "混雑: LOS B" }
        else if abs(iv - panelModel.tC) < 0.1 { crowdLabelStr = "混雑: LOS C" }
        else if abs(iv - panelModel.tD) < 0.1 { crowdLabelStr = "混雑: LOS D" }
        else if abs(iv - panelModel.tE) < 0.1 { crowdLabelStr = "混雑: LOS E" }
        else if abs(iv - panelModel.tF) < 0.1 { crowdLabelStr = "混雑: LOS F" }
        else { crowdLabelStr = "混雑: Custom" }
        
        let crowdTextEntity = addOrUpdateTextEntity(
            id: "PreCrowdText",
            text: crowdLabelStr,
            fontSize: 0.015,
            color: UIColor(panel.textColor),
            position: [lSize.x / 2 - 0.18, crowdTextY, 0.004],
            parent: parent
        )
        if let cr = crowdTextEntity { currentPreTaskIDs.insert(cr.name) }
        
        // 混雑度切り替えボタン "TOGGLE"
        let crowdBtn = addOrUpdateModelEntity(
            id: "Crowd.Toggle",
            meshFactory: { .generatePlane(width: 0.10, height: 0.03) },
            color: UIColor(panel.textColor).withAlphaComponent(0.20),
            position: [lSize.x / 2 - 0.09, crowdBtnY, 0.006],
            collisionSize: [0.10, 0.03, defaultCollisionZ],
            parent: parent
        )
        currentPreTaskIDs.insert(crowdBtn.name)
        let crowdBtnText = addOrUpdateTextEntity(id: "PreCrowdBtnText", text: "TOGGLE", fontSize: 0.013, color: UIColor(panel.textColor), position: [-0.03, -0.006, 0.001], parent: crowdBtn)
        if let cbt = crowdBtnText { currentPreTaskIDs.insert(cbt.name) }
        
        // 5. CSV保存ボタン (実験後の finished 状態のときのみ表示)
        if experimentManager.state == .finished {
            let csvBtnColor = experimentManager.isCSVSaved ? UIColor.systemGreen.withAlphaComponent(0.6) : UIColor.systemPurple.withAlphaComponent(0.5)
            let csvBtnLabel = experimentManager.isCSVSaved ? "SAVED ✔" : "SAVE CSV"
            let csvBtnWidth: Float = 0.14
            let csvBtnXOffset = -csvBtnWidth / 2 + 0.02
            
            let csvBtn = addOrUpdateModelEntity(
                id: "Summary.Save",
                meshFactory: { .generatePlane(width: csvBtnWidth, height: 0.035) },
                color: csvBtnColor,
                position: [lSize.x / 2 - 0.12, lSize.y / 2 - 0.21, 0.006],
                collisionSize: [csvBtnWidth, 0.035, defaultCollisionZ],
                parent: parent
            )
            currentPreTaskIDs.insert(csvBtn.name)
            
            let csvText = addOrUpdateTextEntity(
                id: "PreCSVText",
                text: csvBtnLabel,
                fontSize: 0.015,
                color: UIColor(panel.textColor),
                position: [csvBtnXOffset, -0.007, 0.001],
                parent: csvBtn
            )
            if let ct = csvText { currentPreTaskIDs.insert(ct.name) }
        }
    }

    /// Whack-a-mole（モグラ叩き）タスクの表示内容を構築
    private func addArcadeContents(on panel: PanelModel.PanelInfo, parent: Entity) {
        let lSize = getLogicalSize(for: panel)
        var currentTargetIDs = Set<String>()

        // 固有テキスト（Title, Rule）は状態に関わらず常時左側に表示
        addOrUpdateTextEntity(id: "Title", text: "Whack", fontSize: 0.045, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.04, 0.004], parent: parent)
        addOrUpdateTextEntity(id: "Rule", text: experimentManager.arcadeRuleDescription, fontSize: 0.016, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.14, 0.004], parent: parent)

        if experimentManager.state != .running {
            // タスク開始前はタスク中の表示（Score, Comboなど）をクリーンアップ
            for id in ["Score", "Combo"] {
                parent.findEntity(named: "TextEntity_\(id)")?.removeFromParent()
            }
            addPreTaskControls(on: panel, parent: parent)
        } else {
            // Pre-task用のUI要素を一括でクリーンアップ
            let preTaskPrefixes = ["TextEntity_Pre", "Condition.", "Crowd.", "Summary.Save", "Whack.StartTask"]
            for child in parent.children {
                if preTaskPrefixes.contains(where: { child.name.hasPrefix($0) }) {
                    child.removeFromParent()
                }
            }

            addOrUpdateTextEntity(id: "Score", text: "Score \(experimentManager.arcadeScore)", fontSize: 0.018, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.08, 0.004], parent: parent)
            addOrUpdateTextEntity(id: "Combo", text: "Combo \(experimentManager.comboCount)", fontSize: 0.018, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.11, 0.004], parent: parent)

            for target in experimentManager.displayedTargets {
                let entityName = "AttentionTarget.\(target.id.uuidString)"
                currentTargetIDs.insert(entityName)

                let targetSize: Float = 0.035
                let pos = SIMD3<Float>(Float(target.position.x), Float(target.position.y), 0.006)

                _ = addOrUpdateModelEntity(
                    id: entityName,
                    meshFactory: { .generateSphere(radius: targetSize / 2) },
                    color: target.color.uiColor.withAlphaComponent(0.94),
                    position: pos,
                    collisionSize: [targetSize, targetSize, defaultCollisionZ],
                    parent: parent
                )
            }

            if let hit = experimentManager.selectiveAttentionTaskManager.lastHitPosition {
                let hitName = "HitEffect"
                currentTargetIDs.insert(hitName)
                let hitPos = SIMD3<Float>(Float(hit.x), Float(hit.y), 0.01)
                let effectEntity = addOrUpdateModelEntity(
                    id: hitName,
                    meshFactory: { .generateSphere(radius: 0.03) },
                    color: .systemYellow.withAlphaComponent(0.8),
                    position: hitPos,
                    parent: parent
                )
                if let e = addOrUpdateTextEntity(id: "HitText", text: "Hit!", fontSize: 0.025, color: .systemRed, position: [-0.02, 0.02, 0.005], parent: effectEntity) { currentTargetIDs.insert(e.name) }
            }
        }

        for child in parent.children {
            let n = child.name
            if (n.hasPrefix("AttentionTarget.") || n == "HitEffect") && !currentTargetIDs.contains(n) {
                child.removeFromParent()
            }
        }
    }

    /// 計算タスクの表示内容を構築
    private func addArithmeticContents(on panel: PanelModel.PanelInfo, parent: Entity) {
        let lSize = getLogicalSize(for: panel)
        var currentButtonIDs = Set<String>()

        // 固有テキスト（Title, Subtitle）は状態に関わらず常時左側に表示
        addOrUpdateTextEntity(id: "Title", text: "Calc", fontSize: 0.045, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.04, 0.004], parent: parent)
        addOrUpdateTextEntity(id: "Subtitle", text: "4択に回答", fontSize: 0.018, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.08, 0.004], parent: parent)

        if experimentManager.state != .running {
            // タスク開始前はタスク中の表示（Prompt, Result, Statusなど）をクリーンアップ
            for id in ["Prompt", "Result", "Status"] {
                parent.findEntity(named: "TextEntity_\(id)")?.removeFromParent()
            }
            addPreTaskControls(on: panel, parent: parent)
        } else {
            // Pre-task用のUI要素を一括でクリーンアップ
            let preTaskPrefixes = ["TextEntity_Pre", "Condition.", "Crowd.", "Summary.Save", "Calc.StartTask"]
            for child in parent.children {
                if preTaskPrefixes.contains(where: { child.name.hasPrefix($0) }) {
                    child.removeFromParent()
                }
            }

            if let question = experimentManager.displayedQuestion {
                addOrUpdateTextEntity(id: "Status", text: "", fontSize: 0.001, color: .clear, position: .zero, parent: parent)
                addOrUpdateTextEntity(id: "Prompt", text: question.prompt, fontSize: 0.038, color: UIColor(panel.textColor), position: [-0.08, 0.01, 0.004], parent: parent)
                addOrUpdateTextEntity(id: "Result", text: "", fontSize: 0.001, color: .clear, position: .zero, parent: parent)
            
                let optionOffsets: [SIMD3<Float>] = [
                    SIMD3<Float>(-0.09, -0.03, 0.006),
                    SIMD3<Float>(0.09, -0.03, 0.006),
                    SIMD3<Float>(-0.09, -0.08, 0.006),
                    SIMD3<Float>(0.09, -0.08, 0.006)
                ]

                for (index, option) in question.options.enumerated() where index < optionOffsets.count {
                    let entityName = "ArithmeticOption.\(question.id.uuidString).\(option)"
                    currentButtonIDs.insert(entityName)
                    let button = addOrUpdateModelEntity(
                        id: entityName,
                        meshFactory: { .generatePlane(width: 0.09, height: 0.04) },
                        color: UIColor(panel.textColor).withAlphaComponent(0.20),
                        position: optionOffsets[index],
                        collisionSize: [0.09, 0.04, defaultCollisionZ],
                        parent: parent
                    )
                    addOrUpdateTextEntity(id: "Label", text: "\(option)", fontSize: 0.028, color: UIColor(panel.textColor), position: SIMD3<Float>(-0.015, -0.010, 0.001), parent: button)
                }
            } else {
                addOrUpdateTextEntity(id: "Prompt", text: "", fontSize: 0.001, color: .clear, position: .zero, parent: parent)
                if let result = experimentManager.arithmeticTaskManager.lastResult {
                    let resultColor: UIColor = result ? .systemGreen : .systemRed
                    addOrUpdateTextEntity(id: "Result", text: result ? "正解！" : "不正解...", fontSize: 0.032, color: resultColor, position: [-0.045, 0.03, 0.004], parent: parent)
                    addOrUpdateTextEntity(id: "Status", text: "", fontSize: 0.001, color: .clear, position: .zero, parent: parent)
                } else {
                    addOrUpdateTextEntity(id: "Status", text: "次の問題を準備中...", fontSize: 0.022, color: UIColor(panel.textColor), position: [-0.11, -0.01, 0.004], parent: parent)
                    addOrUpdateTextEntity(id: "Result", text: "", fontSize: 0.001, color: .clear, position: .zero, parent: parent)
                }
            }
        }

        for child in parent.children {
            if child.name.hasPrefix("ArithmeticOption.") && !currentButtonIDs.contains(child.name) {
                child.removeFromParent()
            }
        }
    }

    /// テキスト入力タスクの表示内容を構築
    private func addTextEntryContents(on panel: PanelModel.PanelInfo, parent: Entity) {
        let lSize = getLogicalSize(for: panel)
        var currentIDs = Set<String>()

        // 固有テキスト（Title）は状態に関わらず常時左側に表示。文字入力のSubtitleはちらつき防止およびユーザー要望により削除
        addOrUpdateTextEntity(id: "Title", text: "Text", fontSize: 0.045, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.04, 0.004], parent: parent)

        if experimentManager.state != .running {
            // タスク開始前はタスク中の表示をクリーンアップ
            for id in ["TargetL", "TargetV", "InputV", "Result", "Status", "EndL", "DelL", "NextL", "Subtitle"] {
                parent.findEntity(named: "TextEntity_\(id)")?.removeFromParent()
            }
            addPreTaskControls(on: panel, parent: parent)
        } else {
            // Pre-task用のUI要素を一括でクリーンアップ
            let preTaskPrefixes = ["TextEntity_Pre", "Condition.", "Crowd.", "Summary.Save", "Input.StartTask"]
            for child in parent.children {
                if preTaskPrefixes.contains(where: { child.name.hasPrefix($0) }) {
                    child.removeFromParent()
                }
            }

            if let prompt = experimentManager.textEntryPrompt {
                let e1 = addOrUpdateTextEntity(id: "TargetL", text: "TARGET", fontSize: 0.012, color: .systemGray, position: [-lSize.x / 2 + 0.04, lSize.y * 0.35, 0.004], parent: parent)
                let e2 = addOrUpdateTextEntity(id: "TargetV", text: prompt.targetText, fontSize: 0.042, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.04, lSize.y * 0.20, 0.004], parent: parent)
                let e3 = addOrUpdateTextEntity(id: "InputV", text: "> \(prompt.enteredText)", fontSize: 0.032, color: .systemYellow, position: [-lSize.x / 2 + 0.04, lSize.y * 0.05, 0.004], parent: parent)
                if let e = e1 { currentIDs.insert(e.name) }
                if let e = e2 { currentIDs.insert(e.name) }
                if let e = e3 { currentIDs.insert(e.name) }

                let endButton = addOrUpdateModelEntity(id: "TextEntry.End", meshFactory: { .generatePlane(width: 0.08, height: 0.035) }, color: .systemRed.withAlphaComponent(0.4), position: [lSize.x / 2 - 0.05, lSize.y / 2 - 0.03, 0.006], collisionSize: [0.088, 0.043, defaultCollisionZ], parent: parent)
                currentIDs.insert(endButton.name)
                if let e = addOrUpdateTextEntity(id: "EndL", text: "END", fontSize: 0.018, color: UIColor(panel.textColor), position: SIMD3<Float>(-0.018, -0.008, 0.001), parent: endButton) {
                    currentIDs.insert(e.name)
                }

                let rows: [[String]] = [
                    ["Q","W","E","R","T","Y","U","I","O","P"],
                    ["A","S","D","F","G","H","J","K","L"],
                    ["Z","X","C","V","B","N","M"]
                ]
                let kbScale: Float = min(1.0, (lSize.x - 0.04) / 0.445)
                let spacingX: Float = 0.045 * kbScale
                let isPortrait = lSize.y > lSize.x
                let spacingY: Float = (isPortrait ? 0.055 : 0.034) * kbScale
                let kbTopY: Float = isPortrait ? -0.05 : -0.01

                for (rowIndex, row) in rows.enumerated() {
                    let startX = -Float(row.count - 1) * spacingX / 2
                    let y = kbTopY - Float(rowIndex) * spacingY
                    for (colIndex, key) in row.enumerated() {
                        let entityName = "TextEntryKey.\(key)"
                        currentIDs.insert(entityName)
                        let button = addOrUpdateModelEntity(
                            id: entityName,
                            meshFactory: { .generatePlane(width: 0.04 * kbScale, height: 0.03 * kbScale) },
                            color: UIColor(panel.textColor).withAlphaComponent(0.12),
                            position: [startX + Float(colIndex) * spacingX, y, 0.006],
                            collisionSize: [0.044 * kbScale, 0.034 * kbScale, defaultCollisionZ],
                            parent: parent
                        )
                        currentIDs.insert(button.name)
                        if let e = addOrUpdateTextEntity(id: "Label", text: key, fontSize: 0.018 * kbScale, color: UIColor(panel.textColor), position: SIMD3<Float>(-0.006 * kbScale, -0.008 * kbScale, 0.001), parent: button) {
                            currentIDs.insert(e.name)
                        }
                    }
                }
                
                let delX = (Float(rows[2].count - 1) * spacingX) / 2 + spacingX * 1.15
                let delButton = addOrUpdateModelEntity(id: "TextEntry.Delete", meshFactory: { .generatePlane(width: 0.055 * kbScale, height: 0.03 * kbScale) }, color: .systemRed.withAlphaComponent(0.25), position: [delX, kbTopY - 2.0 * spacingY, 0.006], collisionSize: [0.063 * kbScale, 0.038 * kbScale, defaultCollisionZ], parent: parent)
                currentIDs.insert(delButton.name)
                if let e = addOrUpdateTextEntity(id: "DelL", text: "DEL", fontSize: 0.015 * kbScale, color: UIColor(panel.textColor), position: SIMD3<Float>(-0.013 * kbScale, -0.006 * kbScale, 0.001), parent: delButton) {
                    currentIDs.insert(e.name)
                }

                let isReady = experimentManager.textEntryTaskManager.isReadyToSubmit
                let nextColor = isReady ? UIColor.systemBlue.withAlphaComponent(0.25) : UIColor.systemGray.withAlphaComponent(0.25)
                let nextTextColor = isReady ? UIColor.white : UIColor.lightGray

                let nextButton = addOrUpdateModelEntity(
                    id: "TextEntry.Next",
                    meshFactory: { .generatePlane(width: 0.10 * kbScale, height: 0.035 * kbScale) },
                    color: nextColor,
                    position: [0, kbTopY - 3.1 * spacingY, 0.006],
                    collisionSize: isReady ? [0.108 * kbScale, 0.043 * kbScale, defaultCollisionZ] : nil,
                    parent: parent
                )
                currentIDs.insert(nextButton.name)
                if let e = addOrUpdateTextEntity(id: "NextL", text: "NEXT", fontSize: 0.018 * kbScale, color: nextTextColor, position: SIMD3<Float>(-0.022 * kbScale, -0.008 * kbScale, 0.001), parent: nextButton) {
                    currentIDs.insert(e.name)
                }
            } else {
                if let result = experimentManager.textEntryTaskManager.lastResult {
                    let e = addOrUpdateTextEntity(id: "Result", text: result ? "正解！" : "不正解...", fontSize: 0.045, color: result ? .systemGreen : .systemRed, position: [-0.06, 0.02, 0.004], parent: parent)
                    if let e = e { currentIDs.insert(e.name) }
                } else {
                    let e = addOrUpdateTextEntity(id: "Status", text: "次の語を準備中...", fontSize: 0.022, color: UIColor(panel.textColor), position: [-0.12, -0.01, 0.004], parent: parent)
                    if let e = e { currentIDs.insert(e.name) }
                }
            }
        }

        for child in parent.children {
            let n = child.name
            if n != "TextEntity_Title" && !currentIDs.contains(n) && !n.hasPrefix("TextEntity_Pre") && !n.hasPrefix("Condition.") && !n.hasPrefix("Crowd.") && !n.hasPrefix("Summary.Save") && !n.hasPrefix("Input.StartTask") {
                child.removeFromParent()
            }
        }
    }

    private func addExploreContents(on panel: PanelModel.PanelInfo, parent: Entity) {
        let lSize = getLogicalSize(for: panel)
        var currentEntityIDs = Set<String>()

        // 固有テキスト（Title, Subtitle）は状態に関わらず常時左側に表示
        addOrUpdateTextEntity(id: "Title", text: "Explore", fontSize: 0.035, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.03, 0.004], parent: parent)
        addOrUpdateTextEntity(id: "Subtitle", text: "ページ探索", fontSize: 0.018, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.065, 0.004], parent: parent)

        if experimentManager.state != .running {
            // タスク開始前はタスク中の表示（GoalL, GoalV, TitleV, Statusなど）をクリーンアップ
            for id in ["GoalL", "GoalV", "TitleV", "Status"] {
                parent.findEntity(named: "TextEntity_\(id)")?.removeFromParent()
            }
            addPreTaskControls(on: panel, parent: parent)
        } else {
            // Pre-task用のUI要素を一括でクリーンアップ
            let preTaskPrefixes = ["TextEntity_Pre", "Condition.", "Crowd.", "Summary.Save", "Explore.StartTask"]
            for child in parent.children {
                if preTaskPrefixes.contains(where: { child.name.hasPrefix($0) }) {
                    child.removeFromParent()
                }
            }

            if let challenge = experimentManager.pageExplorationChallenge {
                addOrUpdateTextEntity(id: "GoalL", text: "GOAL", fontSize: 0.014, color: .systemYellow, position: [-lSize.x / 2 + 0.04, lSize.y / 2 - 0.06, 0.004], parent: parent)
                addOrUpdateTextEntity(id: "GoalV", text: challenge.targetTitle, fontSize: 0.022, color: .systemYellow, position: [-lSize.x / 2 + 0.10, lSize.y / 2 - 0.064, 0.004], parent: parent)
                addOrUpdateTextEntity(id: "TitleV", text: challenge.currentPage.title, fontSize: 0.020, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.04, lSize.y / 2 - 0.095, 0.004], parent: parent)

                // Simplification: Not full text rendering here for brevity, but maintaining structure
                addOrUpdateTextEntity(id: "Status", text: "ページを読み込み中...", fontSize: 0.02, color: UIColor(panel.textColor), position: [-0.12, -0.01, 0.004], parent: parent)
            }
        }
    }

    /// N-Backタスクの表示内容を構築
    private func addNBackContents(on panel: PanelModel.PanelInfo, parent: Entity) {
        let lSize = getLogicalSize(for: panel)
        var currentMarkers = Set<String>()

        // 固有テキスト（Title, Subtitle）は状態に関わらず常時左側に表示
        addOrUpdateTextEntity(id: "Title", text: "N-Back", fontSize: 0.05, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.05, 0.004], parent: parent)
        addOrUpdateTextEntity(id: "Subtitle", text: "\(experimentManager.nBackConfig.nValue)-back で色を回答", fontSize: 0.018, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.09, 0.004], parent: parent)

        if experimentManager.state != .running {
            // タスク開始前はタスク中の表示（Status, Resultなど）をクリーンアップ
            for id in ["Status", "Result"] {
                parent.findEntity(named: "TextEntity_\(id)")?.removeFromParent()
            }
            addPreTaskControls(on: panel, parent: parent)
        } else {
            // Pre-task用のUI要素を一括でクリーンアップ
            let preTaskPrefixes = ["TextEntity_Pre", "Condition.", "Crowd.", "Summary.Save", "NBack.StartTask"]
            for child in parent.children {
                if preTaskPrefixes.contains(where: { child.name.hasPrefix($0) }) {
                    child.removeFromParent()
                }
            }

            if let stimulus = experimentManager.currentNBackStimulus {
                addOrUpdateTextEntity(id: "Status", text: "", fontSize: 0.001, color: .clear, position: .zero, parent: parent)
                _ = addOrUpdateModelEntity(id: "NBackSphere", meshFactory: { .generateSphere(radius: 0.03) }, color: stimulus.color.uiColor, position: [0.0, 0.03, 0.012], parent: parent)
                currentMarkers.insert("NBackSphere")

                let nBackColors = NBackBallColor.allCases
                let spacing: Float = 0.045
                let startX = -Float(nBackColors.count - 1) * spacing / 2.0
                let canAnswer = experimentManager.nBackTaskManager.canAnswer
                let selectedColor = experimentManager.nBackTaskManager.selectedColor

                for (index, color) in nBackColors.enumerated() {
                    let isSelected = (selectedColor == color)
                    let alpha: CGFloat = !canAnswer ? 0.2 : (selectedColor == nil ? 1.0 : (isSelected ? 1.0 : 0.3))
                    let entityName = "NBack.Color.\(color.rawValue)_\(isSelected)_\(alpha)"
                    currentMarkers.insert(entityName)
                    _ = addOrUpdateModelEntity(id: entityName, meshFactory: { .generateSphere(radius: isSelected ? 0.022 : 0.018) }, color: color.uiColor.withAlphaComponent(alpha), position: [startX + Float(index) * spacing, -0.04, 0.010], collisionSize: [0.036, 0.036, defaultCollisionZ], parent: parent)
                }

                let nextButton = addOrUpdateModelEntity(id: "NBack.Next", meshFactory: { .generatePlane(width: 0.10, height: 0.035) }, color: .systemBlue.withAlphaComponent(0.3), position: [0, -0.09, 0.006], collisionSize: [0.10, 0.035, defaultCollisionZ], parent: parent)
                addOrUpdateTextEntity(id: "NextL", text: "NEXT", fontSize: 0.018, color: UIColor(panel.textColor), position: SIMD3<Float>(-0.022, -0.008, 0.001), parent: nextButton)
                currentMarkers.insert("NBack.Next")
            } else {
                if let lastResult = experimentManager.nBackTaskManager.lastResult {
                    addOrUpdateTextEntity(id: "Result", text: lastResult ? "正解！" : "不正解...", fontSize: 0.03, color: lastResult ? .systemGreen : .systemRed, position: [-0.045, 0.0, 0.004], parent: parent)
                } else {
                    addOrUpdateTextEntity(id: "Status", text: "次の色を準備中...", fontSize: 0.02, color: UIColor(panel.textColor), position: [-0.11, -0.01, 0.004], parent: parent)
                }
            }
        }

        for child in parent.children {
            if (child.name == "NBackSphere" || child.name.hasPrefix("NBack.Color.") || child.name == "NBack.Next") && !currentMarkers.contains(child.name) {
                child.removeFromParent()
            }
        }
    }

    private func addInfoContents(on panel: PanelModel.PanelInfo, parent: Entity) {
        let lSize = getLogicalSize(for: panel)
        addOrUpdateTextEntity(id: "Title", text: panel.id, fontSize: 0.05, color: UIColor(panel.textColor), position: [-lSize.x / 2 + 0.03, lSize.y / 2 - 0.05, 0.004], parent: parent)
        addOrUpdateTextEntity(id: "Subtitle", text: "予備パネル", fontSize: 0.022, color: UIColor(panel.textColor), position: [-0.06, -0.01, 0.004], parent: parent)
    }

    private func updateSpawnLineVisualization(isVisible: Bool) {
        if sceneData.spawnLineEntity == nil {
            let thickness: Float = 0.01
            let line = ModelEntity(mesh: .generateBox(size: [1.0, thickness, thickness]), materials: [SimpleMaterial(color: .white.withAlphaComponent(0.6), isMetallic: false)])
            line.name = "SpawnLinePreview"
            sceneData.spawnLineEntity = line
            sceneData.worldAnchor.addChild(line)
        }
        if sceneData.spawnStartMarker == nil {
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [SimpleMaterial(color: .systemGreen.withAlphaComponent(0.8), isMetallic: false)])
            marker.name = "SpawnStartPreview"
            sceneData.spawnStartMarker = marker
            sceneData.worldAnchor.addChild(marker)
        }
        if sceneData.spawnEndMarker == nil {
            let marker = ModelEntity(mesh: .generateSphere(radius: 0.02), materials: [SimpleMaterial(color: .systemRed.withAlphaComponent(0.8), isMetallic: false)])
            marker.name = "SpawnEndPreview"
            sceneData.spawnEndMarker = marker
            sceneData.worldAnchor.addChild(marker)
        }
        if sceneData.spawnStartUILabel == nil {
            let label = ModelEntity(mesh: .generateText("START", extrusionDepth: 0.001, font: .systemFont(ofSize: 0.03)), materials: [SimpleMaterial(color: .systemGreen, isMetallic: false)])
            label.name = "SpawnStartUILabel"
            sceneData.spawnStartUILabel = label
            sceneData.worldAnchor.addChild(label)
        }
        if sceneData.spawnEndUILabel == nil {
            let label = ModelEntity(mesh: .generateText("END", extrusionDepth: 0.001, font: .systemFont(ofSize: 0.03)), materials: [SimpleMaterial(color: .systemRed, isMetallic: false)])
            label.name = "SpawnEndUILabel"
            sceneData.spawnEndUILabel = label
            sceneData.worldAnchor.addChild(label)
        }

        sceneData.spawnLineEntity?.isEnabled = isVisible
        sceneData.spawnStartMarker?.isEnabled = isVisible
        sceneData.spawnEndMarker?.isEnabled = isVisible
        sceneData.spawnStartUILabel?.isEnabled = isVisible
        sceneData.spawnEndUILabel?.isEnabled = isVisible
        guard isVisible else { return }

        let startPos = spawnLineStartWorld // 被験者ゴール (30m先)
        let endPos = spawnLineEndWorld     // 被験者スタート (0m)

        // 表示位置を入れ替え：STARTはendPos（ユーザー開始位置）、ENDはstartPos（ユーザー終了位置）へ
        sceneData.spawnStartMarker?.position = endPos
        sceneData.spawnEndMarker?.position = startPos
        sceneData.spawnStartUILabel?.position = endPos + SIMD3<Float>(0, 0.06, 0)
        sceneData.spawnEndUILabel?.position = startPos + SIMD3<Float>(0, 0.06, 0)

        let faceHead = sceneData.headAnchor.position(relativeTo: nil)
        sceneData.spawnStartUILabel?.look(at: faceHead, from: sceneData.spawnStartUILabel!.position(relativeTo: nil), relativeTo: nil)
        sceneData.spawnEndUILabel?.look(at: faceHead, from: sceneData.spawnEndUILabel!.position(relativeTo: nil), relativeTo: nil)

        let dir = startPos - endPos
        let len = max(0.001, simd_length(dir))
        sceneData.spawnLineEntity?.position = (startPos + endPos) * 0.5
        sceneData.spawnLineEntity?.transform.rotation = simd_quatf(from: SIMD3<Float>(1, 0, 0), to: dir / len)
        sceneData.spawnLineEntity?.scale = SIMD3<Float>(len, 1.0, 1.0)
    }

    /// ランダムな歩行個体を生成してシーンに追加する（初期進捗度が指定された場合はその位置に配置）
    private func spawnRandomEntity(initialProgress: Float? = nil) -> Bool {
        let weightedNames = ["Man", "Man", "Man", "Man", "Woman", "Woman", "Woman", "Woman", "Man_phone", "Woman_phone"]
        guard let name = sceneData.randomGen.randomElement(weightedNames),
              let scale = modelScales[name],
              let template = sceneData.modelTemplates[name] else { return false }

        // 骨格アニメーションによるスケールリセットバグを防ぐため、親コンテナで物理スケールを適用
        let container = Entity()
        container.name = "PedestrianContainer_\(name)"

        let entity = template.clone(recursive: true)
        
        // RealityKit標準の衝突判定や入力を削除（独自の精密判定を行うため）
        entity.components.remove(CollisionComponent.self)
        entity.components.remove(InputTargetComponent.self)

        // 親コンテナに3Dモデルを追加し、物理スケールをコンテナに適用z
        container.addChild(entity)
        container.scale = SIMD3<Float>(repeating: scale)
        
        // --- ユーザー指定の歩行速度範囲 of 適用 ---
        // スマホ操作モデルは一律低速、通常モデルは男女別に指定
        let speedZRange: ClosedRange<Float> = name.contains("phone") ? 0.0090...0.0160 : (name.contains("Man") ? 0.0120...0.0200 : 0.0105...0.0185)
        
        // 廊下の幅に合わせたスポーン位置の決定
        let wallLimit = Float(panelModel.peopleHorizontalRange) - 0.5
        let xOffset = sceneData.randomGen.random(in: -wallLimit...wallLimit)

        let baseEnd = spawnLineEndWorld // 被験者スタート ＝ 歩行者消滅位置
        let baseUserEnd = spawnLineStartWorld // 被験者ゴール (30m先)
        let walkDir = normalize(baseUserEnd - baseEnd) // 被験者の進行方向 (endからuserEndへ)
        
        let start: SIMD3<Float>
        let end: SIMD3<Float>
        
        let isTwoWay = (panelModel.pedestrianDirectionMode == .twoWay)
        let spawnOpposite = isTwoWay && sceneData.randomGen.randomBool()
        
        if spawnOpposite {
            // 被験者と同じ方向に歩く（背後から湧いて追い越すイメージ）
            start = baseEnd - walkDir * 5.0
            end = baseUserEnd + walkDir * 10.0
        } else {
            // 対向して歩く（デフォルト）
            start = baseUserEnd + walkDir * 10.0 // ゴールより奥
            end = baseEnd - walkDir * 10.0
        }
        let segDir = normalize(end - start) // 歩行者の進行方向
        
        // --- 速度のブレンド分布（中心付近が出やすい三角形分布 + 一様分布の平均） ---
        var speedMag = (sceneData.randomGen.random(in: speedZRange) + (sceneData.randomGen.random(in: speedZRange) + sceneData.randomGen.random(in: speedZRange)) * 0.5) * 0.5

        // --- 確率的に「たまに極端に遅い人・早い人」を発生させる ---
        // 渋滞を防ぐため、のんびり歩く人は2%、急ぐ人は4%に設定
        let speedRoll = sceneData.randomGen.random(in: Float(0.0)...Float(1.0))
        if speedRoll < 0.02 {
            // 2%の確率で「のんびり歩く人」（速度を65%〜75%に減速）
            let slowFactor = sceneData.randomGen.random(in: Float(0.65)...Float(0.75))
            speedMag *= slowFactor
        } else if speedRoll > 0.96 {
            // 4%の確率で「急いで歩く人」（速度を1.25倍〜1.40倍に加速）
            let fastFactor = sceneData.randomGen.random(in: Float(1.25)...Float(1.40))
            speedMag *= fastFactor
        }

        // モデルの初期回転設定（歩行方向に向ける + 少し前傾させる）をコンテナに適用
        let yaw = atan2(segDir.x, segDir.z)
        container.transform.rotation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0)) * simd_quatf(angle: .pi / 18, axis: SIMD3<Float>(1, 0, 0))
        
        // 横方向ベクトルを計算し、初期位置をオフセット
        let lateralDir = SIMD3<Float>(-segDir.z, 0, segDir.x)
        
        let travelLimit = distance(start, end)
        let progress = initialProgress ?? 0.0
        let currentTraveled = progress * travelLimit
        
        container.position = start + segDir * currentTraveled + lateralDir * xOffset

        let personalRadius: Float = name.contains("phone") ? 0.32 : 0.28
        let headPos = sceneData.headAnchor.position(relativeTo: nil)
        
        // ユーザーの至近距離にはスポーンさせない
        if distance(container.position, headPos) < 1.2 { return false }

        // 他の歩行者とのスポーン時の重なりチェック
        let minSpawnGap = personalRadius * 2.2 + 0.08
        for existing in sceneData.movingEntities where !existing.isWaiting {
            let existingPos = existing.origin + existing.axisDir * existing.traveled + existing.lateralDir * existing.lateralOffset
            if distance(existingPos, container.position) < (existing.personalRadius + minSpawnGap) { return false }
        }

        // アニメーション再生の開始（子エンティティの骨格に対して再生）
        var controller: AnimationPlaybackController? = nil
        if let animation = entity.availableAnimations.first { controller = entity.playAnimation(animation.repeat()) }

        // 精密な衝突判定用の球体（頭部・胴体・脚部）を設定（基準身長1.8mに対応する物理配置、頭上へさらに1つ追加した5点判定）
        let spheres = [
            CollisionSphere(localOffset: [0, 1.90, 0], radius: 0.15), // 頭上（さらに上に追加）
            CollisionSphere(localOffset: [0, 1.62, 0], radius: 0.18), // 頭部
            CollisionSphere(localOffset: [0, 1.20, 0], radius: 0.28), // 胸部
            CollisionSphere(localOffset: [0, 0.78, 0], radius: 0.25), // 腰部
            CollisionSphere(localOffset: [0, 0.35, 0], radius: 0.22)  // 脚部
        ]

        sceneData.worldAnchor.addChild(container)
        
        // 移動管理オブジェクトの生成と追加
        sceneData.movingEntities.append(MovingEntity(
            entity: container, // 親コンテナを移動管理対象とする
            origin: start,
            axisDir: segDir,
            speed: speedMag,
            travelLimit: travelLimit,
            traveled: currentTraveled,
            personalRadius: personalRadius,
            lateralDir: lateralDir,
            lateralOffset: xOffset,
            targetLateralOffset: xOffset,
            preferredCruiseOffset: xOffset,
            isDistracted: name.contains("phone"),
            collisionSpheres: spheres,
            animationController: controller
        ))
        return true
    }

    /// 初期状態の歩行者を確実に表示する（混雑度に応じて道にランダムに初期配置、毎回シード値42から生成するため完全固定）
    private func ensureInitialPeopleAreVisible() {
        guard isSceneReady, sceneData.needsInitialSpawn else { return }
        guard !sceneData.modelTemplates.isEmpty else { return }
        
        let interval = panelModel.peopleSpawnInterval
        let trials: Int
        if interval <= panelModel.tF + 0.1 {
            trials = 100 // LOS F
        } else if interval <= panelModel.tE + 0.1 {
            trials = 70 // LOS E
        } else if interval <= panelModel.tD + 0.1 {
            trials = 40 // LOS D
        } else if interval <= panelModel.tC + 0.1 {
            trials = 20 // LOS C
        } else if interval <= panelModel.tB + 0.1 {
            trials = 10 // LOS B
        } else {
            trials = 5  // LOS A
        }
        
        for _ in 0..<trials {
            // スポーンラインの手前5%〜奥95%の範囲にランダム配置
            let progress = sceneData.randomGen.random(in: Float(0.05)...Float(0.95))
            _ = spawnRandomEntity(initialProgress: progress)
        }
        
        sceneData.needsInitialSpawn = false
    }

    /// 一時停止/再開時の表示状態のリフレッシュ
    private func refreshPausedPresentation() {
        guard isSceneReady else { return }
        if panelModel.peopleIsPlaying { ensureInitialPeopleAreVisible() }
        setPeopleVisibility(panelModel.peopleIsPlaying)
        updateSpawnLineVisualization(isVisible: true)
    }

    /// 歩行者をすべて削除し、シード値および関連ステートを初期値にリセットする
    private func resetPedestriansAndSeed() {
        guard isSceneReady else { return }
        
        // 1. RealityKitのワールド空間からすべての歩行者を安全に破棄
        for moving in sceneData.movingEntities {
            moving.entity.removeFromParent()
            moving.visualGroup?.removeFromParent()
        }
        sceneData.movingEntities.removeAll()

        // 2. 擬似乱数ジェネレータ（SeededRandom）の初期化リセット
        sceneData.randomGen = SeededRandom(seed: 42)

        // 3. 初期配置フラグを立て直す
        sceneData.needsInitialSpawn = true

        // 4. スポーンパラメータや衝突カウントの初期化
        sceneData.spawnCountdown = 0.0
        sceneData.shuffledSpawnXOffsets = []
        sceneData.spawnXIndex = 0
        sceneData.handContactCount = 0
        
        // 5. 最新の衝突回数 (0) を全HUDパネルに即座に反映させるため再描画
        updateHUDPanels()
        
        // 6. 再生状態の場合はリセット直後にすぐ1人目をスポーン
        if panelModel.peopleIsPlaying {
            ensureInitialPeopleAreVisible()
        }
    }

    private func resetPathAnchorState() {
        sceneData.smoothedUserPosition = .zero
        sceneData.previousSmoothedUserPosition = .zero
        sceneData.pathAnchorPosition = .zero
        sceneData.smoothedPathForward = SIMD3<Float>(0, 0, -1)
        sceneData.smoothedHeadForward = SIMD3<Float>(0, 0, -1)
        sceneData.smoothedVelocity = .zero
        sceneData.locomotionHeading = SIMD3<Float>(0, 0, -1)
        sceneData.locomotionPositionHistory.removeAll()
        sceneData.sustainedHeadingCandidate = nil
        sceneData.sustainedHeadingDuration = 0
        sceneData.hasPathAnchorState = false
    }

    /// 自身の当たり判定オブジェクト（シリンダー、手首の球体）を破棄し、最新のトラッキング状態へ強制再同期させる
    private func resetUserCollisionAnchor() {
        guard isSceneReady else { return }
        
        // 1. キャッシュされているユーザーの手・体のビジュアルと物理オブジェクトをRealityKitから破棄
        sceneData.userBodyVisual?.removeFromParent()
        sceneData.userBodyVisual = nil
        
        sceneData.userLeftHandVisual?.removeFromParent()
        sceneData.userLeftHandVisual = nil
        
        sceneData.userRightHandVisual?.removeFromParent()
        sceneData.userRightHandVisual = nil
        
        // 2. 親のワールドアンカー階層から残存している可能性のある同名エンティティも確実にクリーンアップ
        if let existingBody = sceneData.worldAnchor.findEntity(named: "UserBodyVisual") {
            existingBody.removeFromParent()
        }
        if let existingLeft = sceneData.worldAnchor.findEntity(named: "UserLeftHandVisual") {
            existingLeft.removeFromParent()
        }
        if let existingRight = sceneData.worldAnchor.findEntity(named: "UserRightHandVisual") {
            existingRight.removeFromParent()
        }
        
        // 3. 最新のVision Proデバイスの空間座標（頭部位置）をクエリして即時同期
        if let deviceAnchor = sceneData.worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let transform = deviceAnchor.originFromAnchorTransform
            let t = transform.columns.3
            let zAxis = transform.columns.2
            sceneData.latestDevicePosition = SIMD3<Float>(t.x, t.y, t.z)
            sceneData.latestDeviceForward = simd_normalize(SIMD3<Float>(-zAxis.x, -zAxis.y, -zAxis.z))
            sceneData.hasDevicePosition = true
        }
        resetPathAnchorState()
    }

    private func setPeopleVisibility(_ isVisible: Bool) {
        for i in sceneData.movingEntities.indices {
            sceneData.movingEntities[i].entity.isEnabled = isVisible
            sceneData.movingEntities[i].visualGroup?.isEnabled = isVisible && panelModel.showCollisionVisuals
        }
    }

    /// 移動ループの開始
    private func startMovementLoop(content: RealityViewContent) {
        updateSubscription?.cancel()
        sceneData.spawnCountdown = max(0.1, panelModel.peopleSpawnInterval)
        updateSubscription = content.subscribe(to: SceneEvents.Update.self) { event in self.movementLoopTick(deltaTime: event.deltaTime) }
    }

    /// 廊下の左右の壁（コリドー）を更新する
    private func updateCorridorWalls() {
        let wallLength = spawnLineLength
        let start = spawnLineStartWorld
        let end = spawnLineEndWorld
        let range = Float(panelModel.peopleHorizontalRange)
        let yPos = 3.9 + Float(panelModel.peopleHeightOffset)

        if sceneData.leftWall != nil && sceneData.rightWall != nil &&
            sceneData.lastWallLength == wallLength &&
            sceneData.lastPeopleHorizontalRange == range &&
            sceneData.lastPeopleHeightOffset == yPos &&
            sceneData.lastSpawnLineStartWorld == start &&
            sceneData.lastSpawnLineEndWorld == end &&
            sceneData.lastState == experimentManager.state {
            return
        }

        sceneData.lastWallLength = wallLength
        sceneData.lastPeopleHorizontalRange = range
        sceneData.lastPeopleHeightOffset = yPos
        sceneData.lastSpawnLineStartWorld = start
        sceneData.lastSpawnLineEndWorld = end
        sceneData.lastState = experimentManager.state

        let lineDir = normalize(end - start)
        let walkDir = SIMD3<Float>(-lineDir.z, 0, lineDir.x)
        let center = (start + end) / 2.0

        func setupWall(id: String, isForward: Bool, current: inout Entity?) {
            if current == nil {
                let wall = Entity(); wall.name = id
                // 不透明度コンポーネントを追加（確実に透過させるため）
                wall.components.set(OpacityComponent(opacity: 0.1))
                
                let model = ModelEntity(mesh: .generateBox(width: 1.0, height: 7.8, depth: 0.05), materials: [UnlitMaterial(color: .systemBlue)])
                wall.addChild(model)
                current = wall
            }
            if let wall = current, let model = wall.children.first as? ModelEntity {
                model.orientation = simd_quaternion(simd_matrix(lineDir, [0, 1, 0], walkDir))
                model.scale = [wallLength, 1.0, 1.0]
                wall.position = center + (isForward ? walkDir * range : -walkDir * range) + SIMD3<Float>(0, yPos, 0)
                
                if experimentManager.state == .running {
                    wall.removeFromParent()
                } else {
                    if wall.parent == nil {
                        sceneData.worldAnchor.addChild(wall)
                    }
                }
            }
        }
        setupWall(id: "Wall.Front", isForward: true, current: &sceneData.leftWall)
        setupWall(id: "Wall.Back", isForward: false, current: &sceneData.rightWall)
    }

    private func clampPathHUDParameters() -> (zDistance: Float, yAngleDeg: Float, xAngleDeg: Float, vof: Float) {
        (
            zDistance: min(5.0, max(1.25, Float(panelModel.pathHUDZDistance))),
            yAngleDeg: min(10.0, max(-40.0, Float(panelModel.pathHUDYAngleDegrees))),
            xAngleDeg: min(35.0, max(-35.0, Float(panelModel.pathHUDXAngleDegrees))),
            vof: min(100.0, max(60.0, Float(panelModel.pathHUDVoF)))
        )
    }

    private func stableHorizontalForward(from vector: SIMD3<Float>, fallback: SIMD3<Float>) -> SIMD3<Float> {
        let horizontal = SIMD3<Float>(vector.x, 0, vector.z)
        if simd_length(horizontal) > 0.0001 {
            return simd_normalize(horizontal)
        }
        return fallback
    }

    private func smoothingAlpha(deltaTime: TimeInterval, timeConstant: Float) -> Float {
        let dt = max(0.0001, min(0.05, Float(deltaTime)))
        return 1.0 - exp(-dt / max(0.0001, timeConstant))
    }

    private func signedYawDelta(from current: SIMD3<Float>, to target: SIMD3<Float>) -> Float {
        let c = stableHorizontalForward(from: current, fallback: SIMD3<Float>(0, 0, -1))
        let t = stableHorizontalForward(from: target, fallback: c)
        let crossY = c.z * t.x - c.x * t.z
        let dotValue = max(-1.0, min(1.0, simd_dot(c, t)))
        return atan2(crossY, dotValue)
    }

    private func rotateHorizontalForward(_ forward: SIMD3<Float>, by yawDelta: Float) -> SIMD3<Float> {
        let rotation = simd_quatf(angle: yawDelta, axis: SIMD3<Float>(0, 1, 0))
        return stableHorizontalForward(from: simd_act(rotation, forward), fallback: forward)
    }

    private func predictedLocomotionDirection(fallback: SIMD3<Float>) -> SIMD3<Float>? {
        let history = sceneData.locomotionPositionHistory
        guard history.count >= 8 else { return nil }

        let sampleOffsets = [4, 8, 12, 18, 24]
        var trend = SIMD3<Float>.zero
        var totalWeight: Float = 0
        let newest = history[history.count - 1]

        for offset in sampleOffsets where history.count > offset {
            let older = history[history.count - 1 - offset]
            let displacement = newest - older
            let horizontal = SIMD3<Float>(displacement.x, 0, displacement.z)
            let distance = simd_length(horizontal)
            guard distance > 0.04 else { continue }
            let currentForwardProgress = simd_dot(horizontal, fallback)
            guard currentForwardProgress > 0.02 else { continue }
            let lateralRatio = sqrt(max(0, distance * distance - currentForwardProgress * currentForwardProgress)) / max(0.001, currentForwardProgress)
            guard lateralRatio < 0.85 else { continue }
            let recencyWeight = 1.0 / sqrt(Float(offset))
            let weight = min(1.0, distance * 2.0) * recencyWeight
            trend += simd_normalize(horizontal) * weight
            totalWeight += weight
        }

        guard totalWeight > 0, simd_length(trend) > 0.0001 else { return nil }
        return stableHorizontalForward(from: trend / totalWeight, fallback: fallback)
    }

    private func hudVisibleWidth() -> Float {
        let visiblePanels = panelModel.panels.filter(\.isVisible)
        guard !visiblePanels.isEmpty else { return 0.5 }

        var minX = Float.greatestFiniteMagnitude
        var maxX = -Float.greatestFiniteMagnitude
        for panel in visiblePanels {
            let size = panel.renderSize
            let centerX = panel.worldPosition.x
            minX = min(minX, centerX - size.x / 2)
            maxX = max(maxX, centerX + size.x / 2)
        }

        return max(0.01, maxX - minX)
    }

    private func updatePathAnchoredHUD(userWorldPosition: SIMD3<Float>, headForward: SIMD3<Float>, headOrientation: simd_quatf, deltaTime: TimeInterval) {
        let positionAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.12)
        let heightAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.45)
        let velocityAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.10)
        let dt = max(0.0001, min(0.05, Float(deltaTime)))
        let horizontalHeadForward = stableHorizontalForward(from: headForward, fallback: sceneData.smoothedHeadForward)

        if !sceneData.hasPathAnchorState {
            sceneData.smoothedUserPosition = userWorldPosition
            sceneData.previousSmoothedUserPosition = userWorldPosition
            sceneData.smoothedPathForward = horizontalHeadForward
            sceneData.smoothedHeadForward = horizontalHeadForward
            sceneData.locomotionHeading = horizontalHeadForward
            sceneData.smoothedVelocity = .zero
            sceneData.pathAnchorPosition = userWorldPosition
            sceneData.locomotionPositionHistory = [userWorldPosition]
            sceneData.sustainedHeadingCandidate = nil
            sceneData.sustainedHeadingDuration = 0
            sceneData.hasPathAnchorState = true
        }

        sceneData.previousSmoothedUserPosition = sceneData.smoothedUserPosition
        sceneData.smoothedUserPosition.x += (userWorldPosition.x - sceneData.smoothedUserPosition.x) * positionAlpha
        sceneData.smoothedUserPosition.z += (userWorldPosition.z - sceneData.smoothedUserPosition.z) * positionAlpha
        sceneData.smoothedUserPosition.y += (userWorldPosition.y - sceneData.smoothedUserPosition.y) * heightAlpha
        let basePathForward = stableHorizontalForward(from: spawnLineStartWorld - spawnLineEndWorld, fallback: sceneData.locomotionHeading)
        let anchorForward = basePathForward
        let anchorRight = stableHorizontalForward(from: SIMD3<Float>(anchorForward.z, 0, -anchorForward.x), fallback: SIMD3<Float>(1, 0, 0))
        let anchorDelta = userWorldPosition - sceneData.pathAnchorPosition
        let forwardDelta = simd_dot(anchorDelta, anchorForward)
        let lateralDelta = simd_dot(anchorDelta, anchorRight)
        let forwardFollowAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.18)
        let lateralFollowAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 1.20)
        let lateralDeadZone: Float = 0.18
        sceneData.pathAnchorPosition += anchorForward * (forwardDelta * forwardFollowAlpha)
        if abs(lateralDelta) > lateralDeadZone {
            let lateralCorrection = lateralDelta - (lateralDelta > 0 ? lateralDeadZone : -lateralDeadZone)
            sceneData.pathAnchorPosition += anchorRight * (lateralCorrection * lateralFollowAlpha)
        }
        sceneData.pathAnchorPosition.y += (sceneData.smoothedUserPosition.y - sceneData.pathAnchorPosition.y) * heightAlpha
        let headAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.8)
        sceneData.smoothedHeadForward = simd_normalize(simd_mix(sceneData.smoothedHeadForward, horizontalHeadForward, SIMD3<Float>(repeating: headAlpha)))

        let measuredVelocity = (sceneData.smoothedUserPosition - sceneData.previousSmoothedUserPosition) / dt
        sceneData.smoothedVelocity = simd_mix(sceneData.smoothedVelocity, measuredVelocity, SIMD3<Float>(repeating: velocityAlpha))

        sceneData.locomotionPositionHistory.append(sceneData.smoothedUserPosition)
        if sceneData.locomotionPositionHistory.count > 90 {
            sceneData.locomotionPositionHistory.removeFirst(sceneData.locomotionPositionHistory.count - 90)
        }

        // Head orientation is kept separate; path orientation uses the configured start/end path line.
        let speed = simd_length(SIMD2<Float>(sceneData.smoothedVelocity.x, sceneData.smoothedVelocity.z))
        if speed > 0.05, let predictedForward = predictedLocomotionDirection(fallback: sceneData.locomotionHeading) {
            let angleDelta = signedYawDelta(from: sceneData.locomotionHeading, to: predictedForward)
            let absDelta = abs(angleDelta)
            let deadZone = Float(5.0 * Float.pi / 180.0)
            let sustainedThreshold = Float(8.0 * Float.pi / 180.0)

            if absDelta > deadZone {
                if let candidate = sceneData.sustainedHeadingCandidate {
                    let candidateDelta = abs(signedYawDelta(from: candidate, to: predictedForward))
                    if candidateDelta < Float(10.0 * Float.pi / 180.0) {
                        sceneData.sustainedHeadingDuration += dt
                    } else {
                        sceneData.sustainedHeadingCandidate = predictedForward
                        sceneData.sustainedHeadingDuration = dt
                    }
                } else {
                    sceneData.sustainedHeadingCandidate = predictedForward
                    sceneData.sustainedHeadingDuration = dt
                }

                if absDelta > sustainedThreshold && sceneData.sustainedHeadingDuration > 0.12 {
                    let baseYawRate = Float(80.0 * Float.pi / 180.0)
                    let extraYawRate = min(Float(60.0 * Float.pi / 180.0), absDelta * 1.2)
                    let maxYawRate = baseYawRate + extraYawRate
                    let yawStep = max(-maxYawRate * dt, min(maxYawRate * dt, angleDelta))
                    sceneData.locomotionHeading = rotateHorizontalForward(sceneData.locomotionHeading, by: yawStep)
                }
            } else {
                sceneData.sustainedHeadingCandidate = nil
                sceneData.sustainedHeadingDuration = 0
            }
        } else {
            sceneData.sustainedHeadingCandidate = nil
            sceneData.sustainedHeadingDuration = 0
        }

        let trackingMode = panelModel.trackingMode
        
        switch trackingMode {
        case .pathLocked:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            let params = clampPathHUDParameters()
            let xRadians = params.xAngleDeg * Float.pi / 180
            let pathForward = rotateHorizontalForward(basePathForward, by: xRadians)
            let pathZ = -pathForward
            let worldUp = SIMD3<Float>(0, 1, 0)
            let pathXCandidate = simd_cross(worldUp, pathZ)
            let pathX = simd_length(pathXCandidate) > 0.0001 ? simd_normalize(pathXCandidate) : SIMD3<Float>(1, 0, 0)
            let pathY = simd_normalize(simd_cross(pathZ, pathX))

            sceneData.pathAnchor.position = sceneData.pathAnchorPosition
            sceneData.pathAnchor.orientation = simd_quaternion(simd_float3x3(pathX, pathY, pathZ))
            
        case .bodyLocked:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            let params = clampPathHUDParameters()
            let xRadians = params.xAngleDeg * Float.pi / 180
            let pathForward = rotateHorizontalForward(sceneData.locomotionHeading, by: xRadians)
            let pathZ = -pathForward
            let worldUp = SIMD3<Float>(0, 1, 0)
            let pathXCandidate = simd_cross(worldUp, pathZ)
            let pathX = simd_length(pathXCandidate) > 0.0001 ? simd_normalize(pathXCandidate) : SIMD3<Float>(1, 0, 0)
            let pathY = simd_normalize(simd_cross(pathZ, pathX))

            sceneData.pathAnchor.position = sceneData.pathAnchorPosition
            sceneData.pathAnchor.orientation = simd_quaternion(simd_float3x3(pathX, pathY, pathZ))
            
        case .headLocked:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            sceneData.pathAnchor.position = userWorldPosition
            sceneData.pathAnchor.orientation = headOrientation
            
        case .lazyFollow:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            let smoothPosAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.15)
            let smoothRotAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.15)
            let currentPos = sceneData.pathAnchor.position
            let currentRot = sceneData.pathAnchor.orientation
            
            // For lazy follow, we initialize it if it's too far
            if distance(currentPos, userWorldPosition) > 1.0 {
                sceneData.pathAnchor.position = userWorldPosition
                sceneData.pathAnchor.orientation = headOrientation
            } else {
                sceneData.pathAnchor.position = simd_mix(currentPos, userWorldPosition, SIMD3<Float>(repeating: smoothPosAlpha))
                sceneData.pathAnchor.orientation = simd_slerp(currentRot, headOrientation, smoothRotAlpha)
            }
            
        case .pitchLockedYawFollow:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            sceneData.pathAnchor.position = userWorldPosition
            let headForward = headOrientation.act(SIMD3<Float>(0, 0, -1))
            let headForwardXZ = simd_length(SIMD3<Float>(headForward.x, 0, headForward.z)) > 0.0001 ? simd_normalize(SIMD3<Float>(headForward.x, 0, headForward.z)) : SIMD3<Float>(0, 0, -1)
            let yawRot = simd_quaternion(simd_float3x3(
                simd_normalize(simd_cross(SIMD3<Float>(0, 1, 0), -headForwardXZ)),
                SIMD3<Float>(0, 1, 0),
                -headForwardXZ
            ))
            sceneData.pathAnchor.orientation = yawRot
            
        case .yawLockedPitchFollow:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            sceneData.pathAnchor.position = userWorldPosition
            let headForward = headOrientation.act(SIMD3<Float>(0, 0, -1))
            let pitchAngle = asin(max(-1.0, min(1.0, headForward.y)))
            let pathZ = -sceneData.locomotionHeading
            let pathXCandidate = simd_cross(SIMD3<Float>(0, 1, 0), pathZ)
            let pathX = simd_length(pathXCandidate) > 0.0001 ? simd_normalize(pathXCandidate) : SIMD3<Float>(1, 0, 0)
            let yawRot = simd_quaternion(simd_float3x3(pathX, SIMD3<Float>(0, 1, 0), pathZ))
            let pitchRot = simd_quatf(angle: pitchAngle, axis: SIMD3<Float>(1, 0, 0))
            sceneData.pathAnchor.orientation = yawRot * pitchRot
            
        case .snapFollow:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            sceneData.pathAnchor.position = userWorldPosition
            
            let currentRot = sceneData.lastSnappedOrientation
            let dot = abs(simd_dot(currentRot.vector, headOrientation.vector))
            let angleDiff = 2.0 * acos(max(-1.0, min(1.0, dot)))
            let thresholdRadians = Float(panelModel.snapThresholdDegrees) * .pi / 180.0
            
            if angleDiff > thresholdRadians || currentRot.vector == SIMD4<Float>(0,0,0,0) {
                sceneData.lastSnappedOrientation = headOrientation
            }
            
            let smoothRotAlpha = smoothingAlpha(deltaTime: deltaTime, timeConstant: 0.1)
            let interpRot = simd_slerp(sceneData.pathAnchor.orientation, sceneData.lastSnappedOrientation, smoothRotAlpha)
            sceneData.pathAnchor.orientation = interpRot
            
        case .worldOriented:
            sceneData.smoothedPathForward = sceneData.locomotionHeading
            sceneData.pathAnchor.position = userWorldPosition
            let params = clampPathHUDParameters()
            let xRadians = params.xAngleDeg * Float.pi / 180
            let pathForward = rotateHorizontalForward(basePathForward, by: xRadians)
            let pathZ = -pathForward
            let pathXCandidate = simd_cross(SIMD3<Float>(0, 1, 0), pathZ)
            let pathX = simd_length(pathXCandidate) > 0.0001 ? simd_normalize(pathXCandidate) : SIMD3<Float>(1, 0, 0)
            let pathY = simd_normalize(simd_cross(pathZ, pathX))
            sceneData.pathAnchor.orientation = simd_quaternion(simd_float3x3(pathX, pathY, pathZ))
        }

        sceneData.hudRoot.position = .zero
        sceneData.hudRoot.orientation = simd_quatf()
        sceneData.hudRoot.scale = SIMD3<Float>(repeating: 1.0)
        
        updateOptimalZoneGuide()
    }

    /// 毎フレームの移動および回避ロジック（高度なパス評価と衝突回避）
    private func movementLoopTick(deltaTime: TimeInterval) {
        updateCorridorWalls()
        let yOffset = Float(panelModel.peopleHeightOffset)

        sceneData.frameCount += 1
        
        if sceneData.lastCheckedCollisionCount != experimentManager.collisionCount {
            sceneData.lastCheckedCollisionCount = experimentManager.collisionCount
            updateHUDPanels()
        }

        if let pending = sceneData.pendingHUDToken, pending != sceneData.lastHUDToken, sceneData.frameCount % 2 == 0 {
            sceneData.lastHUDToken = pending; sceneData.pendingHUDToken = nil; updateHUDPanels()
        }

        let handRadius: Float = 0.04
        let bodyRadius: Float = 0.23

        // --- ユーザーのビジュアルと位置の更新（再生状態に関わらず、常時高精度に追従） ---
        updateUserCollisionVisuals(bodyRadius: bodyRadius, handRadius: handRadius)

        // 衝突判定は、歩行者・ユーザー・手の座標系をすべて worldAnchor 空間に統一する。
        // ユーザーの頭部位置は AnchorEntity(.head) ではなく、WorldTrackingProvider の device anchor から取得する。
        if let deviceAnchor = sceneData.worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let transform = deviceAnchor.originFromAnchorTransform
            let t = transform.columns.3
            let zAxis = transform.columns.2
            sceneData.latestDevicePosition = SIMD3<Float>(t.x, t.y, t.z)
            // deviceAnchor の -Z 方向を「ユーザーが向いている前方」として扱う。
            sceneData.latestDeviceForward = simd_normalize(SIMD3<Float>(-zAxis.x, -zAxis.y, -zAxis.z))
            sceneData.latestDeviceOrientation = simd_quatf(transform)
            sceneData.hasDevicePosition = true
        }
        let rawHeadPos = sceneData.hasDevicePosition ? sceneData.latestDevicePosition : sceneData.headAnchor.position(relativeTo: nil)
        let rawForward = sceneData.hasDevicePosition ? sceneData.latestDeviceForward : simd_act(sceneData.headAnchor.orientation(relativeTo: nil), SIMD3<Float>(0, 0, -1))
        let rawHeadOri = sceneData.hasDevicePosition ? sceneData.latestDeviceOrientation : sceneData.headAnchor.orientation(relativeTo: nil)
        let headForward = simd_normalize(SIMD3<Float>(rawForward.x, 0, rawForward.z))
        let bodyBackwardOffset: Float = 0.15
        let headPos = rawHeadPos - headForward * bodyBackwardOffset
        updatePathAnchoredHUD(userWorldPosition: rawHeadPos, headForward: rawForward, headOrientation: rawHeadOri, deltaTime: deltaTime)

        // --- ゴール（Endの球）への到達判定によるタスク自動終了 ---
        if experimentManager.state == .running {
            let startPos = spawnLineStartWorld // 被験者ゴール (30m先)
            
            // ユーザー頭部とゴールの2D平面上（水平面）の距離を測定
            let userHorizontal = SIMD2<Float>(rawHeadPos.x, rawHeadPos.z)
            let goalHorizontal = SIMD2<Float>(startPos.x, startPos.z)
            let distToGoal = distance(userHorizontal, goalHorizontal)
            
            // 半径0.8m以内に接近したら自動でゴール（タスク終了）とする
            if distToGoal < 0.8 {
                experimentManager.endTask(panelModel: panelModel)
            }
        }

        // 手の当たり判定は、表示中の黄色い球そのものの現在位置を判定直前に読む。
        // キャッシュ値 latestLeft/RightHandPosition は使わず、見えている球と判定位置を一致させる。
        let leftPos: SIMD3<Float>
        let rightPos: SIMD3<Float>
        let isLeftAnchored: Bool
        let isRightAnchored: Bool

        if sceneData.hasLeftHandPosition {
            leftPos = sceneData.latestLeftHandPosition
            isLeftAnchored = true
        } else {
            leftPos = .zero
            isLeftAnchored = false
        }

        if sceneData.hasRightHandPosition {
            rightPos = sceneData.latestRightHandPosition
            isRightAnchored = true
        } else {
            rightPos = .zero
            isRightAnchored = false
        }

        let isHeadAnchored = sceneData.hasDevicePosition

        // --- 歩行者シミュレーションの再生チェック ---
        if !panelModel.peopleIsPlaying {
            setPeopleVisibility(false)
            return
        }

        setPeopleVisibility(true)
        ensureInitialPeopleAreVisible()

        let baseInterval = max(0.1, panelModel.peopleSpawnInterval)
        sceneData.spawnCountdown -= deltaTime
        if sceneData.spawnCountdown <= 0 {
            if spawnRandomEntity() {
                let jitterFactor = sceneData.randomGen.random(in: 0.9...1.1)
                sceneData.spawnCountdown = baseInterval * jitterFactor
            }
        }

        let speedMultiplier = Float(panelModel.peopleSpeedMultiplier)
        if deltaTime > 0.2 { return }
        let dt = max(0.0001, min(0.05, Float(deltaTime)))

        // --- アルゴリズムによる分岐 ---
        switch panelModel.pedestrianAlgorithm {
        case .customLaneBased:
            updatePedestriansCustomLaneBased(deltaTime: deltaTime, dt: dt, leftPos: leftPos, rightPos: rightPos, isLeftAnchored: isLeftAnchored, isRightAnchored: isRightAnchored, headPos: headPos, isHeadAnchored: isHeadAnchored, speedMultiplier: speedMultiplier, bodyRadius: bodyRadius, handRadius: handRadius)
        case .socialForceModel:
            updatePedestriansSFM(deltaTime: deltaTime, dt: dt, leftPos: leftPos, rightPos: rightPos, isLeftAnchored: isLeftAnchored, isRightAnchored: isRightAnchored, headPos: headPos, isHeadAnchored: isHeadAnchored, speedMultiplier: speedMultiplier)
        case .rvo:
            updatePedestriansRVO(deltaTime: deltaTime, dt: dt, leftPos: leftPos, rightPos: rightPos, isLeftAnchored: isLeftAnchored, isRightAnchored: isRightAnchored, headPos: headPos, isHeadAnchored: isHeadAnchored, speedMultiplier: speedMultiplier)
        case .hybrid:
            updatePedestriansHybrid(deltaTime: deltaTime, dt: dt, leftPos: leftPos, rightPos: rightPos, isLeftAnchored: isLeftAnchored, isRightAnchored: isRightAnchored, headPos: headPos, isHeadAnchored: isHeadAnchored, speedMultiplier: speedMultiplier)
        }
        
    }

    private func updatePedestriansCustomLaneBased(deltaTime: TimeInterval, dt: Float, leftPos: SIMD3<Float>, rightPos: SIMD3<Float>, isLeftAnchored: Bool, isRightAnchored: Bool, headPos: SIMD3<Float>, isHeadAnchored: Bool, speedMultiplier: Float, bodyRadius: Float, handRadius: Float) {
        // --- シミュレーションパラメータ ---
        let lookAheadBase: Float = 2.5
        let proactiveLookAhead: Float = 8.0
        let sideMargin: Float = 0.18
        let oncomingLookAhead: Float = 4.0
        let neighborRadius: Float = 4.5
        let stopGapBase: Float = 0.28
        
        let yOffset = Float(panelModel.peopleHeightOffset)
        
        struct EntitySnapshot {
            let index: Int
            let worldPos: SIMD3<Float>
            let moving: MovingEntity
        }
        var snapshots: [EntitySnapshot] = []
        for i in sceneData.movingEntities.indices {
            let moving = sceneData.movingEntities[i]
            if moving.isWaiting { continue }
            var pos = moving.origin + moving.axisDir * moving.traveled
            pos.y = yOffset
            let worldPos = pos + moving.lateralDir * moving.lateralOffset
            snapshots.append(EntitySnapshot(index: i, worldPos: worldPos, moving: moving))
        }

        let wallLimitTotal = Float(panelModel.peopleHorizontalRange)

        for snapshot in snapshots {
            let i = snapshot.index
            let moving = snapshot.moving
            let currentWorldPos = snapshot.worldPos
            let scale = moving.entity.scale.x

            let physicalScale = scale / 1.8
            let pedestrianRadius: Float = 0.20 * physicalScale

            // 歩行者の判定範囲の可視化更新（USDZのオクルージョンや骨格バグを防ぐため、ワールドアンカー直下に直接描画）
            if moving.visualGroup == nil {
                let group = Entity()
                group.name = "PedestrianVisualGroup_\(i)"
                sceneData.worldAnchor.addChild(group)
                moving.visualGroup = group
                
                // 身体全体の衝突シリンダー（実寸+3cmに設定、頭部頂点までカバーするため高さを1.25倍に設定）
                let cylinderMesh = ModelEntity(
                    mesh: .generateCylinder(height: scale * 1.25, radius: pedestrianRadius + 0.03),
                    materials: [SimpleMaterial(color: .systemRed.withAlphaComponent(0.20), isMetallic: false)]
                )
                cylinderMesh.name = "CylinderVisual"
                group.addChild(cylinderMesh)
                moving.cylinderVisual = cylinderMesh
                
                // パーソナルスペース用のディスク（床下クリップを防ぐため床面より少し浮かせて表示）
                let ringMesh = ModelEntity(
                    mesh: .generateCylinder(height: 0.04, radius: moving.personalRadius),
                    materials: [SimpleMaterial(color: .systemGreen.withAlphaComponent(0.12), isMetallic: false)]
                )
                ringMesh.name = "RingVisual"
                group.addChild(ringMesh)
                moving.ringVisual = ringMesh
            } else {
                if moving.cylinderVisual == nil {
                    moving.cylinderVisual = moving.visualGroup?.children.first(where: { $0.name == "CylinderVisual" }) as? ModelEntity
                }
                if moving.ringVisual == nil {
                    moving.ringVisual = moving.visualGroup?.children.first(where: { $0.name == "RingVisual" }) as? ModelEntity
                }
            }
            
            if let group = moving.visualGroup {
                group.isEnabled = panelModel.showCollisionVisuals
                
                // 衝突シリンダーの位置を床面から立ち上がるように配置（世界座標で直立、進行方向に0.20mシフトして歩行姿勢に適合、高さは1.25倍ベースでセンタリング）
                if let cylinder = moving.cylinderVisual {
                    let forwardShift = moving.axisDir * 0.20
                    cylinder.position = currentWorldPos + forwardShift
                    cylinder.position.y = currentWorldPos.y + (scale * 1.25) / 2.0
                    cylinder.orientation = simd_quatf() // 向きを世界座標に完全固定（直立）
                }
                
                // 足元のディスクの位置を更新（進行方向に0.20mシフトしてシリンダーと完全一致）
                if let ring = moving.ringVisual {
                    var ringPos = currentWorldPos + moving.axisDir * 0.20
                    ringPos.y = yOffset + 0.02 // 床面からの浮上オフセット
                    ring.position = ringPos
                }
            }

            if moving.directionChangeCooldown > 0 { moving.directionChangeCooldown -= 1 }

            var handContactDetected = false
            var nearestFrontGap = Float.greatestFiniteMagnitude
            var nearestOncomingGap = Float.greatestFiniteMagnitude
            var nearestFrontSpeed = moving.speed
            var nearestFrontOffset = moving.lateralOffset
            var strongestCloseness: Float = 0
            var repulsionLateral: Float = 0
            var desiredSpeed: Float = moving.speed
            var isHardColliding: Bool = false

            // --- パス評価用のサンプリング（密度勾配の計算） ---
            let sampleCount = 15
            let samples: [Float] = (0..<sampleCount).map {
                let t = Float($0) / Float(sampleCount - 1)
                return (t * 2.0 - 1.0) * (wallLimitTotal * 0.95)
            }
            var costs = [Float](repeating: 0.0, count: sampleCount)
            var isBeingOvertaken = false

            for otherSnapshot in snapshots where otherSnapshot.index != i {
                let other = otherSnapshot.moving
                let otherPos = otherSnapshot.worldPos
                let diff = otherPos - currentWorldPos
                let planarDist = simd_length(SIMD2<Float>(diff.x, diff.z))
                let forwardGap = simd_dot(diff, moving.axisDir)
                let sideGap = simd_dot(diff, moving.lateralDir)
                let clearance = moving.personalRadius + other.personalRadius + sideMargin
                let headingAlignment = simd_dot(moving.axisDir, other.axisDir)
                let minSafeDist = moving.personalRadius + other.personalRadius
                if planarDist < minSafeDist {
                    isHardColliding = true
                    let overlap = minSafeDist - planarDist
                    let repulsionDir = planarDist > 0 ? -diff / planarDist : SIMD3<Float>(0, 0, 1)
                    repulsionLateral += simd_dot(repulsionDir, moving.lateralDir) * min(0.12, overlap * 0.6)

                    let collisionSlowdownWidth = moving.personalRadius + other.personalRadius - 0.05
                    if forwardGap > 0.0 && forwardGap < minSafeDist && abs(sideGap) < collisionSlowdownWidth {
                        if headingAlignment > 0.0 {
                            // 同一方向の場合：前の人に追突しないよう相手の速度に合わせる
                            if other.currentSpeed <= moving.currentSpeed * 1.1 {
                                desiredSpeed = min(desiredSpeed, other.currentSpeed * 0.35)
                            }
                        } else {
                            // 対向の場合：お互い止まらないように少し減速する程度にし、横に逃げるのを優先
                            desiredSpeed = min(desiredSpeed, moving.speed * 0.6)
                        }
                    }
                }

                // 前方の歩行者への回避コスト（基本）
                if forwardGap > 0.15 && forwardGap < proactiveLookAhead {
                    let distWeight = pow(max(0, 1.0 - forwardGap / proactiveLookAhead), 1.5)
                    // 対向してくる人には早めに強く避けるためボーナスを大きくする
                    let oncomingBonus: Float = headingAlignment < 0.0 ? 4.0 : 1.0
                    // 対向してくる人は横幅の余裕を広めにとる
                    let effectiveClearance = headingAlignment < 0.0 ? clearance + 0.2 : clearance

                    for (idx, offset) in samples.enumerated() {
                        let distFromOtherSide = abs(sideGap - (offset - moving.lateralOffset))
                        if distFromOtherSide < effectiveClearance {
                            costs[idx] += (1.0 - distFromOtherSide / effectiveClearance) * distWeight * oncomingBonus
                        }
                    }
                }
                
                // 後方の歩行者への割り込み防止コスト（カットイン防止）
                // 自分が車線変更しようとする先に後ろから人が来ている場合、そのレーンを避ける。
                // ただし、現在自分がいるレーンにはコストを加えない（後ろから煽られても直進を維持する）。
                if forwardGap >= -3.5 && forwardGap <= 0.15 {
                    let distWeight = pow(max(0, 1.0 - abs(forwardGap) / 3.5), 1.5)
                    for (idx, offset) in samples.enumerated() {
                        let distFromOtherSide = abs(sideGap - (offset - moving.lateralOffset))
                        let myCurrentLaneDist = abs(moving.lateralOffset - offset)
                        if distFromOtherSide < clearance && myCurrentLaneDist > 0.4 {
                            costs[idx] += (1.0 - distFromOtherSide / clearance) * distWeight * 1.5
                        }
                    }
                }

                let slowdownClearance = moving.personalRadius + other.personalRadius + 0.05
                if forwardGap > 0.05 && forwardGap <= lookAheadBase * 1.5 && abs(sideGap) < slowdownClearance {
                    if headingAlignment > 0.5 {
                        if forwardGap < nearestFrontGap {
                            nearestFrontGap = forwardGap
                            nearestFrontSpeed = other.currentSpeed
                            nearestFrontOffset = other.lateralOffset
                        }
                    } else if headingAlignment < -0.5 {
                        nearestOncomingGap = min(nearestOncomingGap, forwardGap)
                    }
                    let closeness = max(0, 1.0 - abs(forwardGap) / (lookAheadBase * 1.5))
                    strongestCloseness = max(strongestCloseness, closeness)
                }
                
                // 後ろから速い人が近づいてきているか（追い越されそうか）を判定
                if headingAlignment > 0.5 && forwardGap > -2.0 && forwardGap < -0.1 {
                    if other.currentSpeed > moving.currentSpeed * 1.15 && abs(sideGap) < 1.0 {
                        isBeingOvertaken = true
                    }
                }

                // 横並びの壁化を防ぐ（同方向に横並びになったら前後にずらす）
                if headingAlignment > 0.5 && abs(forwardGap) < 0.8 && abs(sideGap) > 0.3 && abs(sideGap) < 1.5 {
                    if i > otherSnapshot.index {
                        desiredSpeed *= 1.03 // 少しだけ加速して前に出る
                    } else {
                        desiredSpeed *= 0.92 // 少しだけ減速して後ろに下がる
                    }
                }
            }

            // --- ユーザー回避の重み付け ---
            if isHeadAnchored && !moving.isDistracted {
                let userDiff = headPos - currentWorldPos
                let userForwardGap = simd_dot(userDiff, moving.axisDir)
                let userSideGap = simd_dot(userDiff, moving.lateralDir)

                if userForwardGap > -1.0 && userForwardGap < proactiveLookAhead {
                    let distWeight = pow(max(0, 1.0 - userForwardGap / proactiveLookAhead), 1.5)
                    let userClearance = moving.personalRadius + bodyRadius + sideMargin

                    for (idx, offset) in samples.enumerated() {
                        let distFromUserSide = abs(userSideGap - (offset - moving.lateralOffset))
                        if distFromUserSide < userClearance {
                            costs[idx] += (1.0 - distFromUserSide / userClearance) * distWeight * 1.0
                        }
                    }
                }
            }

            // --- 最適な進路の決定（最小コスト探索） ---
            var bestCost: Float = Float.greatestFiniteMagnitude
            var bestOffset: Float = moving.preferredCruiseOffset

            for idx in 0..<sampleCount {
                let distFromCurrent = abs(samples[idx] - moving.lateralOffset)
                // 横移動の距離ペナルティ（無駄に大外へ膨らむのを防ぐが、強すぎると避けなくなるため調整）
                let persistencePenalty = distFromCurrent * 0.60
                let distFromPreferred = abs(samples[idx] - moving.preferredCruiseOffset)
                let centerBias = distFromPreferred * 0.15
                let wallDist = wallLimitTotal - abs(samples[idx])
                let wallPenalty = wallDist < 0.5 ? (0.5 - wallDist) * 3.0 : 0.0
                
                // 対向者と正面衝突しないよう、「左側へ避ける」微小なバイアスを加える（対称性の破壊）
                // offsetが負（左側）の時にコストが下がり、正（右側）の時にコストが上がる
                let keepLeftBias = samples[idx] * 0.08

                let totalCost = costs[idx] + persistencePenalty + wallPenalty + centerBias + keepLeftBias
                
                if totalCost < bestCost {
                    bestCost = totalCost
                    bestOffset = samples[idx]
                }
            }

            let fluidTargetOffset = bestOffset
            var rawDesiredLateral = fluidTargetOffset

            // 自然な「ゆらぎ」の計算
            let waverFreq = 0.4 + Float(i % 5) * 0.1
            let waverAmp: Float = 0.015
            let waver = sin(Float(sceneData.frameCount) * Float(0.016) * waverFreq) * waverAmp

            // 追い越し中または追い越され中の横移動制御
            if isBeingOvertaken {
                // 追い越されている最中は、基本の横移動をフリーズして道を譲る（ゆらぎは残す）
                rawDesiredLateral = moving.lateralOffset + waver
                moving.preferredCruiseOffset = moving.lateralOffset
            } else if moving.overtakeFrameCount > 0 {
                // 追い越す側は、ロックしたレーン（preferredCruiseOffset）へ向かう（ゆらぎは残す）
                rawDesiredLateral = moving.preferredCruiseOffset + waver
            } else {
                // 通常の歩行時
                rawDesiredLateral += waver

                // 進行方向の速度に合わせて元のレーンに戻る速度も調整
                let speedFactorForReturn = max(0.2, moving.currentSpeed / moving.speed)
                let returnRate: Float = 0.01 * speedFactorForReturn
                moving.preferredCruiseOffset += (moving.initialPreferredOffset - moving.preferredCruiseOffset) * returnRate

                if moving.directionChangeCooldown <= 0 {
                    if abs(fluidTargetOffset - moving.preferredCruiseOffset) > 0.45 {
                        moving.directionChangeCooldown = 240
                        moving.preferredCruiseOffset = fluidTargetOffset
                    }
                } else {
                    rawDesiredLateral = moving.preferredCruiseOffset * 0.95 + fluidTargetOffset * 0.05
                }
            }

            // --- ユーザーの手・身体との多点衝突判定 ---
            let panelEntities = sceneData.hudPanelEntities.values.filter { $0.parent != nil }
            let isLeftHandNearUI = isLeftAnchored && panelEntities.contains { distance(leftPos, $0.position(relativeTo: nil)) < 0.35 }
            let isRightHandNearUI = isRightAnchored && panelEntities.contains { distance(rightPos, $0.position(relativeTo: nil)) < 0.35 }
            let isHeadNearUI = isHeadAnchored && panelEntities.contains { distance(headPos, $0.position(relativeTo: nil)) < 0.35 }
            let rotation = moving.entity.transform.rotation
            let isGhostPeriod = moving.traveled < 0.5

            // 手・歩行者の判定座標はすべて worldAnchor 座標系に統一する。
            let pedestrianCenter = currentWorldPos + moving.axisDir * 0.20
            let pedestrianBase = currentWorldPos
            let pedestrianTopY = pedestrianBase.y + scale * 1.25
            
            let headInWorld = sceneData.worldAnchor.convert(position: headPos, from: nil)
            let leftInWorld = leftPos
            let rightInWorld = rightPos

            // --- 身体と歩行者シリンダーの衝突判定（円柱同士の平面距離チェック） ---
            var isBodyHit = false
            var isLeftHandHit = false
            var isRightHandHit = false

            if isHeadAnchored && !isGhostPeriod {
                let horizontalDist = distance(SIMD2<Float>(pedestrianCenter.x, pedestrianCenter.z), SIMD2<Float>(headInWorld.x, headInWorld.z))
                if horizontalDist < (bodyRadius + pedestrianRadius) {
                    isBodyHit = true
                    handContactDetected = true
                }
            }
            
            // --- 手と歩行者シリンダーの衝突判定（球体と円柱のチェック） ---
            // 見えている赤いシリンダーは pedestrianRadius + 0.03 で描画しているため、判定側も同じ余白を含める。
            // 手の高さはトラッキングや姿勢で揺れるため、上下方向は少し広めに見る。
            let handCollisionRadius = handRadius + pedestrianRadius + 0.03
            let handVerticalMargin: Float = 0.35

            if isLeftAnchored && !isGhostPeriod {
                let horizontalDist = distance(SIMD2<Float>(pedestrianCenter.x, pedestrianCenter.z), SIMD2<Float>(leftInWorld.x, leftInWorld.z))
                let verticalOverlap = (leftInWorld.y >= pedestrianBase.y - handVerticalMargin && leftInWorld.y <= pedestrianTopY + handVerticalMargin)
                if verticalOverlap && horizontalDist < handCollisionRadius {
                    isLeftHandHit = true
                    handContactDetected = true
                }
            }
            if isRightAnchored && !isGhostPeriod {
                let horizontalDist = distance(SIMD2<Float>(pedestrianCenter.x, pedestrianCenter.z), SIMD2<Float>(rightInWorld.x, rightInWorld.z))
                let verticalOverlap = (rightInWorld.y >= pedestrianBase.y - handVerticalMargin && rightInWorld.y <= pedestrianTopY + handVerticalMargin)
                if verticalOverlap && horizontalDist < handCollisionRadius {
                    isRightHandHit = true
                    handContactDetected = true
                }
            }

            if handContactDetected {
                var newLeftHandHit = false
                var newRightHandHit = false
                
                if isBodyHit && !moving.hasBeenHitByBody {
                    moving.hasBeenHitByBody = true
                }
                if isLeftHandHit && !moving.hasBeenHitByLeftHand {
                    moving.hasBeenHitByLeftHand = true
                    newLeftHandHit = true
                }
                if isRightHandHit && !moving.hasBeenHitByRightHand {
                    moving.hasBeenHitByRightHand = true
                    newRightHandHit = true
                }
                
                let isAnyHandHit = moving.hasBeenHitByLeftHand || moving.hasBeenHitByRightHand
                let targetType: ExperimentTaskManager.CollisionType
                if moving.hasBeenHitByBody && isAnyHandHit {
                    targetType = .both
                } else if isAnyHandHit {
                    targetType = .handOnly
                } else {
                    targetType = .bodyOnly
                }
                
                if moving.registeredCollisionType == nil {
                    // First time registering contact for this pedestrian
                    sceneData.handContactCount += 1
                    moving.registeredCollisionType = targetType
                    experimentManager.registerOrUpdateCollisionContact(oldType: nil, newType: targetType, isLeftHandHit: newLeftHandHit, isRightHandHit: newRightHandHit)
                    moving.hasCountedUserContact = true
                    moving.handContactCooldown = 15
                } else if targetType != moving.registeredCollisionType {
                    // Upgrade/Update the collision type
                    let oldType = moving.registeredCollisionType!
                    moving.registeredCollisionType = targetType
                    experimentManager.registerOrUpdateCollisionContact(oldType: oldType, newType: targetType, isLeftHandHit: newLeftHandHit, isRightHandHit: newRightHandHit)
                } else {
                    // Even if collision type didn't change, we might have a new hand hit (e.g. hit left hand first, then right hand later)
                    if newLeftHandHit || newRightHandHit {
                        experimentManager.registerOrUpdateCollisionContact(oldType: targetType, newType: targetType, isLeftHandHit: newLeftHandHit, isRightHandHit: newRightHandHit)
                    }
                }
                moving.handContactCooldown = 10
            }

            // --- 速度制御と追い越し判定 ---
            let stopGap = 0.25 + moving.personalRadius * 0.5
            if nearestFrontGap < lookAheadBase {
                if nearestFrontSpeed < moving.speed * 0.85 {
                    // 追い越し開始の瞬間：一番コストが低く安全なレーンを見つけてロックする
                    if moving.overtakeFrameCount == 0 {
                        var bestOffset = moving.lateralOffset
                        var bestCost = Float.greatestFiniteMagnitude
                        for idx in 0..<sampleCount {
                            // 追い越し時のレーン選びでも、現在地から遠すぎるレーンを強く避ける
                            let totalCost = costs[idx] + abs(samples[idx] - moving.lateralOffset) * 1.5
                            if totalCost < bestCost {
                                bestCost = totalCost
                                bestOffset = samples[idx]
                            }
                        }
                        
                        // 壁や他の人に挟まれていて安全な隙間がない場合（コストが高すぎる場合）は追い越しを諦める
                        if bestCost < 1.2 {
                            moving.preferredCruiseOffset = bestOffset
                            // 抜き終わるまで長めにロック（120フレーム = 約2秒）
                            moving.overtakeFrameCount = max(moving.overtakeFrameCount, 120)
                        }
                    }
                    
                    if moving.overtakeFrameCount > 0 {
                        let overtakeFactor = max(0.7, nearestFrontGap / lookAheadBase)
                        desiredSpeed = min(desiredSpeed, moving.speed * overtakeFactor)
                    } else {
                        // 追い越しを諦めた場合は追従に切り替え
                        // パーソナルスペース分を考慮し、より余裕を持って減速する（カルガモ距離の適正化）
                        let safeGapBase: Float = 1.5
                        let physicalGap = max(0.0, nearestFrontGap - (moving.personalRadius * 2.0))
                        let denom = max(0.1, safeGapBase - moving.personalRadius * 2.0)
                        var gapFactor = max(0.05, pow(physicalGap / denom, 1.5))
                        // 相手が自分より速い（抜かした直後など引き離している）場合は急ブレーキをかけない
                        if nearestFrontSpeed > moving.currentSpeed {
                            if nearestFrontGap >= 1.0 {
                                // 十分な距離(1m)が空いたら減速を止める
                                gapFactor = 1.0
                            } else {
                                // 1m未満の場合は85%の速度を維持して自然に距離を空ける
                                gapFactor = max(gapFactor, 0.85)
                            }
                        }
                        let synchronizedSpeed = min(moving.speed, nearestFrontSpeed * 1.0)
                        desiredSpeed = min(desiredSpeed, synchronizedSpeed * gapFactor)
                        
                        // 抜かせない時は前の人の背中（同じレーン）を目標にする
                        moving.preferredCruiseOffset = nearestFrontOffset
                        rawDesiredLateral = nearestFrontOffset
                    }
                } else {
                    // 速度が近い → 通常の車間追従（十分な車間距離を保つ）
                    // パーソナルスペース分を考慮し、より余裕を持って減速する（カルガモ距離の適正化）
                    let safeGapBase: Float = 1.5
                    let physicalGap = max(0.0, nearestFrontGap - (moving.personalRadius * 2.0))
                    let denom = max(0.1, safeGapBase - moving.personalRadius * 2.0)
                    var gapFactor = max(0.05, pow(physicalGap / denom, 1.5))
                    // 相手が自分より速い（抜かした直後など引き離している）場合は急ブレーキをかけない
                    if nearestFrontSpeed > moving.currentSpeed {
                        if nearestFrontGap >= 1.0 {
                            // 十分な距離(1m)が空いたら減速を止める
                            gapFactor = 1.0
                        } else {
                            // 1m未満の場合は85%の速度を維持して自然に距離を空ける
                            gapFactor = max(gapFactor, 0.85)
                        }
                    }
                    let synchronizedSpeed = min(moving.speed, nearestFrontSpeed * 1.0)
                    desiredSpeed = min(desiredSpeed, synchronizedSpeed * gapFactor)
                    
                    // 抜かせない時は前の人の背中（同じレーン）を目標にする
                    moving.preferredCruiseOffset = nearestFrontOffset
                    rawDesiredLateral = nearestFrontOffset
                }
                // 完全停止は最後の手段（物理重なりが解消できない場合のみ）
                if nearestFrontGap < stopGap * 0.5 { moving.yieldFramesRemaining = max(moving.yieldFramesRemaining, 4) }
            }

            if nearestOncomingGap < lookAheadBase {
                // デッドロック（お見合い停止）を防ぐため、対向に対しては完全停止せず最低60%の速度を維持してすり抜ける
                let slowdownFactor = 0.6 + 0.4 * max(0, nearestOncomingGap / lookAheadBase)
                desiredSpeed = min(desiredSpeed, moving.speed * slowdownFactor)
            }
            
            if moving.yieldFramesRemaining > 0 {
                desiredSpeed = 0
                moving.yieldFramesRemaining -= 1
            }

            // 追い越しカウンタの更新
            if moving.overtakeFrameCount > 0 { moving.overtakeFrameCount -= 1 }

            // --- 最終的な位置と向きの更新 ---
            // 減速（dt * 3.5）は比較的早めに行い、加速（dt * 0.9）はより徐々に行う
            moving.currentSpeed += (desiredSpeed - moving.currentSpeed) * (desiredSpeed < moving.currentSpeed ? min(1.0, dt * 3.5) : min(1.0, dt * 0.9))
            let realSpeedPerSec = moving.currentSpeed * 60.0
            var vForward = realSpeedPerSec * speedMultiplier

            let targetLat = max(-wallLimitTotal, min(wallLimitTotal, rawDesiredLateral + max(-0.25, min(0.25, repulsionLateral))))
            // 横移動のグラデーション（滑らかさ）を前進スピードに合わせる（スピードが遅い時は横移動の反応も遅くする）
            let speedFactorForLateral = max(0.2, moving.currentSpeed / moving.speed)
            // ぶつかる前にスムーズに避けられるよう、通常のゲインを少し上げる (0.35 -> 1.5)
            let lateralSmoothGain: Float = isHardColliding ? min(1.0, dt * 5.0) : min(1.0, dt * 1.5 * speedFactorForLateral)
            moving.targetLateralOffset += (targetLat - moving.targetLateralOffset) * lateralSmoothGain
            
            // 追い越し中も横移動は少しだけ速い程度に抑え、急な横スライドを避ける
            let isOvertaking = moving.overtakeFrameCount > 0
            var maxLateralStep = isOvertaking ? 0.36 * dt : 0.26 * dt
            
            // 体の向きが進行方向に対して45度を超えないように、横方向の最大移動量を前進速度に合わせて制限
            // ただし、完全に停止してしまった場合でも横へ回避（カニ歩き）できるよう最低限の横移動力を保証する
            let dynamicMaxLateralStep = max(vForward, 0.8) * dt
            maxLateralStep = min(maxLateralStep, dynamicMaxLateralStep)

            let lateralDiff = moving.targetLateralOffset - moving.lateralOffset
            let lateralStep = max(-maxLateralStep, min(maxLateralStep, lateralDiff))
            moving.lateralOffset += lateralStep

            var vLateralActual = dt > 0.0001 ? (lateralStep / dt) : 0
            
            // ユーザーとの絶対的な当たり判定 (Custom)
            if isHeadAnchored {
                let userPos2D = SIMD2<Float>(headPos.x, headPos.z)
                let myPos2D = SIMD2<Float>(currentWorldPos.x, currentWorldPos.z)
                let diff2D = myPos2D - userPos2D
                let dist = simd_length(diff2D)
                let combinedRadius = bodyRadius + 0.3
                if dist < combinedRadius {
                    let overlap = combinedRadius - dist
                    let pushDir = diff2D / max(0.001, dist)
                    let pushForward = simd_dot(pushDir, SIMD2<Float>(moving.axisDir.x, moving.axisDir.z))
                    let pushLateral = simd_dot(pushDir, SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z))
                    vForward += pushForward * overlap * 5.0
                    vLateralActual += pushLateral * overlap * 5.0
                }
            }
            let velocityVector = moving.axisDir * vForward + moving.lateralDir * vLateralActual
            let totalSpeed = simd_length(velocityVector)
            if totalSpeed > 0.0001 {
                let moveDir = normalize(velocityVector)
                var angle = atan2(moveDir.x, moveDir.z)
                let baseAngle = atan2(moving.axisDir.x, moving.axisDir.z)
                var diff = angle - baseAngle
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                diff = max(-.pi/4, min(.pi/4, diff))
                angle = baseAngle + diff
                let targetQuat = simd_quatf(angle: angle, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 22, axis: [1, 0, 0])
                let rotationSpeed: Float = 1.2 + (moving.currentSpeed * 20.0)
                moving.entity.transform.rotation = simd_slerp(moving.entity.transform.rotation, targetQuat, min(1.0, dt * rotationSpeed))
            }
            
            moving.entity.transform.translation = currentWorldPos
            moving.animationController?.speed = (totalSpeed / 1.2) * speedMultiplier
            moving.traveled += totalSpeed * dt

            if moving.traveled >= moving.travelLimit {
                moving.entity.removeFromParent()
                moving.visualGroup?.removeFromParent()
                moving.visualGroup = nil
                moving.isWaiting = true
            }
        }
        sceneData.movingEntities.removeAll { $0.isWaiting }
    }

    /// ユーザーと手・身体の衝突判定範囲を可視化する
    private func updateUserCollisionVisuals(bodyRadius: Float, handRadius: Float) {
        // 設定された半径が前回から変更された場合は、ビジュアルを再構築
        let bodyRadiusChanged = (sceneData.lastVisualBodyRadius != bodyRadius)
        let handRadiusChanged = (sceneData.lastVisualHandRadius != handRadius)
        
        if bodyRadiusChanged {
            sceneData.lastVisualBodyRadius = bodyRadius
            if let existing = sceneData.userBodyVisual {
                existing.removeFromParent()
                sceneData.userBodyVisual = nil
            } else {
                if let existing = sceneData.worldAnchor.findEntity(named: "UserBodyVisual") {
                    existing.removeFromParent()
                }
            }
            if let existing = sceneData.headAnchor.findEntity(named: "UserBodyVisual") {
                existing.removeFromParent()
            }
        }
        
        if handRadiusChanged {
            sceneData.lastVisualHandRadius = handRadius
            if let existing = sceneData.userLeftHandVisual {
                existing.removeFromParent()
                sceneData.userLeftHandVisual = nil
            } else {
                if let existing = sceneData.worldAnchor.findEntity(named: "UserLeftHandVisual") {
                    existing.removeFromParent()
                }
            }
            if let existing = sceneData.userRightHandVisual {
                existing.removeFromParent()
                sceneData.userRightHandVisual = nil
            } else {
                if let existing = sceneData.worldAnchor.findEntity(named: "UserRightHandVisual") {
                    existing.removeFromParent()
                }
            }
            
            // Clean up leftHandAnchor / rightHandAnchor hands / debug visuals since radius changed
            if let existing = sceneData.leftHandAnchor.findEntity(named: "UserLeftHandVisual") {
                existing.removeFromParent()
            }
            if let existing = sceneData.rightHandAnchor.findEntity(named: "UserRightHandVisual") {
                existing.removeFromParent()
            }
            if let existing = sceneData.worldAnchor.findEntity(named: "UserLeftHandCollisionDebug") {
                existing.removeFromParent()
            }
            if let existing = sceneData.worldAnchor.findEntity(named: "UserRightHandCollisionDebug") {
                existing.removeFromParent()
            }
            if let existing = sceneData.leftHandAnchor.findEntity(named: "UserLeftHandCollisionDebug") {
                existing.removeFromParent()
            }
            if let existing = sceneData.rightHandAnchor.findEntity(named: "UserRightHandCollisionDebug") {
                existing.removeFromParent()
            }
        }

        // ヘッド（胴体・身体）の衝突シリンダー
        // 衝突判定と同じ WorldTrackingProvider の device position を使い、見た目と当たり判定を完全に一致させる。
        if let deviceAnchor = sceneData.worldTracking.queryDeviceAnchor(atTimestamp: CACurrentMediaTime()) {
            let transform = deviceAnchor.originFromAnchorTransform
            let t = transform.columns.3
            let zAxis = transform.columns.2
            sceneData.latestDevicePosition = SIMD3<Float>(t.x, t.y, t.z)
            // deviceAnchor の -Z 方向を「ユーザーが向いている前方」として扱う。
            sceneData.latestDeviceForward = simd_normalize(SIMD3<Float>(-zAxis.x, -zAxis.y, -zAxis.z))
            sceneData.hasDevicePosition = true
        }

        let headWorldPos = sceneData.hasDevicePosition ? sceneData.latestDevicePosition : sceneData.headAnchor.position(relativeTo: nil)
        let bodyHeight: Float = 1.45
        let bodyYOffset: Float = -bodyHeight / 2.0 + 0.10
        // Vision Pro本体は実際の頭中心より少し前方にあるため、自分の向きを基準に身体シリンダーを約30cm後方へ補正する。
        let backwardOffset: Float = 0.15

        if sceneData.userBodyVisual == nil {
            if let existing = sceneData.worldAnchor.findEntity(named: "UserBodyVisual") as? ModelEntity {
                sceneData.userBodyVisual = existing
            } else {
                let visual = ModelEntity(
                    mesh: .generateCylinder(height: bodyHeight, radius: bodyRadius),
                    materials: [UnlitMaterial(color: .systemBlue.withAlphaComponent(0.25))]
                )
                visual.name = "UserBodyVisual"
                sceneData.worldAnchor.addChild(visual)
                sceneData.userBodyVisual = visual

                // ユーザーはシリンダーの内側にいるため、側面はバックフェイスカリングで見えにくい。
                // そのため、床付近に見えるデバッグ用ディスクを追加する。
                let floorDisc = ModelEntity(
                    mesh: .generateCylinder(height: 0.015, radius: bodyRadius),
                    materials: [UnlitMaterial(color: .systemBlue.withAlphaComponent(0.25))]
                )
                floorDisc.name = "UserBodyFloorDisc"
                floorDisc.position = SIMD3<Float>(0, -bodyHeight / 2.0 + 0.02, 0)
                visual.addChild(floorDisc)
            }
        }

        if let visual = sceneData.userBodyVisual {
            // worldAnchor空間で、実際のVision Pro本体位置より、自分の向きを基準に少し後方へ配置する。
            let rawForward = sceneData.hasDevicePosition ? sceneData.latestDeviceForward : simd_act(sceneData.headAnchor.orientation(relativeTo: nil), SIMD3<Float>(0, 0, -1))
            let forward = simd_normalize(SIMD3<Float>(rawForward.x, 0, rawForward.z))
            let correctedPosition = headWorldPos - forward * backwardOffset

            visual.position = SIMD3<Float>(
                correctedPosition.x,
                correctedPosition.y + bodyYOffset,
                correctedPosition.z
            )
            // 向きもユーザーの向きに連動させる。ただしシリンダーが傾かないよう、Yaw成分のみ反映する。
            let yaw = atan2(forward.x, -forward.z)
            visual.orientation = simd_quatf(angle: yaw, axis: SIMD3<Float>(0, 1, 0))
            visual.isEnabled = panelModel.showCollisionVisuals

            if bodyRadiusChanged {
                if var model = visual.components[ModelComponent.self] {
                    model.materials = [UnlitMaterial(color: .systemBlue.withAlphaComponent(0.25))]
                    visual.components.set(model)
                }

                if let floorDisc = visual.findEntity(named: "UserBodyFloorDisc") as? ModelEntity {
                    floorDisc.position = SIMD3<Float>(0, -bodyHeight / 2.0 + 0.02, 0)
                    floorDisc.isEnabled = panelModel.showCollisionVisuals
                    if var model = floorDisc.components[ModelComponent.self] {
                        model.materials = [UnlitMaterial(color: .systemBlue.withAlphaComponent(0.25))]
                        floorDisc.components.set(model)
                    }
                }
            } else {
                if let floorDisc = visual.findEntity(named: "UserBodyFloorDisc") as? ModelEntity {
                    floorDisc.isEnabled = panelModel.showCollisionVisuals
                }
            }
        }
        
        // 左手: 物理判定と表示座標の完全一致
        if sceneData.userLeftHandVisual == nil {
            if let existing = sceneData.worldAnchor.findEntity(named: "UserLeftHandVisual") as? ModelEntity {
                sceneData.userLeftHandVisual = existing
            } else {
                let visual = ModelEntity(
                    mesh: .generateSphere(radius: handRadius),
                    materials: [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.20), isMetallic: false)]
                )
                visual.name = "UserLeftHandVisual"
                sceneData.worldAnchor.addChild(visual)
                sceneData.userLeftHandVisual = visual
            }
        }

        if let visual = sceneData.userLeftHandVisual {
            visual.position = sceneData.latestLeftHandPosition
            let isVisible = panelModel.showCollisionVisuals && sceneData.hasLeftHandPosition
            visual.isEnabled = isVisible
            
            if handRadiusChanged {
                if var model = visual.components[ModelComponent.self] {
                    model.materials = [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.20), isMetallic: false)]
                    visual.components.set(model)
                }
            }
        }

        // 右手: 物理判定と表示座標の完全一致
        if sceneData.userRightHandVisual == nil {
            if let existing = sceneData.worldAnchor.findEntity(named: "UserRightHandVisual") as? ModelEntity {
                sceneData.userRightHandVisual = existing
            } else {
                let visual = ModelEntity(
                    mesh: .generateSphere(radius: handRadius),
                    materials: [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.20), isMetallic: false)]
                )
                visual.name = "UserRightHandVisual"
                sceneData.worldAnchor.addChild(visual)
                sceneData.userRightHandVisual = visual
            }
        }

        if let visual = sceneData.userRightHandVisual {
            visual.position = sceneData.latestRightHandPosition
            let isVisible = panelModel.showCollisionVisuals && sceneData.hasRightHandPosition
            visual.isEnabled = isVisible
            
            if handRadiusChanged {
                if var model = visual.components[ModelComponent.self] {
                    model.materials = [SimpleMaterial(color: .systemYellow.withAlphaComponent(0.20), isMetallic: false)]
                    visual.components.set(model)
                }
            }
        }
    }

    private func updatePedestriansSFM(deltaTime: TimeInterval, dt: Float, leftPos: SIMD3<Float>, rightPos: SIMD3<Float>, isLeftAnchored: Bool, isRightAnchored: Bool, headPos: SIMD3<Float>, isHeadAnchored: Bool, speedMultiplier: Float) {
        let wallLimitTotal = Float(panelModel.peopleHorizontalRange)
        let yOffset = Float(panelModel.peopleHeightOffset)
        
        let tau: Float = 0.5 // 緩和時間
        let A: Float = 3.0 // 対人斥力係数
        let B: Float = 0.8 // 対人斥力の減衰距離
        let A_wall: Float = 5.0 // 壁の斥力係数
        let B_wall: Float = 0.2 // 壁の斥力の減衰距離
        let A_user: Float = 4.0 // ユーザーへの斥力係数
        let B_user: Float = 0.5 // ユーザーへの斥力の減衰距離
        
        struct EntitySnapshot {
            let index: Int
            let worldPos: SIMD3<Float>
            let moving: MovingEntity
            let radius: Float
        }
        
        var snapshots: [EntitySnapshot] = []
        for i in sceneData.movingEntities.indices {
            let moving = sceneData.movingEntities[i]
            if moving.isWaiting { continue }
            var pos = moving.origin + moving.axisDir * moving.traveled
            pos.y = yOffset
            let worldPos = pos + moving.lateralDir * moving.lateralOffset
            let physicalScale = moving.entity.scale.x / 1.8
            let radius = 0.20 * physicalScale
            snapshots.append(EntitySnapshot(index: i, worldPos: worldPos, moving: moving, radius: radius))
        }
        
        for snapshot in snapshots {
            let moving = snapshot.moving
            let currentWorldPos = snapshot.worldPos
            let v_i = moving.velocity2D
            
            // 1. 目的地への引力 (Driving Force) (15%減速)
            let desiredSpeed = (moving.speed * 60.0) * speedMultiplier * 0.85
            let e_goal = SIMD2<Float>(moving.axisDir.x, moving.axisDir.z)
            let v_desired = e_goal * desiredSpeed
            
            var force = (v_desired - v_i) / tau
            
            // 2. 対人斥力 (Repulsive Force)
            var isColliding = false
            for otherSnapshot in snapshots where otherSnapshot.index != snapshot.index {
                let diff = snapshot.worldPos - otherSnapshot.worldPos
                let diff2D = SIMD2<Float>(diff.x, diff.z)
                let dist = simd_length(diff2D)
                if dist > 0.001 {
                    let n_ij = diff2D / dist
                    // --- 斥力を進行方向に伸ばす（楕円形） ---
                    let physAxisDir2D = SIMD2<Float>(moving.axisDir.x, moving.axisDir.z)
                    let physLateralDir2D = SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z)
                    let forwardDist = -simd_dot(diff2D, physAxisDir2D) // 相手が自分の前方ならプラス
                    let lateralDist = simd_dot(diff2D, physLateralDir2D)
                    var effectiveDist = dist
                    if forwardDist > 0 {
                        // 前方の距離を短く見積もることで、遠くからでも強い斥力を生ませる
                        effectiveDist = sqrt((forwardDist * 0.4) * (forwardDist * 0.4) + lateralDist * lateralDist)
                    }
                    let d_ij = effectiveDist - (snapshot.radius + otherSnapshot.radius)
                    
                    // 視野ファクター：後ろにいる人からの影響は小さくする
                    var dotProd: Float = 1.0
                    if simd_length_squared(v_i) > 0.001 {
                        dotProd = simd_dot(n_ij, simd_normalize(v_i))
                    }
                    let viewFactor: Float = dotProd > -0.1 ? 1.0 : 0.3
                    
                    // 接触時 (d_ij < 0) は強力なバネ的斥力を追加して突き抜けを防止
                    if d_ij < 0 { isColliding = true }
                    let penetrationForce = d_ij < 0 ? A * 20.0 * (-d_ij) : 0.0
                    let magnitude = A * exp(-max(0, d_ij) / B) * viewFactor + penetrationForce
                    
                    // 正面衝突（お見合い）の場合は横に弾き飛ばす力を追加（対称性の打破）
                    var pushDir = n_ij
                    if abs(pushDir.x) < 0.2 {
                        let avoidSign: Float = moving.lateralOffset >= 0 ? 1.0 : -1.0
                        pushDir.x += avoidSign * 0.5
                        pushDir = simd_normalize(pushDir)
                    }
                    
                    force += magnitude * pushDir
                }
            }
            
            // 3. 壁の斥力 (Wall Repulsion)
            let rightWallDist = wallLimitTotal - moving.lateralOffset
            let leftWallDist = moving.lateralOffset - (-wallLimitTotal)
            let wallLateralDir2D = SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z)
            
            if rightWallDist > 0 {
                let magnitude = A_wall * exp(-rightWallDist / B_wall)
                force += magnitude * (-wallLateralDir2D)
            }
            if leftWallDist > 0 {
                let magnitude = A_wall * exp(-leftWallDist / B_wall)
                force += magnitude * (wallLateralDir2D)
            }
            
            // 4. ユーザーからの斥力
            if isHeadAnchored {
                let userPos2D = SIMD2<Float>(headPos.x, headPos.z)
                let myPos2D = SIMD2<Float>(currentWorldPos.x, currentWorldPos.z)
                let diff2D = myPos2D - userPos2D
                let dist = simd_length(diff2D)
                if dist > 0.001 {
                    let n_ij = diff2D / dist
                    let bodyRadius: Float = 0.25
                    let d_ij = dist - (snapshot.radius + bodyRadius)
                    let magnitude = A_user * exp(-max(0, d_ij) / B_user)
                    force += magnitude * n_ij
                }
            }
            
            // 加速度による速度更新
            moving.velocity2D += force * dt
            
            // 速度の制限

            let speedSq = simd_length_squared(moving.velocity2D)
            let maxSpeed = desiredSpeed * 1.5
            if speedSq > maxSpeed * maxSpeed {
                moving.velocity2D = simd_normalize(moving.velocity2D) * maxSpeed
            }
            
            // 物理的な横方向の速度を前進速度の100% (45度) までに制限する
            let physAxisDir2D = SIMD2<Float>(moving.axisDir.x, moving.axisDir.z)
            let physLateralDir2D = SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z)
            var vForward = simd_dot(moving.velocity2D, physAxisDir2D)
            var vLateral = simd_dot(moving.velocity2D, physLateralDir2D)
            
            // ぶつかっても反転（後ろ歩き）しないように下限を0にする（止まることを許可）
            vForward = max(0.0, vForward)
            
            // 人混みでやむを得ず立ち止まりそうになった場合（詰まった場合）は45度制限を解除し、カニ歩きで逃げられるようにする
            let lateralSpeedLimit = (vForward < desiredSpeed * 0.5) ? (desiredSpeed * 0.6) : (max(0.1, vForward) * 1.0)
            if abs(vLateral) > lateralSpeedLimit {
                vLateral = (vLateral > 0 ? Float(1.0) : Float(-1.0)) * lateralSpeedLimit
            }
            moving.velocity2D = physAxisDir2D * vForward + physLateralDir2D * vLateral

            
            // 位置の更新
            let delta2D = moving.velocity2D * dt
            let forwardMove = simd_dot(delta2D, SIMD2<Float>(moving.axisDir.x, moving.axisDir.z))
            let lateralMove = simd_dot(delta2D, SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z))
            
            moving.traveled += forwardMove
            moving.lateralOffset += lateralMove
            moving.targetLateralOffset = moving.lateralOffset
            moving.currentSpeed = simd_length(moving.velocity2D) / speedMultiplier
            
            var newPos = moving.origin + moving.axisDir * moving.traveled
            newPos.y = yOffset
            let finalWorldPos = newPos + moving.lateralDir * moving.lateralOffset
            
            moving.entity.position = finalWorldPos
            moving.animationController?.speed = (moving.currentSpeed / 1.2) * speedMultiplier
            
            if simd_length_squared(moving.velocity2D) > 0.0001 {
                let moveDir = normalize(SIMD3<Float>(moving.velocity2D.x, 0, moving.velocity2D.y))
                let angle = atan2(moveDir.x, moveDir.z)
                let targetQuat = simd_quatf(angle: angle, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 22, axis: [1, 0, 0])
                moving.entity.transform.rotation = simd_slerp(moving.entity.transform.rotation, targetQuat, min(1.0, dt * 10.0))
            }
            
            if moving.traveled >= moving.travelLimit {
                moving.entity.removeFromParent()
                moving.visualGroup?.removeFromParent()
                moving.visualGroup = nil
                moving.isWaiting = true
            }
        }
        sceneData.movingEntities.removeAll { $0.isWaiting }
    }

    private func updatePedestriansRVO(deltaTime: TimeInterval, dt: Float, leftPos: SIMD3<Float>, rightPos: SIMD3<Float>, isLeftAnchored: Bool, isRightAnchored: Bool, headPos: SIMD3<Float>, isHeadAnchored: Bool, speedMultiplier: Float) {
        let wallLimitTotal = Float(panelModel.peopleHorizontalRange)
        let yOffset = Float(panelModel.peopleHeightOffset)
        let timeHorizon: Float = 3.0 // 何秒先までの衝突を考慮するか
        let maxSpeedFactor: Float = 1.3
        
        struct EntitySnapshot {
            let index: Int
            let worldPos: SIMD3<Float>
            let moving: MovingEntity
            let radius: Float
            let vel: SIMD2<Float>
        }
        
        var snapshots: [EntitySnapshot] = []
        for i in sceneData.movingEntities.indices {
            let moving = sceneData.movingEntities[i]
            if moving.isWaiting { continue }
            var pos = moving.origin + moving.axisDir * moving.traveled
            pos.y = yOffset
            let worldPos = pos + moving.lateralDir * moving.lateralOffset
            let physicalScale = moving.entity.scale.x / 1.8
            let radius = 0.20 * physicalScale
            snapshots.append(EntitySnapshot(index: i, worldPos: worldPos, moving: moving, radius: radius, vel: moving.velocity2D))
        }
        
        for snapshot in snapshots {
            let moving = snapshot.moving
            let currentWorldPos = snapshot.worldPos
            let myPos2D = SIMD2<Float>(currentWorldPos.x, currentWorldPos.z)
            let myRad = snapshot.radius
            let currentVel = moving.velocity2D
            
            // 目標速度 (15%減速)
            let desiredSpeed = (moving.speed * 60.0) * speedMultiplier * 0.85
            let e_goal = SIMD2<Float>(moving.axisDir.x, moving.axisDir.z)
            let prefVel = e_goal * desiredSpeed
            
            // 速度空間のサンプリング
            let sampleCount = 30
            var isColliding = false
            var bestVel = currentVel
            var minPenalty: Float = Float.greatestFiniteMagnitude
            
            for i in 0..<sampleCount {
                // 円板上のランダムまたは一様なサンプリング
                let r = sqrt(sceneData.randomGen.nextFloat()) * (desiredSpeed * maxSpeedFactor)
                let theta = sceneData.randomGen.nextFloat() * 2.0 * .pi
                var candVel = prefVel
                if i > 0 { // 0番目はpreferredVelocityをテスト
                    candVel = SIMD2<Float>(cos(theta), sin(theta)) * r
                }
                
                // 1. 目標速度との差によるペナルティ
                let diffToPref = simd_length(candVel - prefVel)
                var penalty = diffToPref * 1.0
                
                // (慣性ペナルティは本来のRVOアルゴリズムにはないため削除)
                
                // 3. 他の歩行者とのTTC(Time To Collision)ペナルティ
                var minTTC = timeHorizon
                for other in snapshots where other.index != snapshot.index {
                    let relPos = SIMD2<Float>(other.worldPos.x, other.worldPos.z) - myPos2D
                    // 互いの責任を半々にする (Reciprocal) ため、相手の速度の平均を考慮
                    // candVelとother.velの相対速度
                    let relVel = candVel - other.vel
                    let combinedRad = myRad + other.radius + 0.1 // 安全マージン
                    
                    let a = simd_length_squared(relVel)
                    let b = -2.0 * simd_dot(relVel, relPos)
                    let c = simd_length_squared(relPos) - combinedRad * combinedRad
                    
                    if c < 0 {
                        // 既に衝突している場合、相手に向かう速度ほど大きなペナルティ
                        let approachSpeed = -simd_dot(relVel, simd_normalize(relPos))
                        if approachSpeed > 0 {
                            penalty += approachSpeed * 100.0
                        }
                        isColliding = true
                        minTTC = 0.0
                        break
                    }
                    if a > 0.0001 && b > 0 {
                        let discriminant = b * b - 4 * a * c
                        if discriminant > 0 {
                            let t = (b - sqrt(discriminant)) / (2 * a)
                            if t > 0 && t < minTTC {
                                minTTC = t
                            }
                        }
                    }
                }
                
                // ユーザーとのTTC
                if isHeadAnchored {
                    let userPos2D = SIMD2<Float>(headPos.x, headPos.z)
                    let relPos = userPos2D - myPos2D
                    let relVel = candVel // ユーザーは静止または独自の動きとみなす
                    let combinedRad = myRad + 0.25 + 0.2 // マージン大きめ
                    
                    let a = simd_length_squared(relVel)
                    if a > 0.0001 {
                        let b = -2.0 * simd_dot(relVel, relPos)
                        let c = simd_length_squared(relPos) - combinedRad * combinedRad
                        
                        if c < 0 { minTTC = 0.0 }
                        else if b > 0 {
                            let discriminant = b * b - 4 * a * c
                            if discriminant > 0 {
                                let t = (b - sqrt(discriminant)) / (2 * a)
                                if t > 0 && t < minTTC { minTTC = t }
                            }
                        }
                    }
                }
                
                // 壁との衝突予測 (横方向の制限)
                // 横方向の速度成分
                let lateralVel = simd_dot(candVel, SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z))
                if lateralVel > 0 {
                    let distToWall = wallLimitTotal - moving.lateralOffset
                    let t = distToWall / lateralVel
                    if t > 0 && t < minTTC { minTTC = t }
                } else if lateralVel < 0 {
                    let distToWall = moving.lateralOffset - (-wallLimitTotal)
                    let t = distToWall / abs(lateralVel)
                    if t > 0 && t < minTTC { minTTC = t }
                }
                
                if minTTC < timeHorizon {
                    penalty += (timeHorizon - minTTC) * 5.0 / max(0.01, minTTC)
                }
                
                // 進行方向への逆走ペナルティ（後ろに戻らないようにする）
                if simd_dot(candVel, e_goal) < -0.1 {
                    penalty += 10.0
                }
                
                if penalty < minPenalty {
                    minPenalty = penalty
                    bestVel = candVel
                }
            }
            
            // 速度の更新（滑らかに）
            moving.velocity2D += (bestVel - moving.velocity2D) * min(1.0, dt * 5.0)
            
            // 位置の更新
            let delta2D = moving.velocity2D * dt
            let forwardMove = simd_dot(delta2D, SIMD2<Float>(moving.axisDir.x, moving.axisDir.z))
            let lateralMove = simd_dot(delta2D, SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z))
            
            moving.traveled += forwardMove
            moving.lateralOffset += lateralMove
            moving.targetLateralOffset = moving.lateralOffset
            moving.currentSpeed = simd_length(moving.velocity2D) / speedMultiplier
            
            var newPos = moving.origin + moving.axisDir * moving.traveled
            newPos.y = yOffset
            let finalWorldPos = newPos + moving.lateralDir * moving.lateralOffset
            
            moving.entity.position = finalWorldPos
            moving.animationController?.speed = (moving.currentSpeed / 1.2) * speedMultiplier
            
            if simd_length_squared(moving.velocity2D) > 0.0001 {
                let moveDir = normalize(SIMD3<Float>(moving.velocity2D.x, 0, moving.velocity2D.y))
                let angle = atan2(moveDir.x, moveDir.z)
                let targetQuat = simd_quatf(angle: angle, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 22, axis: [1, 0, 0])
                moving.entity.transform.rotation = simd_slerp(moving.entity.transform.rotation, targetQuat, min(1.0, dt * 10.0))
            }
            
            if moving.traveled >= moving.travelLimit {
                moving.entity.removeFromParent()
                moving.visualGroup?.removeFromParent()
                moving.visualGroup = nil
                moving.isWaiting = true
            }
        }
        sceneData.movingEntities.removeAll { $0.isWaiting }
    }
    
    private func updatePedestriansHybrid(deltaTime: TimeInterval, dt: Float, leftPos: SIMD3<Float>, rightPos: SIMD3<Float>, isLeftAnchored: Bool, isRightAnchored: Bool, headPos: SIMD3<Float>, isHeadAnchored: Bool, speedMultiplier: Float) {
        let wallLimitTotal = Float(panelModel.peopleHorizontalRange)
        let yOffset = Float(panelModel.peopleHeightOffset)
        
        let tau: Float = 0.5
        let A: Float = 3.0
        let B: Float = 0.4
        let A_wall: Float = 5.0
        let B_wall: Float = 0.2
        let A_user: Float = 4.0
        let B_user: Float = 0.5
        
        struct EntitySnapshot {
            let index: Int
            let worldPos: SIMD3<Float>
            let moving: MovingEntity
            let radius: Float
        }
        
        var snapshots: [EntitySnapshot] = []
        for i in sceneData.movingEntities.indices {
            let moving = sceneData.movingEntities[i]
            if moving.isWaiting { continue }
            var pos = moving.origin + moving.axisDir * moving.traveled
            pos.y = yOffset
            let worldPos = pos + moving.lateralDir * moving.lateralOffset
            let physicalScale = moving.entity.scale.x / 1.8
            let radius = 0.20 * physicalScale
            snapshots.append(EntitySnapshot(index: i, worldPos: worldPos, moving: moving, radius: radius))
        }
        
        for snapshot in snapshots {
            let moving = snapshot.moving
            let currentWorldPos = snapshot.worldPos
            let v_i = moving.velocity2D
            
            // 1. 目的地への引力 (Driving Force)
            // ハイブリッドモデルでは速度を10%程度抑えてより落ち着いた動きに
            let desiredSpeed = (moving.speed * 60.0) * speedMultiplier * 0.75
            let e_goal = SIMD2<Float>(moving.axisDir.x, moving.axisDir.z)
            let v_desired = e_goal * desiredSpeed
            
            var force = (v_desired - v_i) / tau
            
            // 2. 早期のすれ違い回避 (Predictive Dodging)
            // 前方の対向者や遅い人を検知して早めに横へ避ける力を加える
            var dodgeForce = SIMD2<Float>(0, 0)
            var isColliding = false
            for otherSnapshot in snapshots where otherSnapshot.index != snapshot.index {
                let diff = otherSnapshot.worldPos - snapshot.worldPos
                let forwardDist = simd_dot(diff, moving.axisDir)
                let lateralDist = simd_dot(diff, moving.lateralDir)
                
                // 1.5m 〜 7.0m 前方にいる人に対して反応
                if forwardDist > 1.5 && forwardDist < 7.0 {
                    let combinedRadius = snapshot.radius + otherSnapshot.radius + 0.6 // 余裕を持たせる
                    if abs(lateralDist) < combinedRadius {
                        // 向かい合っている（対向している）か、相手が遅い場合のみ避ける
                        let otherVel = otherSnapshot.moving.velocity2D
                        let relVel = v_i - otherVel
                        let axisDir2D = SIMD2<Float>(moving.axisDir.x, moving.axisDir.z)
                        let approachSpeed = simd_dot(relVel, axisDir2D)
                        
                        if approachSpeed > 0.1 { // 近づいている場合のみ
                            let dodgeDir = lateralDist >= 0 ? -moving.lateralDir : moving.lateralDir
                            // ドッジ（回避）の力を強めて、早期に確実に横へ避けるようにする
                            let dodgeMagnitude: Float = 3.0 * approachSpeed / max(0.5, forwardDist)
                            dodgeForce += SIMD2<Float>(dodgeDir.x, dodgeDir.z) * dodgeMagnitude
                        }
                    }
                }
            }
            force += dodgeForce
            
            // 3. レーン維持力 (Lane Keeping)
            // 自分が最初に割り当てられたレーン（initialPreferredOffset）に緩やかに戻ろうとする力
            let laneError = moving.initialPreferredOffset - moving.lateralOffset
            // ダンピングを追加して左右の揺れ（振動）を防ぐ
            let lateralVel = simd_dot(v_i, SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z))
            let laneForceMagnitude = laneError * 1.5 - lateralVel * 1.5
            let laneForce = SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z) * laneForceMagnitude
            force += laneForce
            
            // 4. 対人斥力 (Social Force) - 近距離での衝突回避
            for otherSnapshot in snapshots where otherSnapshot.index != snapshot.index {
                let diff = snapshot.worldPos - otherSnapshot.worldPos
                let diff2D = SIMD2<Float>(diff.x, diff.z)
                let dist = simd_length(diff2D)
                if dist > 0.001 {
                    let n_ij = diff2D / dist
                    let d_ij = dist - (snapshot.radius + otherSnapshot.radius)
                    var dotProd: Float = 1.0
                    if simd_length_squared(v_i) > 0.001 {
                        dotProd = simd_dot(n_ij, simd_normalize(v_i))
                    }
                    let viewFactor: Float = dotProd > -0.1 ? 1.0 : 0.3
                    
                    // 接触時 (d_ij < 0) は強力なバネ的斥力を追加して突き抜けを防止
                    if d_ij < 0 { isColliding = true }
                    let penetrationForce = d_ij < 0 ? A * 20.0 * (-d_ij) : 0.0
                    let magnitude = A * exp(-max(0, d_ij) / B) * viewFactor + penetrationForce
                    
                    // 正面衝突（お見合い）の場合は横に弾き飛ばす力を追加（対称性の打破）
                    var pushDir = n_ij
                    if abs(pushDir.x) < 0.2 {
                        let avoidSign: Float = moving.lateralOffset >= 0 ? 1.0 : -1.0
                        pushDir.x += avoidSign * 0.5
                        pushDir = simd_normalize(pushDir)
                    }
                    
                    force += magnitude * pushDir
                }
            }
            
            // 5. 壁からの斥力
            let rightWallDist = wallLimitTotal - moving.lateralOffset
            let leftWallDist = moving.lateralOffset - (-wallLimitTotal)
            let lateralDir2D = SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z)
            
            if rightWallDist > 0 {
                let magnitude = A_wall * exp(-rightWallDist / B_wall)
                force += magnitude * (-lateralDir2D)
            }
            if leftWallDist > 0 {
                let magnitude = A_wall * exp(-leftWallDist / B_wall)
                force += magnitude * lateralDir2D
            }
            
            // 6. ユーザーからの絶対的な当たり判定・斥力
            if isHeadAnchored {
                let userPos2D = SIMD2<Float>(headPos.x, headPos.z)
                let myPos2D = SIMD2<Float>(currentWorldPos.x, currentWorldPos.z)
                let diff2D = myPos2D - userPos2D
                let dist = simd_length(diff2D)
                if dist > 0.001 {
                    let n_ij = diff2D / dist
                    let bodyRadius: Float = 0.3
                    let d_ij = dist - (snapshot.radius + bodyRadius)
                    if d_ij < 0 { isColliding = true }
                    // 接触時は強力な剛体ペナルティ
                    let penetrationForce = d_ij < 0 ? A_user * 30.0 * (-d_ij) : 0.0
                    let magnitude = A_user * exp(-max(0, d_ij) / B_user) + penetrationForce
                    force += magnitude * n_ij
                }
            }
            
            // 速度の更新
            moving.velocity2D += force * dt
            

            let speedSq = simd_length_squared(moving.velocity2D)
            let maxSpeed = desiredSpeed * 1.5
            if speedSq > maxSpeed * maxSpeed {
                moving.velocity2D = simd_normalize(moving.velocity2D) * maxSpeed
            }
            
            // 物理的な横方向の速度を前進速度の100% (45度) までに制限する
            let physAxisDir2D = SIMD2<Float>(moving.axisDir.x, moving.axisDir.z)
            let physLateralDir2D = SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z)
            var vForward = simd_dot(moving.velocity2D, physAxisDir2D)
            var vLateral = simd_dot(moving.velocity2D, physLateralDir2D)
            
            // ぶつかっても反転（後ろ歩き）しないように下限を0にする（止まることを許可）
            vForward = max(0.0, vForward)
            
            // 人混みでやむを得ず立ち止まりそうになった場合（詰まった場合）は45度制限を解除し、カニ歩きで逃げられるようにする
            let lateralSpeedLimit = (vForward < desiredSpeed * 0.5) ? (desiredSpeed * 0.6) : (max(0.1, vForward) * 1.0)
            if abs(vLateral) > lateralSpeedLimit {
                vLateral = (vLateral > 0 ? Float(1.0) : Float(-1.0)) * lateralSpeedLimit
            }
            moving.velocity2D = physAxisDir2D * vForward + physLateralDir2D * vLateral

            
            let delta2D = moving.velocity2D * dt
            let forwardMove = simd_dot(delta2D, SIMD2<Float>(moving.axisDir.x, moving.axisDir.z))
            let lateralMove = simd_dot(delta2D, SIMD2<Float>(moving.lateralDir.x, moving.lateralDir.z))
            
            moving.traveled += forwardMove
            moving.lateralOffset += lateralMove
            moving.targetLateralOffset = moving.lateralOffset
            moving.currentSpeed = simd_length(moving.velocity2D) / speedMultiplier
            
            var newPos = moving.origin + moving.axisDir * moving.traveled
            newPos.y = yOffset
            let finalWorldPos = newPos + moving.lateralDir * moving.lateralOffset
            
            moving.entity.position = finalWorldPos
            moving.animationController?.speed = (moving.currentSpeed / 1.2) * speedMultiplier
            
            if simd_length_squared(moving.velocity2D) > 0.0001 {
                let moveDir = normalize(SIMD3<Float>(moving.velocity2D.x, 0, moving.velocity2D.y))
                var angle = atan2(moveDir.x, moveDir.z)
                let baseAngle = atan2(moving.axisDir.x, moving.axisDir.z)
                var diff = angle - baseAngle
                while diff > .pi { diff -= 2 * .pi }
                while diff < -.pi { diff += 2 * .pi }
                diff = max(-.pi/4, min(.pi/4, diff))
                angle = baseAngle + diff
                let targetQuat = simd_quatf(angle: angle, axis: [0, 1, 0]) * simd_quatf(angle: .pi / 22, axis: [1, 0, 0])
                moving.entity.transform.rotation = simd_slerp(moving.entity.transform.rotation, targetQuat, min(1.0, dt * 10.0))
            }
            
            if moving.traveled >= moving.travelLimit {
                moving.entity.removeFromParent()
                moving.visualGroup?.removeFromParent()
                moving.visualGroup = nil
                moving.isWaiting = true
            }
        }
        sceneData.movingEntities.removeAll { $0.isWaiting }
    }
}