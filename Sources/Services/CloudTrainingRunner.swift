import Foundation

/// Manages cloud-based model training via SSH (e.g. RunPod GPU instances).
/// Stateless enum (matching TrainingRunner pattern).
///
/// Pipeline: validate -> upload dataset -> upload scripts -> install deps + train (SSH) -> download results -> import
enum CloudTrainingRunner {

    /// Holds a reference to the running SSH/SCP process for cancellation.
    nonisolated(unsafe) private static var currentProcess: Process?
    /// Stores the cloud config of the active training session for remote cleanup on cancel.
    nonisolated(unsafe) private static var activeConfig: CloudConfig?

    // MARK: - SSH/SCP Flag Builders

    private static func sshFlags(_ config: CloudConfig) -> [String] {
        [
            "-i", config.resolvedKeyPath,
            "-p", "\(config.port)",
            "-o", "StrictHostKeyChecking=accept-new",
            "-o", "ConnectTimeout=10",
        ]
    }

    private static func scpFlags(_ config: CloudConfig) -> [String] {
        [
            "-i", config.resolvedKeyPath,
            "-P", "\(config.port)",
            "-o", "StrictHostKeyChecking=accept-new",
        ]
    }

    private static func remoteTarget(_ config: CloudConfig) -> String {
        "\(config.username)@\(config.hostname)"
    }

    // MARK: - Test Connection

