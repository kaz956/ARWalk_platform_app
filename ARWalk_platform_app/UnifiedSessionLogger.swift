import Foundation

/// 実験中の IMU / タスクイベント / 条件サマリを 1 本の CSV にまとめる
final class UnifiedSessionLogger {
    private let logger: CSVLogger
    let fileURL: URL

    init(fileURL: URL) throws {
        self.fileURL = fileURL
        self.logger = try CSVLogger(
            fileURL: fileURL,
            headers: [
                "record_type",
                "timestamp",
                "elapsed_time",
                "event_type",
                "task_type",
                "target_id",
                "target_color",
                "target_shape",
                "target_symbol",
                "target_number",
                "rule",
                "is_correct",
                "reaction_time",
                "target_x",
                "target_y",
                "arithmetic_question",
                "arithmetic_correct_answer",
                "arithmetic_selected_answer",
                "arithmetic_options",
                "arithmetic_operator",
                "arithmetic_difficulty",
                "detail_1",
                "detail_2",
                "detail_3",
                "detail_4",
                "acceleration_x",
                "acceleration_y",
                "acceleration_z",
                "user_acceleration_x",
                "user_acceleration_y",
                "user_acceleration_z",
                "gyro_x",
                "gyro_y",
                "gyro_z",
                "attitude_roll",
                "attitude_pitch",
                "attitude_yaw",
                "rotation_rate_x",
                "rotation_rate_y",
                "rotation_rate_z",
                "gravity_x",
                "gravity_y",
                "gravity_z",
                "participant_id",
                "condition_id",
                "los"
            ]
        )
    }

    func appendTaskEvent(_ row: [String: String]) throws {
        var merged = emptyRow(recordType: "task")
        for (key, value) in row {
            merged[key] = value
        }
        try logger.appendRow(merged)
    }

    func appendIMUEvent(_ row: [String: String]) throws {
        var merged = emptyRow(recordType: "imu")
        for (key, value) in row {
            merged[key] = value
        }
        try logger.appendRow(merged)
    }

    func appendIMURaw(
        timestamp: String,
        elapsedTime: String,
        accelerationX: String,
        accelerationY: String,
        accelerationZ: String,
        userAccelerationX: String,
        userAccelerationY: String,
        userAccelerationZ: String,
        gyroX: String,
        gyroY: String,
        gyroZ: String,
        attitudeRoll: String,
        attitudePitch: String,
        attitudeYaw: String,
        rotationRateX: String,
        rotationRateY: String,
        rotationRateZ: String,
        gravityX: String,
        gravityY: String,
        gravityZ: String,
        participantID: String,
        conditionID: String,
        los: String
    ) throws {
        let values: [String] = [
            "imu",
            timestamp,
            elapsedTime,
            "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "", "",
            accelerationX,
            accelerationY,
            accelerationZ,
            userAccelerationX,
            userAccelerationY,
            userAccelerationZ,
            gyroX,
            gyroY,
            gyroZ,
            attitudeRoll,
            attitudePitch,
            attitudeYaw,
            rotationRateX,
            rotationRateY,
            rotationRateZ,
            gravityX,
            gravityY,
            gravityZ,
            participantID,
            conditionID,
            los
        ]
        try logger.appendRawLine(values)
    }


    func appendSummaryEvent(_ row: [String: String]) throws {
        var merged = emptyRow(recordType: "summary")
        for (key, value) in row {
            merged[key] = value
        }
        try logger.appendRow(merged)
    }

    func flush() throws {
        try logger.flush()
    }

    func close() throws {
        try logger.close()
    }

    private func emptyRow(recordType: String) -> [String: String] {
        [
            "record_type": recordType,
            "timestamp": "",
            "elapsed_time": "",
            "event_type": "",
            "task_type": "",
            "target_id": "",
            "target_color": "",
            "target_shape": "",
            "target_symbol": "",
            "target_number": "",
            "rule": "",
            "is_correct": "",
            "reaction_time": "",
            "target_x": "",
            "target_y": "",
            "arithmetic_question": "",
            "arithmetic_correct_answer": "",
            "arithmetic_selected_answer": "",
            "arithmetic_options": "",
            "arithmetic_operator": "",
            "arithmetic_difficulty": "",
            "detail_1": "",
            "detail_2": "",
            "detail_3": "",
            "detail_4": "",
            "acceleration_x": "",
            "acceleration_y": "",
            "acceleration_z": "",
            "user_acceleration_x": "",
            "user_acceleration_y": "",
            "user_acceleration_z": "",
            "gyro_x": "",
            "gyro_y": "",
            "gyro_z": "",
            "attitude_roll": "",
            "attitude_pitch": "",
            "attitude_yaw": "",
            "rotation_rate_x": "",
            "rotation_rate_y": "",
            "rotation_rate_z": "",
            "gravity_x": "",
            "gravity_y": "",
            "gravity_z": "",
            "participant_id": "",
            "condition_id": "",
            "los": ""
        ]
    }
}
