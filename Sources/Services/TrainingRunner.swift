import Foundation

/// Manages automated model training by running Python as a subprocess.
/// Stateless enum (matching DatasetGenerator pattern).
enum TrainingRunner {

    /// Holds a reference to the running process for cancellation.
    nonisolated(unsafe) private static var currentProcess: Process?

    // MARK: - Python Discovery

    /// Search common paths for python3, returns the first found.
    static func findPython() -> String? {
        let candidates = [
            "/opt/homebrew/bin/python3",
            "/usr/local/bin/python3",
            "/usr/bin/python3",
        ]
        let fm = FileManager.default
        for path in candidates {
            if fm.fileExists(atPath: path) {
                return path
            }
        }
        // Fall back to which
        let pipe = Pipe()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/which")
        process.arguments = ["python3"]
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let result = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
            if let result, !result.isEmpty, fm.fileExists(atPath: result) {
                return result
            }
        } catch {}
        return nil
    }

    /// Check if python3 is available.
    static func isPythonAvailable() async -> Bool {
        findPython() != nil
    }

    // MARK: - Training

    /// Main entry point - orchestrates the full training pipeline.
    @MainActor
    static func train(model: SiameseModel, dataset: PuzzleDataset, state: ModelState) async {
        // Validate python
        guard let pythonPath = findPython() else {
            state.trainingStatus = .failed(reason: "python3 not found")
            return
        }

        // Validate dataset directory exists
        let datasetDir = DatasetStore.datasetDirectory(for: dataset.id)
        guard FileManager.default.fileExists(atPath: datasetDir.path) else {
            state.trainingStatus = .failed(reason: "Dataset directory not found on disk")
            return
        }

        // Set up state
        state.trainingModelID = model.id
        state.trainingLog = []
        state.liveMetrics = TrainingMetrics()
        state.trainingStatus = .preparingEnvironment
        model.status = .training
        ModelStore.saveModel(model)

        // Create working directory
        let workDir = ModelStore.modelDirectory(for: model.id).appendingPathComponent("training")
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            state.trainingStatus = .failed(reason: "Failed to create working directory: \(error.localizedDescription)")
            model.status = .designed
            ModelStore.saveModel(model)
            return
        }

        // Write train.py + requirements.txt pointing at internal dataset
        do {
            let hash = try TrainingScriptGenerator.writeTrainingFiles(
                model: model,
                datasetPath: datasetDir.path,
                to: workDir
            )
            model.scriptHash = hash
            ModelStore.saveModel(model)
            state.appendLog("Wrote train.py and requirements.txt")
        } catch {
            state.trainingStatus = .failed(reason: "Failed to write training files: \(error.localizedDescription)")
            model.status = .designed
            ModelStore.saveModel(model)
            return
        }

        let env = buildEnvironment()

        // Create virtual environment (avoids PEP 668 "externally managed" errors)
        let venvDir = workDir.appendingPathComponent(".venv")
        let venvPython = venvDir.appendingPathComponent("bin/python3").path

        if !FileManager.default.fileExists(atPath: venvPython) {
            state.appendLog("Creating virtual environment...")
            let venvExitCode: Int32
            do {
                venvExitCode = try await runProcess(
                    executable: pythonPath,
                    arguments: ["-m", "venv", venvDir.path],
                    workingDirectory: workDir,
                    environment: env,
                    state: state,
                    onStdoutLine: { line in
                        Task { @MainActor in state.appendLog(line) }
                    },
                    onStderrLine: { line in
                        Task { @MainActor in state.appendLog("[venv] \(line)") }
                    }
                )
            } catch {
                await handleCancellationOrFailure(error: error, model: model, state: state)
                return
            }

            if venvExitCode != 0 {
                await MainActor.run {
                    state.trainingStatus = .failed(reason: "Failed to create virtual environment (exit code \(venvExitCode))")
                    model.status = .designed
                    ModelStore.saveModel(model)
                }
                return
            }
            state.appendLog("Virtual environment created")
        } else {
            state.appendLog("Using existing virtual environment")
        }

        // Install dependencies using venv pip (skip if already done)
        let depsMarker = workDir.appendingPathComponent(".deps_installed")
        if FileManager.default.fileExists(atPath: depsMarker.path) {
            state.appendLog("Dependencies already installed, skipping pip install")
        } else {
            state.trainingStatus = .installingDependencies
            state.appendLog("[pip] Installing dependencies...")

            let pipExitCode: Int32
            do {
                pipExitCode = try await runProcess(
                    executable: venvPython,
                    arguments: ["-m", "pip", "install", "-r", "requirements.txt"],
                    workingDirectory: workDir,
                    environment: env,
                    state: state,
                    onStdoutLine: { line in
                        Task { @MainActor in state.appendLog("[pip] \(line)") }
                    },
                    onStderrLine: { line in
                        Task { @MainActor in state.appendLog("[pip] \(line)") }
                    }
                )
            } catch {
                await handleCancellationOrFailure(error: error, model: model, state: state)
                return
            }

            if pipExitCode != 0 {
                await MainActor.run {
                    state.trainingStatus = .failed(reason: "pip install failed (exit code \(pipExitCode))")
                    model.status = .designed
                    ModelStore.saveModel(model)
                }
                return
            }

            // Mark deps as installed
            FileManager.default.createFile(atPath: depsMarker.path, contents: nil)
        }

        // Run training using venv python
        let totalEpochs = model.architecture.epochs
        await MainActor.run {
            state.trainingStatus = .training(epoch: 0, totalEpochs: totalEpochs)
            state.appendLog("[train] Starting training...")
        }

        let trainExitCode: Int32
        do {
            trainExitCode = try await runProcess(
                executable: venvPython,
                arguments: ["train.py"],
                workingDirectory: workDir,
                environment: env,
                state: state,
                onStdoutLine: { line in
                    Task { @MainActor in
                        state.appendLog(line)
                        if let epoch = parseEpochLine(line) {
                            state.trainingStatus = .training(epoch: epoch.epoch, totalEpochs: totalEpochs)
                            // Update live metrics
                            state.liveMetrics?.trainLoss.append(MetricPoint(epoch: epoch.epoch, value: epoch.trainLoss))
                            state.liveMetrics?.validLoss.append(MetricPoint(epoch: epoch.epoch, value: epoch.validLoss))
                            state.liveMetrics?.trainAccuracy.append(MetricPoint(epoch: epoch.epoch, value: epoch.trainAcc))
                            state.liveMetrics?.validAccuracy.append(MetricPoint(epoch: epoch.epoch, value: epoch.validAcc))
                            if epoch.isBest {
                                state.liveMetrics?.bestEpoch = epoch.epoch
                            }
                        }
                    }
                },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[stderr] \(line)") }
                }
            )
        } catch {
            await handleCancellationOrFailure(error: error, model: model, state: state)
            return
        }

        if trainExitCode != 0 {
            await MainActor.run {
                state.savePartialMetrics()
                state.trainingStatus = .failed(reason: "Training failed (exit code \(trainExitCode))")
                model.status = .designed
                ModelStore.saveModel(model)
            }
            return
        }

        // Import results
        await MainActor.run {
            state.trainingStatus = .importingResults
            state.appendLog("Importing results...")
        }

        // Auto-import metrics.json
        let metricsURL = workDir.appendingPathComponent("metrics.json")
        if FileManager.default.fileExists(atPath: metricsURL.path) {
            do {
                let data = try Data(contentsOf: metricsURL)
                let metrics = try JSONDecoder().decode(TrainingMetrics.self, from: data)
                await MainActor.run {
                    model.metrics = metrics
                    ModelStore.saveMetrics(metrics, for: model.id)
                    state.appendLog("Imported metrics.json")
                }
            } catch {
                await MainActor.run {
                    state.appendLog("Warning: Failed to parse metrics.json: \(error.localizedDescription)")
                }
            }
        }

        // Auto-import model.mlpackage if present
        let mlpackageURL = workDir.appendingPathComponent("model.mlpackage")
        if FileManager.default.fileExists(atPath: mlpackageURL.path) {
            do {
                try ModelStore.importCoreMLModel(from: mlpackageURL, for: model.id)
                await MainActor.run {
                    model.hasImportedModel = true
                    state.appendLog("Imported model.mlpackage")
                }
            } catch {
                await MainActor.run {
                    state.appendLog("Warning: Failed to import Core ML model: \(error.localizedDescription)")
                }
            }
        }

        // Mark complete
        await MainActor.run {
            model.trainedAt = Date()
            model.status = .trained
            ModelStore.saveModel(model)
            state.trainingStatus = .completed
            state.appendLog("Training complete!")
        }
    }

    /// Cancel the running training process.
    @MainActor
    static func cancel(state: ModelState) {
        currentProcess?.terminate()
        currentProcess = nil
        state.savePartialMetrics()
        if let model = state.trainingModel {
            model.status = .designed
            ModelStore.saveModel(model)
        }
        state.trainingStatus = .cancelled
        state.appendLog("Training cancelled by user.")
    }

    // MARK: - Subprocess Runner

    /// Run a process and stream stdout/stderr line by line.
    private static func runProcess(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
        state: ModelState,
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = environment

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

            // Buffer for partial lines
            let stdoutBuffer = LineBuffer { line in onStdoutLine(line) }
            let stderrBuffer = LineBuffer { line in onStderrLine(line) }

            stdoutPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    stdoutBuffer.flush()
                    stdoutPipe.fileHandleForReading.readabilityHandler = nil
                } else {
                    stdoutBuffer.append(data)
                }
            }

            stderrPipe.fileHandleForReading.readabilityHandler = { handle in
                let data = handle.availableData
                if data.isEmpty {
                    stderrBuffer.flush()
                    stderrPipe.fileHandleForReading.readabilityHandler = nil
                } else {
                    stderrBuffer.append(data)
                }
            }

            process.terminationHandler = { proc in
                // Flush any remaining buffered data
                stdoutBuffer.flush()
                stderrBuffer.flush()
                currentProcess = nil
                continuation.resume(returning: proc.terminationStatus)
            }

            do {
                currentProcess = process
                try process.run()
            } catch {
                currentProcess = nil
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Epoch Parsing

    /// Parsed result from a training epoch output line.
    struct EpochResult {
        let epoch: Int
        let trainLoss: Double
        let trainAcc: Double
        let validLoss: Double
        let validAcc: Double
        let isBest: Bool
    }

    /// Parse a line like: "Epoch   1/50 | Train Loss: 0.6932 Acc: 0.5123 | Valid Loss: 0.6890 Acc: 0.5234 *"
    static func parseEpochLine(_ line: String) -> EpochResult? {
        // Pattern: Epoch <num>/<total> | Train Loss: <f> Acc: <f> | Valid Loss: <f> Acc: <f> [*]
        let pattern = #"Epoch\s+(\d+)/(\d+)\s*\|\s*Train Loss:\s*([\d.]+)\s*Acc:\s*([\d.]+)\s*\|\s*Valid Loss:\s*([\d.]+)\s*Acc:\s*([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }

        func capture(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: line) else { return nil }
            return String(line[r])
        }

        guard
            let epochStr = capture(1), let epoch = Int(epochStr),
            let trainLossStr = capture(3), let trainLoss = Double(trainLossStr),
            let trainAccStr = capture(4), let trainAcc = Double(trainAccStr),
            let validLossStr = capture(5), let validLoss = Double(validLossStr),
            let validAccStr = capture(6), let validAcc = Double(validAccStr)
        else { return nil }

        let isBest = line.hasSuffix("*")

        return EpochResult(
            epoch: epoch,
            trainLoss: trainLoss,
            trainAcc: trainAcc,
            validLoss: validLoss,
            validAcc: validAcc,
            isBest: isBest
        )
    }

    // MARK: - Helpers

    private static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        // Prepend common Python install paths
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + existingPath
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    private static func handleCancellationOrFailure(error: Error, model: SiameseModel, state: ModelState) async {
        await MainActor.run {
            state.savePartialMetrics()
            if (error as NSError).domain == NSCocoaErrorDomain {
                state.trainingStatus = .cancelled
                state.appendLog("Training cancelled.")
            } else {
                state.trainingStatus = .failed(reason: error.localizedDescription)
            }
            model.status = .designed
            ModelStore.saveModel(model)
        }
    }
}

// MARK: - Line Buffer

/// Accumulates data and emits complete lines (split on newline).
/// Used to handle partial reads from Pipe.
final class LineBuffer: @unchecked Sendable {
    private var buffer = Data()
    private let handler: (String) -> Void

    init(handler: @escaping (String) -> Void) {
        self.handler = handler
    }

    func append(_ data: Data) {
        buffer.append(data)
        // Split on newlines and emit complete lines
        while let newlineIndex = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let lineData = buffer[buffer.startIndex..<newlineIndex]
            buffer = Data(buffer[(newlineIndex + 1)...])
            if let line = String(data: lineData, encoding: .utf8) {
                handler(line)
            }
        }
    }

    func flush() {
        guard !buffer.isEmpty else { return }
        if let line = String(data: buffer, encoding: .utf8), !line.isEmpty {
            handler(line)
        }
        buffer = Data()
    }
}
