import CoreMotion
import Foundation

private let sharedISOFormatter = ISO8601DateFormatter()

/// CoreMotion から IMU を取得して統合 CSV へ保存する
final class MotionRecorder {
    private let motionManager = CMMotionManager()
    private let queue: OperationQueue = {
        let queue = OperationQueue()
        queue.name = "MotionRecorder.queue"
        return queue
    }()

    private var sessionLogger: UnifiedSessionLogger?
    private var metadata: ExperimentMetadata?
    private var startDate: Date?
    private var sampleCount = 0
    private var accelSum: Double = 0
    private var accelSumSq: Double = 0
    private var accelCount: Int = 0

    func startRecording(metadata: ExperimentMetadata, startDate: Date, sessionLogger: UnifiedSessionLogger) throws {
        stopRecording()

        self.metadata = metadata
        self.startDate = startDate
        self.sessionLogger = sessionLogger
        sampleCount = 0
        accelSum = 0
        accelSumSq = 0
        accelCount = 0

        motionManager.deviceMotionUpdateInterval = 1.0 / 50.0

        guard motionManager.isDeviceMotionAvailable else {
            try appendFallbackRow(reasonDate: startDate)
            return
        }

        motionManager.startDeviceMotionUpdates(to: queue) { [weak self] motion, _ in
            self?.appendMotionRow(motion)
        }
    }

    func stopRecording() {
        motionManager.stopDeviceMotionUpdates()
        sessionLogger = nil
        metadata = nil
        startDate = nil
    }

    func getStats() -> (count: Int, sum: Double, sumSq: Double) {
        return (accelCount, accelSum, accelSumSq)
    }

    private func appendFallbackRow(reasonDate: Date) throws {
        guard let sessionLogger, let metadata else { return }

        try sessionLogger.appendIMURaw(
            timestamp: iso8601(reasonDate),
            elapsedTime: "0",
            accelerationX: "0",
            accelerationY: "0",
            accelerationZ: "0",
            userAccelerationX: "0",
            userAccelerationY: "0",
            userAccelerationZ: "0",
            gyroX: "0",
            gyroY: "0",
            gyroZ: "0",
            attitudeRoll: "0",
            attitudePitch: "0",
            attitudeYaw: "0",
            rotationRateX: "0",
            rotationRateY: "0",
            rotationRateZ: "0",
            gravityX: "0",
            gravityY: "0",
            gravityZ: "0",
            participantID: metadata.participantID,
            conditionID: metadata.conditionID,
            los: metadata.los
        )
        try sessionLogger.flush()
    }

    private func appendMotionRow(_ motion: CMDeviceMotion?) {
        guard let sessionLogger, let metadata, let startDate else { return }

        let now = Date()
        let elapsed = now.timeIntervalSince(startDate)

        do {
            if let motion {
                try sessionLogger.appendIMURaw(
                    timestamp: iso8601(now),
                    elapsedTime: csv(elapsed),
                    accelerationX: csv(motion.userAcceleration.x),
                    accelerationY: csv(motion.userAcceleration.y),
                    accelerationZ: csv(motion.userAcceleration.z),
                    userAccelerationX: csv(motion.userAcceleration.x),
                    userAccelerationY: csv(motion.userAcceleration.y),
                    userAccelerationZ: csv(motion.userAcceleration.z),
                    gyroX: csv(motion.rotationRate.x),
                    gyroY: csv(motion.rotationRate.y),
                    gyroZ: csv(motion.rotationRate.z),
                    attitudeRoll: csv(motion.attitude.roll),
                    attitudePitch: csv(motion.attitude.pitch),
                    attitudeYaw: csv(motion.attitude.yaw),
                    rotationRateX: csv(motion.rotationRate.x),
                    rotationRateY: csv(motion.rotationRate.y),
                    rotationRateZ: csv(motion.rotationRate.z),
                    gravityX: csv(motion.gravity.x),
                    gravityY: csv(motion.gravity.y),
                    gravityZ: csv(motion.gravity.z),
                    participantID: metadata.participantID,
                    conditionID: metadata.conditionID,
                    los: metadata.los
                )
                
                let mag = sqrt(motion.userAcceleration.x * motion.userAcceleration.x + motion.userAcceleration.y * motion.userAcceleration.y + motion.userAcceleration.z * motion.userAcceleration.z)
                accelCount += 1
                accelSum += mag
                accelSumSq += (mag * mag)
            } else {
                try sessionLogger.appendIMURaw(
                    timestamp: iso8601(now),
                    elapsedTime: csv(elapsed),
                    accelerationX: "0",
                    accelerationY: "0",
                    accelerationZ: "0",
                    userAccelerationX: "0",
                    userAccelerationY: "0",
                    userAccelerationZ: "0",
                    gyroX: "0",
                    gyroY: "0",
                    gyroZ: "0",
                    attitudeRoll: "0",
                    attitudePitch: "0",
                    attitudeYaw: "0",
                    rotationRateX: "0",
                    rotationRateY: "0",
                    rotationRateZ: "0",
                    gravityX: "0",
                    gravityY: "0",
                    gravityZ: "0",
                    participantID: metadata.participantID,
                    conditionID: metadata.conditionID,
                    los: metadata.los
                )
            }

            sampleCount += 1
            if sampleCount.isMultiple(of: 25) {
                try sessionLogger.flush()
            }
        } catch {
            // 収録中のクラッシュ回避を優先して握りつぶす
        }
    }

    private func iso8601(_ date: Date) -> String {
        sharedISOFormatter.string(from: date)
    }

    private func csv(_ value: Double) -> String {
        String(format: "%.6f", value)
    }
}
