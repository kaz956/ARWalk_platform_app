import SwiftUI
import UniformTypeIdentifiers

struct ExperimentView: View {
    @EnvironmentObject private var panelModel: PanelModel
    @EnvironmentObject private var experimentManager: ExperimentTaskManager
    @State private var isImmersiveSpaceActive = false
    @State private var didAttemptAutoOpen = false
    @State private var exportDocument = ExportedCSVDocument(data: Data(), suggestedFilename: "session")
    @State private var isExportingFile = false
    @Environment(\.openImmersiveSpace) private var openImmersiveSpace
    @Environment(\.dismissImmersiveSpace) private var dismissImmersiveSpace

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                immersiveControls
                experimentControls
                // taskConfigControls
                panelControls
                optimalZoneControls
                peopleControls
            }
            .padding()
            .frame(maxWidth: 760)
        }
        .task {
            guard !didAttemptAutoOpen else { return }
            didAttemptAutoOpen = true
            panelModel.applyCondition(experimentManager.conditionNumber)
            await ensureImmersiveSpaceIsOpen()
        }
        .onChange(of: panelModel.panels) { _ in
            experimentManager.syncVisibleTasks(panelModel: panelModel)
        }
        .onChange(of: experimentManager.conditionNumber) { newCondition in
            panelModel.applyCondition(newCondition)
        }
        .onChange(of: experimentManager.shouldTriggerCSVExport) { newValue in
            if newValue, let summaryFile = experimentManager.exportedSummaryFile {
                exportDocument = ExportedCSVDocument(sourceURL: summaryFile.url)
                isExportingFile = true
                experimentManager.shouldTriggerCSVExport = false
            }
        }
        .fileExporter(
            isPresented: $isExportingFile,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportDocument.suggestedFilename
        ) { result in
            if case .failure(let error) = result {
                experimentManager.errorMessage = "Failed to export CSV: \(error.localizedDescription)"
            }
        }
    }

    private var immersiveControls: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Immersive")
                .font(.headline)

            Button("Open HUD Panels") {
                Task { await showHUDPanels() }
            }

            if isImmersiveSpaceActive {
                Button("Hide HUD Panels") {
                    panelModel.hudPanelsAreShown = false
                }

                Button("Close Immersive Space") {
                    Task {
                        await dismissImmersiveSpace()
                        isImmersiveSpaceActive = false
                        panelModel.hudPanelsAreShown = false
                    }
                }
            }
        }
    }

    private var experimentControls: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Experiment Control")
                .font(.headline)

            HStack(spacing: 20) {
                StepperCard(
                    title: "Participant ID",
                    valueText: experimentManager.participantIDText,
                    onDecrement: experimentManager.decrementParticipant,
                    onIncrement: experimentManager.incrementParticipant
                )

                StepperCard(
                    title: "Condition ID",
                    valueText: experimentManager.conditionIDText,
                    subtitleText: experimentManager.conditionName,
                    onDecrement: experimentManager.decrementCondition,
                    onIncrement: experimentManager.incrementCondition
                )
            }

            LOSCard(panelModel: panelModel)

            HStack(spacing: 12) {
                Button("Start Task") {
                    experimentManager.startTask(panelModel: panelModel)
                }
                .disabled(!experimentManager.canStart)

                Button("End Task") {
                    experimentManager.endTask(panelModel: panelModel)
                }
                .disabled(!experimentManager.canEnd)

                Button("Reset Collision") {
                    Task {
                        // 1. Close HUD / Immersive Space のクローズ処理
                        await dismissImmersiveSpace()
                        isImmersiveSpaceActive = false
                        panelModel.hudPanelsAreShown = false
                        
                        // 2. 当たり判定モデルのキャッシュ破棄トリガーを引く
                        panelModel.resetCollisionRequestCount += 1
                        
                        // 3. Open HUD / Immersive Space の再オープン
                        await showHUDPanels()
                    }
                }
                .buttonStyle(.bordered)
            }

            HStack(spacing: 18) {
                Text("Status: \(experimentManager.statusText)")
                Text("Elapsed: \(experimentManager.elapsedTime, format: .number.precision(.fractionLength(1))) s")
                Text("Score: \(experimentManager.arcadeScore)")
                Text("Combo: \(experimentManager.comboCount)")
            }
            .font(.subheadline)

            Text("Only tasks with visible (ON) panels will be started and recorded.")
                .font(.footnote)
                .foregroundStyle(.secondary)

            if let errorMessage = experimentManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.footnote)
            }

            if let summaryFile = experimentManager.exportedSummaryFile {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Export Summary File")
                        .font(.subheadline.bold())

                    Button {
                        exportDocument = ExportedCSVDocument(sourceURL: summaryFile.url)
                        isExportingFile = true
                    } label: {
                        Label(summaryFile.title, systemImage: "chart.bar.doc.horizontal")
                    }

                    Text(summaryFile.url.path)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private var taskConfigControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Task Settings")
                .font(.headline)

            // 1枚目のゲーム用パラメータ
            VStack(alignment: .leading) {
                Text(String(format: "Game: Spawn Interval %.1f s", experimentManager.selectiveConfig.spawnInterval))
                Slider(value: $experimentManager.selectiveConfig.spawnInterval, in: 0.3...2.0, step: 0.1)
                    .onChange(of: experimentManager.selectiveConfig.spawnInterval) { _ in
                        experimentManager.refreshConfigurations()
                    }
            }

            VStack(alignment: .leading) {
                Text(String(format: "Game: Display Duration %.1f s", experimentManager.selectiveConfig.displayDuration))
                Slider(value: $experimentManager.selectiveConfig.displayDuration, in: 0.6...2.0, step: 0.1)
                    .onChange(of: experimentManager.selectiveConfig.displayDuration) { _ in
                        experimentManager.refreshConfigurations()
                    }
            }

            VStack(alignment: .leading) {
                Text("Game: Simultaneous Targets \(experimentManager.selectiveConfig.simultaneousTargetCount)")
                Slider(
                    value: Binding(
                        get: { Double(experimentManager.selectiveConfig.simultaneousTargetCount) },
                        set: {
                            experimentManager.selectiveConfig.simultaneousTargetCount = Int($0.rounded())
                            experimentManager.refreshConfigurations()
                        }
                    ),
                    in: 1...2,
                    step: 1
                )
            }

            VStack(alignment: .leading) {
                Text(String(format: "Game: Correct Target Ratio %.2f", experimentManager.selectiveConfig.correctTargetRatio))
                Slider(value: $experimentManager.selectiveConfig.correctTargetRatio, in: 0.2...0.7, step: 0.05)
                    .onChange(of: experimentManager.selectiveConfig.correctTargetRatio) { _ in
                        experimentManager.refreshConfigurations()
                    }
            }

            Divider().padding(.vertical, 4)

            // 2枚目の計算パネル用パラメータ
            VStack(alignment: .leading) {
                Text(String(format: "Calc: Display Duration %.1f s", experimentManager.arithmeticConfig.displayDuration))
                Slider(value: $experimentManager.arithmeticConfig.displayDuration, in: 1.0...6.0, step: 0.1)
                    .onChange(of: experimentManager.arithmeticConfig.displayDuration) { _ in
                        experimentManager.refreshConfigurations()
                    }
            }

            VStack(alignment: .leading) {
                Text(String(format: "Calc: Inter-question Interval %.1f s", experimentManager.arithmeticConfig.interQuestionInterval))
                Slider(value: $experimentManager.arithmeticConfig.interQuestionInterval, in: 0.4...2.0, step: 0.1)
                    .onChange(of: experimentManager.arithmeticConfig.interQuestionInterval) { _ in
                        experimentManager.refreshConfigurations()
                    }
            }

            Divider().padding(.vertical, 4)

            VStack(alignment: .leading) {
                Text(String(format: "Text Entry: Time Limit %.1f s", experimentManager.textEntryConfig.displayDuration))
                Slider(value: $experimentManager.textEntryConfig.displayDuration, in: 6.0...20.0, step: 1.0)
                    .onChange(of: experimentManager.textEntryConfig.displayDuration) { _ in
                        experimentManager.refreshConfigurations()
                    }
            }

            VStack(alignment: .leading) {
                Text("n-back: n = \(experimentManager.nBackConfig.nValue)")
                Slider(
                    value: Binding(
                        get: { Double(experimentManager.nBackConfig.nValue) },
                        set: {
                            experimentManager.nBackConfig.nValue = Int($0.rounded())
                            experimentManager.refreshConfigurations()
                        }
                    ),
                    in: 1...3,
                    step: 1
                )
            }

            VStack(alignment: .leading) {
                Text(String(format: "N-Back: Stimulus Duration %.1f s", experimentManager.nBackConfig.stimulusDuration))
                Slider(value: $experimentManager.nBackConfig.stimulusDuration, in: 1.0...3.0, step: 0.1)
                    .onChange(of: experimentManager.nBackConfig.stimulusDuration) { _ in
                        experimentManager.refreshConfigurations()
                    }
            }
        }
    }

    private var panelControls: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("HUD Panel Settings")
                    .font(.headline)
                Spacer()
                Button(action: {
                    panelModel.resetPanelsToDefault()
                }) {
                    Label("Reset to Default", systemImage: "arrow.uturn.backward")
                        .font(.subheadline)
                }
                .buttonStyle(.bordered)
            }
            
            HStack(spacing: 8) {
                Text("Save/Load Preset:")
                    .font(.subheadline)
                ForEach(["A", "B", "C"], id: \.self) { presetName in
                    HStack(spacing: 4) {
                        Button(action: {
                            panelModel.loadPreset(name: presetName)
                        }) {
                            Text(presetName)
                        }
                        .buttonStyle(.bordered)
                        .disabled(panelModel.presets[presetName] == nil)
                        
                        Button(action: {
                            panelModel.savePreset(name: presetName)
                        }) {
                            Image(systemName: "square.and.arrow.down")
                        }
                        .buttonStyle(.borderless)
                        .foregroundColor(.blue)
                    }
                }
            }
            .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Follow Mode (Tracking Mode)")
                    .font(.subheadline.bold())
                Picker("Follow Mode", selection: $panelModel.trackingMode) {
                    ForEach(PanelModel.HUDTrackingMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.menu)
                
                if panelModel.trackingMode == .snapFollow {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(String(format: "Snap Threshold: %.1f°", panelModel.snapThresholdDegrees))
                            .font(.footnote)
                        Slider(value: $panelModel.snapThresholdDegrees, in: 10.0...90.0, step: 1.0)
                    }
                    .padding(.top, 4)
                }
            }
            .padding(.bottom, 8)

            ForEach($panelModel.panels) { $panel in
                DisclosureGroup {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle("Visible", isOn: $panel.isVisible)
                        ColorPicker("Background Color", selection: $panel.color)
                        ColorPicker("Text Color", selection: $panel.textColor)
                        
                        HStack(spacing: 8) {
                            Text("Color Theme:")
                                .font(.footnote)
                            
                            Button("Dark") {
                                panel.color = .black
                                panel.textColor = .white
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Light") {
                                panel.color = .white
                                panel.textColor = .black
                            }
                            .buttonStyle(.bordered)
                            
                            Button("Contrast") {
                                panel.color = .yellow
                                panel.textColor = .black
                            }
                            .buttonStyle(.bordered)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Opacity")
                                .font(.subheadline)
                            Slider(value: Binding(
                                get: { Float(panel.opacity) },
                                set: { panel.opacity = Double($0) }
                            ), in: 0.0...1.0)
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(String(format: "Yaw (L/R): %.1f°", panel.angleX))
                            Slider(value: $panel.angleX, in: -90...90, step: 1.0)

                            Text(String(format: "Pitch (U/D): %.1f°", panel.angleY))
                            Slider(value: $panel.angleY, in: -90...90, step: 1.0)

                            Text(String(format: "Distance (Z): %.2fm", panel.distanceZ))
                            Slider(value: $panel.distanceZ, in: 0.5...10.0, step: 0.1)

                            HStack {
                                Text(String(format: "Aspect Ratio (W/H): %.2f", panel.aspectRatio))
                                Spacer()
                                Button(action: {
                                    panel.aspectRatio = 1.0 / panel.aspectRatio
                                }) {
                                    Image(systemName: "arrow.triangle.2.circlepath")
                                        .foregroundColor(.blue)
                                }
                                .buttonStyle(.borderless)
                            }
                            Slider(value: $panel.aspectRatio, in: 0.25...4.0, step: 0.05)
                                .padding(.bottom, 4)

                            Text(String(format: "Field of View (Size): %.1f°", panel.vofDegrees))
                            Slider(value: $panel.vofDegrees, in: 10.0...120.0, step: 1.0)

                            let renderSize = panel.renderSize
                            Text(String(format: "Actual Size %.2f x %.2f m", renderSize.x, renderSize.y))
                                
                        }
                    }
                    .padding(.vertical, 4)
                } label: {
                    HStack {
                        Text(panel.id).font(.subheadline).bold()
                        Spacer()
                        if panel.isVisible {
                            Image(systemName: "eye.fill").foregroundColor(.blue)
                        } else {
                            Image(systemName: "eye.slash").foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Color.secondary.opacity(0.3))
                )
            }
        }
    }
    
    private var optimalZoneControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Optimal FoV Guide Settings")
                .font(.headline)
            
            Toggle("Show Guide", isOn: $panelModel.optimalZone.isGuideVisible)
                .padding(.bottom, 8)
            
            if panelModel.optimalZone.isGuideVisible {
                DisclosureGroup("Z Coordinate (Distance: m)") {
                    VStack {
                        HStack { Text("Min"); Slider(value: $panelModel.optimalZone.minZ, in: 0.5...10.0, step: 0.1); Text(String(format: "%.2f", panelModel.optimalZone.minZ)) }
                        HStack { Text("Max"); Slider(value: $panelModel.optimalZone.maxZ, in: 0.5...10.0, step: 0.1); Text(String(format: "%.2f", panelModel.optimalZone.maxZ)) }
                        HStack { Text("Base"); Slider(value: $panelModel.optimalZone.baseZ, in: 0.5...10.0, step: 0.1); Text(String(format: "%.2f", panelModel.optimalZone.baseZ)) }
                    }
                }
                
                DisclosureGroup("Y Coordinate (Pitch: deg)") {
                    VStack {
                        HStack { Text("Min"); Slider(value: $panelModel.optimalZone.minPitch, in: -90...90, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.minPitch)) }
                        HStack { Text("Max"); Slider(value: $panelModel.optimalZone.maxPitch, in: -90...90, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.maxPitch)) }
                        HStack { Text("Base"); Slider(value: $panelModel.optimalZone.basePitch, in: -90...90, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.basePitch)) }
                    }
                }
                
                DisclosureGroup("X Coordinate (Yaw: deg)") {
                    VStack {
                        HStack { Text("Min"); Slider(value: $panelModel.optimalZone.minYaw, in: -90...90, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.minYaw)) }
                        HStack { Text("Max"); Slider(value: $panelModel.optimalZone.maxYaw, in: -90...90, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.maxYaw)) }
                        HStack { Text("Base"); Slider(value: $panelModel.optimalZone.baseYaw, in: -90...90, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.baseYaw)) }
                    }
                }
                
                DisclosureGroup("Size / FoV (deg)") {
                    VStack {
                        HStack { Text("Min"); Slider(value: $panelModel.optimalZone.minVoF, in: 10...120, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.minVoF)) }
                        HStack { Text("Max"); Slider(value: $panelModel.optimalZone.maxVoF, in: 10...120, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.maxVoF)) }
                        HStack { Text("Base"); Slider(value: $panelModel.optimalZone.baseVoF, in: 10...120, step: 1.0); Text(String(format: "%.1f", panelModel.optimalZone.baseVoF)) }
                    }
                }
            }
        }
        .padding(.vertical, 8)
    }

    private var peopleControls: some View {
        let width = Double(panelModel.peopleHorizontalRange) * 2.0
        let avgVelocity = 0.88 * Double(panelModel.peopleSpeedMultiplier)
        
        return VStack(alignment: .leading, spacing: 12) {
            Text("Pedestrian Settings")
                .font(.headline)

            HStack(spacing: 12) {
                Button {
                    panelModel.peopleIsPlaying.toggle()
                } label: {
                    Label(
                        panelModel.peopleIsPlaying ? "Pause" : "Play",
                        systemImage: panelModel.peopleIsPlaying ? "pause.fill" : "play.fill"
                    )
                }

                Button {
                    panelModel.resetCount += 1
                    experimentManager.collisionCount = 0
                } label: {
                    Label("Reset", systemImage: "arrow.clockwise")
                }

                Button("1x Speed") {
                    panelModel.peopleSpeedMultiplier = 1.0
                }
                
                Spacer()
                
                Toggle(isOn: $panelModel.showCollisionVisuals) {
                    Label("Show Collision", systemImage: panelModel.showCollisionVisuals ? "eye.fill" : "eye.slash.fill")
                }
                .toggleStyle(.button)
                

            }

            VStack(alignment: .leading, spacing: 8) {
                Text("Pedestrian Direction")
                    .font(.subheadline.bold())
                Picker("Direction", selection: $panelModel.pedestrianDirectionMode) {
                    ForEach(PanelModel.PedestrianDirectionMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading, spacing: 8) {
                Text("Walking Algorithm")
                    .font(.subheadline.bold())
                Picker("Algorithm", selection: $panelModel.pedestrianAlgorithm) {
                    ForEach(PanelModel.PedestrianAlgorithm.allCases) { algo in
                        Text(algo.rawValue).tag(algo)
                    }
                }
                .pickerStyle(.menu)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading) {
                Text(String(format: "Speed Multiplier: x%.1f", panelModel.peopleSpeedMultiplier))
                Slider(value: $panelModel.peopleSpeedMultiplier, in: 0.2...3.0)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Pedestrian Density Preset (Fruin's LOS)")
                    .font(.subheadline.bold())
                Picker("Density", selection: Binding(
                    get: {
                        if abs(panelModel.peopleSpawnInterval - panelModel.tA) < 0.1 { return 0 }
                        else if abs(panelModel.peopleSpawnInterval - panelModel.tB) < 0.1 { return 1 }
                        else if abs(panelModel.peopleSpawnInterval - panelModel.tC) < 0.1 { return 2 }
                        else if abs(panelModel.peopleSpawnInterval - panelModel.tD) < 0.1 { return 3 }
                        else if abs(panelModel.peopleSpawnInterval - panelModel.tE) < 0.1 { return 4 }
                        else if abs(panelModel.peopleSpawnInterval - panelModel.tF) < 0.1 { return 5 }
                        else { return 6 }
                    },
                    set: { val in
                        switch val {
                        case 0: panelModel.peopleSpawnInterval = panelModel.tA
                        case 1: panelModel.peopleSpawnInterval = panelModel.tB
                        case 2: panelModel.peopleSpawnInterval = panelModel.tC
                        case 3: panelModel.peopleSpawnInterval = panelModel.tD
                        case 4: panelModel.peopleSpawnInterval = panelModel.tE
                        case 5: panelModel.peopleSpawnInterval = panelModel.tF
                        default: break
                        }
                    }
                )) {
                    Text("LOS A").tag(0)
                    Text("LOS B").tag(1)
                    Text("LOS C").tag(2)
                    Text("LOS D").tag(3)
                    Text("LOS E").tag(4)
                    Text("LOS F").tag(5)
                }
                .pickerStyle(.segmented)
                
                Text(String(format: "* Target (Width %.1fm, Speed %.2fm/s):", width, avgVelocity))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                Text(String(format: "A: %.1fs | B: %.1fs | C: %.1fs | D: %.1fs | E: %.1fs | F: %.1fs", panelModel.tA, panelModel.tB, panelModel.tC, panelModel.tD, panelModel.tE, panelModel.tF))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)

            VStack(alignment: .leading) {
                Text(String(format: "Spawn Interval (avg): %.1f s", panelModel.peopleSpawnInterval))
                Slider(value: $panelModel.peopleSpawnInterval, in: 0.3...10.0)
            }

            VStack(alignment: .leading) {
                Text(String(format: "Horizontal Range (lane spread): %.1f m", panelModel.peopleHorizontalRange))
                Slider(value: $panelModel.peopleHorizontalRange, in: 0.5...6.0)
            }

            VStack(alignment: .leading) {
                Text(String(format: "Height Offset: %.2f m", panelModel.peopleHeightOffset))
                Slider(value: $panelModel.peopleHeightOffset, in: -1.0...0.0)
            }

            Divider().padding(.vertical, 6)

            VStack(alignment: .leading, spacing: 12) {
                Text("Spawn Line (Length / Angle / Position)")
                    .font(.subheadline.bold())

                GroupBox("Length & Angle Fine-Tuning") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Length Row
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "Length (L): %.2f m", panelModel.spawnLineLength))
                                    .font(.subheadline.bold())
                                Spacer()
                                TextField("", value: $panelModel.spawnLineLength, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            Slider(value: $panelModel.spawnLineLength, in: 0.2...80.0, step: 0.05)
                            HStack(spacing: 6) {
                                Button("-5.0m") { panelModel.spawnLineLength = max(0.2, panelModel.spawnLineLength - 5.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-1.0m") { panelModel.spawnLineLength = max(0.2, panelModel.spawnLineLength - 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-0.1m") { panelModel.spawnLineLength = max(0.2, panelModel.spawnLineLength - 0.1) }.buttonStyle(.bordered).controlSize(.small)
                                Spacer()
                                Button("+0.1m") { panelModel.spawnLineLength = min(80.0, panelModel.spawnLineLength + 0.1) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+1.0m") { panelModel.spawnLineLength = min(80.0, panelModel.spawnLineLength + 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+5.0m") { panelModel.spawnLineLength = min(80.0, panelModel.spawnLineLength + 5.0) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        // Angle Row
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "Angle (A): %.1f °", panelModel.spawnLineAngleDegrees))
                                    .font(.subheadline.bold())
                                Spacer()
                                TextField("", value: $panelModel.spawnLineAngleDegrees, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            Slider(value: $panelModel.spawnLineAngleDegrees, in: -180...180, step: 0.5)
                            HStack(spacing: 6) {
                                Button("-5°") { panelModel.spawnLineAngleDegrees = max(-180, panelModel.spawnLineAngleDegrees - 5.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-1°") { panelModel.spawnLineAngleDegrees = max(-180, panelModel.spawnLineAngleDegrees - 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-0.5°") { panelModel.spawnLineAngleDegrees = max(-180, panelModel.spawnLineAngleDegrees - 0.5) }.buttonStyle(.bordered).controlSize(.small)
                                Spacer()
                                Button("+0.5°") { panelModel.spawnLineAngleDegrees = min(180, panelModel.spawnLineAngleDegrees + 0.5) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+1°") { panelModel.spawnLineAngleDegrees = min(180, panelModel.spawnLineAngleDegrees + 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+5°") { panelModel.spawnLineAngleDegrees = min(180, panelModel.spawnLineAngleDegrees + 5.0) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }

                GroupBox("Position (World Coordinates) Fine-Tuning") {
                    VStack(alignment: .leading, spacing: 12) {
                        // Translation X Row
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "Translate X: %.2f m", panelModel.spawnLineCenterX))
                                    .font(.subheadline.bold())
                                Spacer()
                                TextField("", value: $panelModel.spawnLineCenterX, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            Slider(value: $panelModel.spawnLineCenterX, in: -50...50, step: 0.05)
                            HStack(spacing: 6) {
                                Button("-5.0m") { panelModel.spawnLineCenterX = max(-50.0, panelModel.spawnLineCenterX - 5.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-1.0m") { panelModel.spawnLineCenterX = max(-50.0, panelModel.spawnLineCenterX - 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-0.1m") { panelModel.spawnLineCenterX = max(-50.0, panelModel.spawnLineCenterX - 0.1) }.buttonStyle(.bordered).controlSize(.small)
                                Spacer()
                                Button("+0.1m") { panelModel.spawnLineCenterX = min(50.0, panelModel.spawnLineCenterX + 0.1) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+1.0m") { panelModel.spawnLineCenterX = min(50.0, panelModel.spawnLineCenterX + 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+5.0m") { panelModel.spawnLineCenterX = min(50.0, panelModel.spawnLineCenterX + 5.0) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                        
                        Divider().padding(.vertical, 4)
                        
                        // Translation Z Row
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text(String(format: "Translate Z: %.2f m", panelModel.spawnLineCenterZ))
                                    .font(.subheadline.bold())
                                Spacer()
                                TextField("", value: $panelModel.spawnLineCenterZ, format: .number)
                                    .frame(width: 80)
                                    .textFieldStyle(.roundedBorder)
                                    .multilineTextAlignment(.trailing)
                            }
                            Slider(value: $panelModel.spawnLineCenterZ, in: -30...30, step: 0.05)
                            HStack(spacing: 6) {
                                Button("-5.0m") { panelModel.spawnLineCenterZ = max(-30.0, panelModel.spawnLineCenterZ - 5.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-1.0m") { panelModel.spawnLineCenterZ = max(-30.0, panelModel.spawnLineCenterZ - 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("-0.1m") { panelModel.spawnLineCenterZ = max(-30.0, panelModel.spawnLineCenterZ - 0.1) }.buttonStyle(.bordered).controlSize(.small)
                                Spacer()
                                Button("+0.1m") { panelModel.spawnLineCenterZ = min(30.0, panelModel.spawnLineCenterZ + 0.1) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+1.0m") { panelModel.spawnLineCenterZ = min(30.0, panelModel.spawnLineCenterZ + 1.0) }.buttonStyle(.bordered).controlSize(.small)
                                Button("+5.0m") { panelModel.spawnLineCenterZ = min(30.0, panelModel.spawnLineCenterZ + 5.0) }.buttonStyle(.bordered).controlSize(.small)
                            }
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func ensureImmersiveSpaceIsOpen() async {
        guard !isImmersiveSpaceActive else { return }

        let status = await openImmersiveSpace(id: "ImmersiveHUD")
        if status == .opened {
            isImmersiveSpaceActive = true
        }
    }

    @MainActor
    private func showHUDPanels() async {
        await ensureImmersiveSpaceIsOpen()
        panelModel.hudPanelsAreShown = true
    }
}

private struct StepperCard: View {
    let title: String
    let valueText: String
    var subtitleText: String? = nil
    let onDecrement: () -> Void
    let onIncrement: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Button(action: onDecrement) {
                    Image(systemName: "minus.circle.fill")
                        .font(.title2)
                }

                VStack(spacing: 2) {
                    Text(valueText)
                        .font(.title3.bold())
                    if let subtitle = subtitleText {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(minWidth: 100)

                Button(action: onIncrement) {
                    Image(systemName: "plus.circle.fill")
                        .font(.title2)
                }
            }
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

private struct LOSCard: View {
    @ObservedObject var panelModel: PanelModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Density (LOS)")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Picker("Density", selection: Binding(
                get: {
                    if abs(panelModel.peopleSpawnInterval - panelModel.tA) < 0.1 { return 0 }
                    else if abs(panelModel.peopleSpawnInterval - panelModel.tB) < 0.1 { return 1 }
                    else if abs(panelModel.peopleSpawnInterval - panelModel.tC) < 0.1 { return 2 }
                    else if abs(panelModel.peopleSpawnInterval - panelModel.tD) < 0.1 { return 3 }
                    else if abs(panelModel.peopleSpawnInterval - panelModel.tE) < 0.1 { return 4 }
                    else if abs(panelModel.peopleSpawnInterval - panelModel.tF) < 0.1 { return 5 }
                    else { return 6 }
                },
                set: { val in
                    switch val {
                    case 0: panelModel.peopleSpawnInterval = panelModel.tA
                    case 1: panelModel.peopleSpawnInterval = panelModel.tB
                    case 2: panelModel.peopleSpawnInterval = panelModel.tC
                    case 3: panelModel.peopleSpawnInterval = panelModel.tD
                    case 4: panelModel.peopleSpawnInterval = panelModel.tE
                    case 5: panelModel.peopleSpawnInterval = panelModel.tF
                    default: break
                    }
                }
            )) {
                Text("LOS A").tag(0)
                Text("LOS B").tag(1)
                Text("LOS C").tag(2)
                Text("LOS D").tag(3)
                Text("LOS E").tag(4)
                Text("LOS F").tag(5)
            }
            .pickerStyle(.segmented)
            .frame(minWidth: 260)
        }
        .padding(12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(Color.secondary.opacity(0.08))
        )
    }
}

struct SliderWithLabel: View {
    var label: String
    @Binding var value: Float
    var range: ClosedRange<Float>

    var body: some View {
        HStack {
            Text(label)
                .frame(width: 20, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: "%.2f", value))
                .frame(width: 50, alignment: .trailing)
        }
    }
}

private struct ExportedCSVDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }

    let data: Data
    let suggestedFilename: String

    init(data: Data, suggestedFilename: String) {
        self.data = data
        self.suggestedFilename = suggestedFilename
    }

    init(sourceURL: URL) {
        self.data = (try? Data(contentsOf: sourceURL)) ?? Data()
        self.suggestedFilename = sourceURL.deletingPathExtension().lastPathComponent
    }

    init(configuration: ReadConfiguration) throws {
        self.data = configuration.file.regularFileContents ?? Data()
        self.suggestedFilename = "session"
    }

    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper {
        FileWrapper(regularFileWithContents: data)
    }
}