    /// Test SSH connectivity. Returns (success, message).
    static func testConnection(config: CloudConfig) async -> (Bool, String) {
        guard config.isValid else {
            return (false, "Invalid config - check hostname and SSH key path")
        }

        let args = sshFlags(config) + [remoteTarget(config), "echo ok"]

        do {
            let exitCode = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: args,
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { _ in },
                onStderrLine: { _ in }
            )
            if exitCode == 0 {
                return (true, "Connection successful")
            } else {
                return (false, "SSH exited with code \(exitCode)")
            }
        } catch {
            return (false, "Connection failed: \(error.localizedDescription)")
        }
    }

    // MARK: - Training

    /// Main entry point - orchestrates the full cloud training pipeline.
    @MainActor
    static func train(model: SiameseModel, dataset: PuzzleDataset, config: CloudConfig, state: ModelState) async {
        // Validate config
        guard config.isValid else {
            state.trainingStatus = .failed(reason: "Invalid SSH config - check hostname and key path")
            return
        }

        // Validate dataset directory exists locally
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
        activeConfig = config

        // Write train.py + requirements.txt locally to a temp dir
        // Dataset path is relative (./dataset) since we upload it alongside the script
        // Device preference is always auto for cloud - checks CUDA first, then MPS, then CPU
        let tempDir: URL
        do {
            tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("cloud_training_\(model.id.uuidString)")
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)

            var cloudArch = model.architecture
            cloudArch.devicePreference = .auto
            let cloudModel = SiameseModel(
                id: model.id,
                name: model.name,
                sourceDatasetID: model.sourceDatasetID,
                sourceDatasetName: model.sourceDatasetName,
                architecture: cloudArch,
                createdAt: model.createdAt
            )
            try TrainingScriptGenerator.writeTrainingFiles(
                model: cloudModel,
                datasetPath: "./dataset",
                to: tempDir
            )
            state.appendLog("Wrote train.py and requirements.txt")
        } catch {
            state.trainingStatus = .failed(reason: "Failed to write training files: \(error.localizedDescription)")
            model.status = .designed
            ModelStore.saveModel(model)
            return
        }

        let remote = remoteTarget(config)
        let remoteDir = config.remoteWorkDir

        // Step 1: Test SSH connection
        state.appendLog("Testing SSH connection to \(config.hostname)...")
        do {
            let exitCode = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: sshFlags(config) + [remote, "echo ok"],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { _ in },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[ssh] \(line)") }
                }
            )
            if exitCode != 0 {
                await handleFailure(reason: "SSH connection test failed (exit code \(exitCode))", model: model, state: state)
                return
            }
            state.appendLog("SSH connection OK")
        } catch {
            await handleCancellationOrFailure(error: error, model: model, state: state)
            return
        }

        // Step 2: Create remote directory
        state.appendLog("Creating remote directory \(remoteDir)...")
        do {
            let exitCode = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: sshFlags(config) + [remote, "mkdir -p \(remoteDir)"],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { _ in },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[ssh] \(line)") }
                }
            )
            if exitCode != 0 {
                await handleFailure(reason: "Failed to create remote directory (exit code \(exitCode))", model: model, state: state)
                return
            }
        } catch {
            await handleCancellationOrFailure(error: error, model: model, state: state)
            return
        }

        // Step 3: Upload dataset (cached by UUID - skip if already present and complete)
        let remoteDatasetCache = "\(remoteDir)/datasets/\(dataset.id.uuidString)"
        let remoteDatasetLink = "\(remoteDir)/dataset"

        // Count local files for comparison
        let localFileCount = countFiles(in: datasetDir)
        state.appendLog("Local dataset: \(localFileCount) files")

        // Check if dataset already exists on remote with matching file count
        var datasetNeedsUpload = true
        do {
            state.appendLog("Checking for cached dataset on remote...")
            let captured = CapturedLine()
            let exitCode = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: sshFlags(config) + [remote, "test -d \(remoteDatasetCache) && find \(remoteDatasetCache) -type f | wc -l || echo 0"],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { line in
                    captured.value = line.trimmingCharacters(in: .whitespaces)
                },
                onStderrLine: { _ in }
            )
            let remoteCountStr = captured.value
            if exitCode == 0, let remoteCount = Int(remoteCountStr), remoteCount >= localFileCount {
                state.appendLog("Dataset already cached on remote (\(remoteCount) files) - skipping upload")
                datasetNeedsUpload = false
            } else {
                let count = Int(remoteCountStr) ?? 0
                state.appendLog("Remote has \(count) files, local has \(localFileCount) - upload needed")
            }
        } catch {
            state.appendLog("Could not check remote dataset, will upload")
        }

        if datasetNeedsUpload {
            await MainActor.run {
                state.trainingStatus = .uploadingDataset
                state.appendLog("Uploading dataset to \(config.hostname)...")
            }

            // Upload using tar piped through SSH - sends all files in a single stream,
            // much faster than scp -r which opens a transfer per file.
            // tar cf - creates archive to stdout, ssh pipes it to tar xf - on remote.
            do {
                _ = try await runProcess(
                    executable: "/usr/bin/ssh",
                    arguments: sshFlags(config) + [remote, "mkdir -p \(remoteDatasetCache)"],
                    workingDirectory: nil,
                    environment: [:],
                    onStdoutLine: { _ in },
                    onStderrLine: { _ in }
                )

                // Build the tar|ssh pipeline as a shell command.
                // --no-mac-metadata strips Apple xattrs/resource forks from the archive.
                // --no-same-owner prevents remote tar from trying to set macOS UIDs.
                let sshCmd = "ssh -i \(config.resolvedKeyPath) -p \(config.port) -o StrictHostKeyChecking=accept-new -o ConnectTimeout=10"
                let tarPipeline = "tar cf - --no-mac-metadata -C \"\(datasetDir.path)\" . | \(sshCmd) \(remote) \"tar xf - --no-same-owner -C \(remoteDatasetCache)\""

                let exitCode = try await runProcess(
                    executable: "/bin/sh",
                    arguments: ["-c", tarPipeline],
                    workingDirectory: nil,
                    environment: ["COPYFILE_DISABLE": "1"],
                    onStdoutLine: { line in
                        Task { @MainActor in state.appendLog("[upload] \(line)") }
                    },
                    onStderrLine: { line in
                        // Filter out macOS tar metadata warnings that flood the log
                        if line.contains("LIBARCHIVE.xattr") || line.contains("Cannot change ownership") { return }
                        Task { @MainActor in state.appendLog("[upload] \(line)") }
                    }
                )

                if exitCode != 0 {
                    await handleFailure(reason: "Dataset upload failed (exit code \(exitCode))", model: model, state: state)
                    return
                }
                state.appendLog("Dataset uploaded (\(localFileCount) files)")
            } catch {
                await handleCancellationOrFailure(error: error, model: model, state: state)
                return
            }
        }

        // Create/update symlink so train.py can read from ./dataset
        do {
            let exitCode = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: sshFlags(config) + [remote, "ln -sfn \(remoteDatasetCache) \(remoteDatasetLink)"],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { _ in },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[ssh] \(line)") }
                }
            )
            if exitCode != 0 {
                await handleFailure(reason: "Failed to create dataset symlink", model: model, state: state)
                return
            }
        } catch {
            await handleCancellationOrFailure(error: error, model: model, state: state)
            return
        }

        // Step 4: Upload training scripts
        state.appendLog("Uploading training scripts...")
        do {
            let trainPy = tempDir.appendingPathComponent("train.py").path
            let reqTxt = tempDir.appendingPathComponent("requirements.txt").path
            let exitCode = try await runProcess(
                executable: "/usr/bin/scp",
                arguments: scpFlags(config) + [trainPy, reqTxt, "\(remote):\(remoteDir)/"],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { _ in },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[scp] \(line)") }
                }
            )
            if exitCode != 0 {
                await handleFailure(reason: "Script upload failed (exit code \(exitCode))", model: model, state: state)
                return
            }
            state.appendLog("Scripts uploaded")
        } catch {
            await handleCancellationOrFailure(error: error, model: model, state: state)
            return
        }

        // Step 5: Install deps + run training in one SSH session
        await MainActor.run {
            state.trainingStatus = .installingDependencies
            state.appendLog("Installing dependencies and starting training...")
        }

        let totalEpochs = model.architecture.epochs
        // Smart pip install:
        // 1. Check if CUDA PyTorch already works -> only install non-torch deps
        // 2. Otherwise, install torch+torchvision from PyTorch CUDA index (--index-url
        //    replaces PyPI so pip can't prefer a newer CPU-only version), then other deps
        // --root-user-action=ignore suppresses the venv warning when running as root
        let pipCommand = """
            if python -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then \
                echo "CUDA PyTorch already available"; \
                pip install --root-user-action=ignore pandas>=1.5 Pillow>=9.0 numpy>=1.24 scikit-learn>=1.2; \
            else \
                echo "Installing CUDA PyTorch..."; \
                pip install --root-user-action=ignore torch torchvision --index-url https://download.pytorch.org/whl/cu124; \
                pip install --root-user-action=ignore pandas>=1.5 Pillow>=9.0 numpy>=1.24 scikit-learn>=1.2; \
            fi
            """
        let remoteCommand = "cd \(remoteDir) && \(pipCommand) && PYTHONUNBUFFERED=1 python train.py"

        do {
            let exitCode = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: sshFlags(config) + [remote, remoteCommand],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { line in
                    Task { @MainActor in
                        state.appendLog(line)
                        if let epoch = TrainingRunner.parseEpochLine(line) {
                            state.trainingStatus = .training(epoch: epoch.epoch, totalEpochs: totalEpochs)
                            state.liveMetrics?.trainLoss.append(MetricPoint(epoch: epoch.epoch, value: epoch.trainLoss))
                            state.liveMetrics?.validLoss.append(MetricPoint(epoch: epoch.epoch, value: epoch.validLoss))
                            state.liveMetrics?.trainAccuracy.append(MetricPoint(epoch: epoch.epoch, value: epoch.trainAcc))
                            state.liveMetrics?.validAccuracy.append(MetricPoint(epoch: epoch.epoch, value: epoch.validAcc))
                            if epoch.isBest {
                                state.liveMetrics?.bestEpoch = epoch.epoch
                            }
                        } else if line.contains("Installing") || line.contains("Collecting") || line.contains("Downloading") {
                            // Still in pip install phase
                            if case .installingDependencies = state.trainingStatus {
                                // Keep status as-is
                            }
                        } else if line.contains("Training for") || line.contains("Train:") {
                            // Training preamble - switch to training status
                            state.trainingStatus = .training(epoch: 0, totalEpochs: totalEpochs)
                        }
                    }
                },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[stderr] \(line)") }
                }
            )
            if exitCode != 0 {
                await handleFailure(reason: "Remote training failed (exit code \(exitCode))", model: model, state: state)
                return
            }
        } catch {
            await handleCancellationOrFailure(error: error, model: model, state: state)
            return
        }

        // Step 6: Download results
        await MainActor.run {
            state.trainingStatus = .downloadingResults
            state.appendLog("Downloading results...")
        }

        let localResultsDir = ModelStore.modelDirectory(for: model.id).appendingPathComponent("training")
        try? FileManager.default.createDirectory(at: localResultsDir, withIntermediateDirectories: true)

        // Download metrics.json
        do {
            let exitCode = try await runProcess(
                executable: "/usr/bin/scp",
                arguments: scpFlags(config) + ["\(remote):\(remoteDir)/metrics.json", localResultsDir.path + "/"],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { _ in },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[scp] \(line)") }
                }
            )
            if exitCode == 0 {
                state.appendLog("Downloaded metrics.json")
            } else {
                state.appendLog("Warning: Failed to download metrics.json (exit code \(exitCode))")
            }
        } catch {
            await MainActor.run {
                state.appendLog("Warning: Failed to download metrics.json: \(error.localizedDescription)")
            }
        }

        // Try downloading model.mlpackage (may not exist if coremltools not installed)
        do {
            let exitCode = try await runProcess(
                executable: "/usr/bin/scp",
                arguments: scpFlags(config) + ["-r", "\(remote):\(remoteDir)/model.mlpackage", localResultsDir.path + "/"],
                workingDirectory: nil,
                environment: [:],
                onStdoutLine: { _ in },
                onStderrLine: { _ in }
            )
            if exitCode == 0 {
                await MainActor.run { state.appendLog("Downloaded model.mlpackage") }
            }
        } catch {
            // model.mlpackage is optional - ignore failures
        }

        // Step 7: Import results (same as TrainingRunner)
        await MainActor.run {
            state.trainingStatus = .importingResults
            state.appendLog("Importing results...")
        }

        let metricsURL = localResultsDir.appendingPathComponent("metrics.json")
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

        let mlpackageURL = localResultsDir.appendingPathComponent("model.mlpackage")
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

        // Clean up temp dir
        try? FileManager.default.removeItem(at: tempDir)

        // Mark complete
        await MainActor.run {
            model.status = .trained
            ModelStore.saveModel(model)
            state.trainingStatus = .completed
            state.appendLog("Training complete!")
        }
    }

    // MARK: - Cancel

    /// Cancel the running cloud training process and kill the remote training.
    @MainActor
    static func cancel(state: ModelState) {
        currentProcess?.terminate()
        currentProcess = nil
        if let model = state.trainingModel {
            model.status = .designed
            ModelStore.saveModel(model)
        }
        state.trainingStatus = .cancelled
        state.appendLog("Cloud training cancelled by user.")

        // Kill the remote training process so it doesn't keep running orphaned
        if let config = activeConfig {
            let remote = remoteTarget(config)
            let flags = sshFlags(config)
            activeConfig = nil
            Task.detached {
                let process = Process()
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = flags + [remote, "pkill -f 'python train.py'"]
                process.standardOutput = FileHandle.nullDevice
                process.standardError = FileHandle.nullDevice
                try? process.run()
                process.waitUntilExit()
            }
        }
    }

    // MARK: - Subprocess Runner

    /// Run a process and stream stdout/stderr line by line.
    /// Independent copy from TrainingRunner to keep the two runners decoupled.
    private static func runProcess(
        executable: String,
        arguments: [String],
        workingDirectory: URL?,
        environment: [String: String],
        onStdoutLine: @escaping @Sendable (String) -> Void,
        onStderrLine: @escaping @Sendable (String) -> Void
    ) async throws -> Int32 {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: executable)
            process.arguments = arguments
            if let wd = workingDirectory {
                process.currentDirectoryURL = wd
            }
            if !environment.isEmpty {
                process.environment = environment
            }

            let stdoutPipe = Pipe()
            let stderrPipe = Pipe()
            process.standardOutput = stdoutPipe
            process.standardError = stderrPipe

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

    // MARK: - Helpers

    /// Thread-safe container for capturing a single line from a process callback.
    private final class CapturedLine: @unchecked Sendable {
        var value: String = ""
    }

    /// Count all files recursively in a local directory.
    private static func countFiles(in directory: URL) -> Int {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey],
            options: [.skipsHiddenFiles]
        ) else { return 0 }

        var count = 0
        for case let url as URL in enumerator {
            if let values = try? url.resourceValues(forKeys: [.isRegularFileKey]),
               values.isRegularFile == true {
                count += 1
            }
        }
        return count
    }

    private static func handleFailure(reason: String, model: SiameseModel, state: ModelState) async {
        await MainActor.run {
            state.trainingStatus = .failed(reason: reason)
            model.status = .designed
            ModelStore.saveModel(model)
        }
    }

    private static func handleCancellationOrFailure(error: Error, model: SiameseModel, state: ModelState) async {
        await MainActor.run {
            if (error as NSError).domain == NSCocoaErrorDomain {
                state.trainingStatus = .cancelled
                state.appendLog("Cloud training cancelled.")
            } else {
                state.trainingStatus = .failed(reason: error.localizedDescription)
            }
            model.status = .designed
            ModelStore.saveModel(model)
        }
    }
}
