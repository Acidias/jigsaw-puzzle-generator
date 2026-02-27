import CryptoKit
import Foundation

/// Manages automated AutoML study execution by running Python as a subprocess.
/// Stateless enum (matching TrainingRunner pattern).
enum AutoMLRunner {

    /// Holds a reference to the running process for cancellation.
    nonisolated(unsafe) private static var currentProcess: Process?

    /// Background checkpoint polling task (for cloud training).
    nonisolated(unsafe) private static var checkpointTask: Task<Void, Never>?

    // MARK: - Local Training

    /// Main entry point for local AutoML study execution.
    @MainActor
    static func train(study: AutoMLStudy, dataset: PuzzleDataset, state: AutoMLState, modelState: ModelState) async {
        guard let pythonPath = TrainingRunner.findPython() else {
            state.runningStatus = .failed(reason: "python3 not found")
            return
        }

        let datasetDir = DatasetStore.datasetDirectory(for: dataset.id)
        guard FileManager.default.fileExists(atPath: datasetDir.path) else {
            state.runningStatus = .failed(reason: "Dataset directory not found on disk")
            return
        }

        // Set up state
        state.runningStudyID = study.id
        state.runningLog = []
        state.liveTrials = study.trials  // Preserve any existing trials from resume
        state.liveBestValue = nil
        state.liveBestTrialNumber = nil
        state.currentTrialNumber = 0
        state.currentTrialEpoch = 0
        state.currentTrialTotalEpochs = 0
        state.currentTrialLiveMetrics = nil
        state.runningStatus = .preparingEnvironment
        study.status = .running
        AutoMLStudyStore.saveStudy(study)

        // Create working directory
        let workDir = AutoMLStudyStore.trainingDirectory(for: study.id)
        do {
            try FileManager.default.createDirectory(at: workDir, withIntermediateDirectories: true)
        } catch {
            state.runningStatus = .failed(reason: "Failed to create working directory: \(error.localizedDescription)")
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
            return
        }

        // Write automl_train.py + requirements.txt
        do {
            try AutoMLScriptGenerator.writeTrainingFiles(
                study: study,
                datasetPath: datasetDir.path,
                to: workDir
            )
            state.appendLog("Wrote automl_train.py and requirements.txt")
        } catch {
            state.runningStatus = .failed(reason: "Failed to write training files: \(error.localizedDescription)")
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
            return
        }

        let env = buildEnvironment()

        // Create virtual environment
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
                    onStdoutLine: { line in Task { @MainActor in state.appendLog(line) } },
                    onStderrLine: { line in Task { @MainActor in state.appendLog("[venv] \(line)") } }
                )
            } catch {
                await handleFailure(error: error, study: study, state: state)
                return
            }

            if venvExitCode != 0 {
                await MainActor.run {
                    state.runningStatus = .failed(reason: "Failed to create virtual environment (exit code \(venvExitCode))")
                    study.status = .configured
                    AutoMLStudyStore.saveStudy(study)
                }
                return
            }
            state.appendLog("Virtual environment created")
        } else {
            state.appendLog("Using existing virtual environment")
        }

        // Install dependencies
        let depsMarker = workDir.appendingPathComponent(".deps_installed")
        if FileManager.default.fileExists(atPath: depsMarker.path) {
            state.appendLog("Dependencies already installed, skipping pip install")
        } else {
            state.runningStatus = .installingDependencies
            state.appendLog("[pip] Installing dependencies...")

            let pipExitCode: Int32
            do {
                pipExitCode = try await runProcess(
                    executable: venvPython,
                    arguments: ["-m", "pip", "install", "-r", "requirements.txt"],
                    workingDirectory: workDir,
                    environment: env,
                    onStdoutLine: { line in Task { @MainActor in state.appendLog("[pip] \(line)") } },
                    onStderrLine: { line in Task { @MainActor in state.appendLog("[pip] \(line)") } }
                )
            } catch {
                await handleFailure(error: error, study: study, state: state)
                return
            }

            if pipExitCode != 0 {
                await MainActor.run {
                    state.runningStatus = .failed(reason: "pip install failed (exit code \(pipExitCode))")
                    study.status = .configured
                    AutoMLStudyStore.saveStudy(study)
                }
                return
            }

            FileManager.default.createFile(atPath: depsMarker.path, contents: nil)
        }

        // Run AutoML study
        let totalTrials = study.configuration.numTrials
        await MainActor.run {
            state.runningStatus = .running(trial: 0, totalTrials: totalTrials)
            state.appendLog("[automl] Starting hyperparameter search...")
        }

        let trainExitCode: Int32
        do {
            trainExitCode = try await runProcess(
                executable: venvPython,
                arguments: ["automl_train.py"],
                workingDirectory: workDir,
                environment: env,
                onStdoutLine: { line in
                    Task { @MainActor in
                        state.appendLog(line)
                        parseAutoMLLine(line, state: state, totalTrials: totalTrials)
                    }
                },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[stderr] \(line)") }
                }
            )
        } catch {
            await handleFailure(error: error, study: study, state: state)
            return
        }

        if trainExitCode != 0 {
            await MainActor.run {
                state.savePartialResults()
                state.runningStatus = .failed(reason: "AutoML search failed (exit code \(trainExitCode))")
                study.status = .failed
                AutoMLStudyStore.saveStudy(study)
            }
            return
        }

        // Import results
        await importResults(study: study, state: state, modelState: modelState, workDir: workDir)
    }

    // MARK: - Cloud Training

    /// SSH-based cloud AutoML study execution.
    @MainActor
    static func trainCloud(study: AutoMLStudy, dataset: PuzzleDataset, config: CloudConfig, state: AutoMLState, modelState: ModelState) async {
        guard config.isValid else {
            state.runningStatus = .failed(reason: "Invalid SSH configuration")
            return
        }

        let datasetDir = DatasetStore.datasetDirectory(for: dataset.id)
        guard FileManager.default.fileExists(atPath: datasetDir.path) else {
            state.runningStatus = .failed(reason: "Dataset directory not found on disk")
            return
        }

        // Set up state
        state.runningStudyID = study.id
        state.runningLog = []
        state.liveTrials = study.trials
        state.liveBestValue = nil
        state.liveBestTrialNumber = nil
        state.currentTrialNumber = 0
        state.currentTrialEpoch = 0
        state.currentTrialTotalEpochs = 0
        state.currentTrialLiveMetrics = nil
        state.runningStatus = .preparingEnvironment
        study.status = .running
        AutoMLStudyStore.saveStudy(study)

        // Create local working directory for scripts
        let localWorkDir = AutoMLStudyStore.trainingDirectory(for: study.id)
        do {
            try FileManager.default.createDirectory(at: localWorkDir, withIntermediateDirectories: true)
        } catch {
            state.runningStatus = .failed(reason: "Failed to create working directory: \(error.localizedDescription)")
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
            return
        }

        // Force auto device for cloud (CUDA detection)
        var cloudConfig = study.configuration
        cloudConfig.baseArchitecture.devicePreference = .auto

        let cloudStudy = study
        // Write scripts
        do {
            try AutoMLScriptGenerator.writeTrainingFiles(
                study: cloudStudy,
                datasetPath: "./dataset",
                to: localWorkDir
            )
            state.appendLog("Wrote automl_train.py and requirements.txt")
        } catch {
            state.runningStatus = .failed(reason: "Failed to write training files: \(error.localizedDescription)")
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
            return
        }

        let sshFlags = CloudTrainingRunner.sshFlags(config)
        let scpFlags = CloudTrainingRunner.scpFlags(config)
        let remoteHost = "\(config.username)@\(config.hostname)"
        let remoteDir = "\(config.remoteWorkDir)/automl_\(study.id.uuidString.prefix(8))"

        // Test SSH connection
        state.appendLog("Testing SSH connection...")
        let (success, message) = await CloudTrainingRunner.testConnection(config: config)
        if !success {
            state.runningStatus = .failed(reason: "SSH connection failed: \(message)")
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
            return
        }
        state.appendLog("SSH connection OK")

        // Create remote directory
        let mkdirCode = try? await runSSHCommand(
            sshFlags: sshFlags, remoteHost: remoteHost,
            command: "mkdir -p \(remoteDir)",
            state: state
        )
        guard mkdirCode == 0 else {
            state.runningStatus = .failed(reason: "Failed to create remote directory")
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
            return
        }

        // Upload dataset
        state.runningStatus = .uploadingDataset
        state.appendLog("Uploading dataset...")

        // Check if dataset already cached on remote
        let checkCode = try? await runSSHCommand(
            sshFlags: sshFlags, remoteHost: remoteHost,
            command: "test -d \(config.remoteWorkDir)/datasets/\(dataset.id.uuidString) && echo CACHED",
            state: state
        )

        let datasetRemotePath = "\(config.remoteWorkDir)/datasets/\(dataset.id.uuidString)"
        if checkCode == 0 {
            state.appendLog("Dataset already cached on remote")
        } else {
            // Upload via tar|ssh pipeline
            let tarCode: Int32
            do {
                tarCode = try await runProcess(
                    executable: "/bin/bash",
                    arguments: ["-c", "tar -cf - -C '\(datasetDir.deletingLastPathComponent().path)' '\(datasetDir.lastPathComponent)' | ssh \(sshFlags.joined(separator: " ")) \(remoteHost) 'mkdir -p \(datasetRemotePath) && tar -xf - -C \(datasetRemotePath) --strip-components=1'"],
                    workingDirectory: localWorkDir,
                    environment: ProcessInfo.processInfo.environment,
                    onStdoutLine: { _ in },
                    onStderrLine: { line in Task { @MainActor in state.appendLog("[upload] \(line)") } }
                )
            } catch {
                await handleFailure(error: error, study: study, state: state)
                return
            }
            if tarCode != 0 {
                state.runningStatus = .failed(reason: "Dataset upload failed")
                study.status = .configured
                AutoMLStudyStore.saveStudy(study)
                return
            }
            state.appendLog("Dataset uploaded")
        }

        // Create symlink
        _ = try? await runSSHCommand(
            sshFlags: sshFlags, remoteHost: remoteHost,
            command: "ln -sfn \(datasetRemotePath) \(remoteDir)/dataset",
            state: state
        )

        // Upload scripts
        state.appendLog("Uploading scripts...")
        let scpCode: Int32
        do {
            let scriptPath = localWorkDir.appendingPathComponent("automl_train.py").path
            let reqPath = localWorkDir.appendingPathComponent("requirements.txt").path
            scpCode = try await runProcess(
                executable: "/usr/bin/scp",
                arguments: scpFlags + [scriptPath, reqPath, "\(remoteHost):\(remoteDir)/"],
                workingDirectory: localWorkDir,
                environment: ProcessInfo.processInfo.environment,
                onStdoutLine: { _ in },
                onStderrLine: { line in Task { @MainActor in state.appendLog("[scp] \(line)") } }
            )
        } catch {
            await handleFailure(error: error, study: study, state: state)
            return
        }
        if scpCode != 0 {
            state.runningStatus = .failed(reason: "Script upload failed")
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
            return
        }
        state.appendLog("Scripts uploaded")

        // Start checkpoint polling
        let pollStudyID = study.id
        let pollRemoteDir = remoteDir
        checkpointTask = Task.detached {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60_000_000_000) // 60 seconds
                if Task.isCancelled { break }

                // SCP optuna_results.json from remote
                let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                let tempResults = tempDir.appendingPathComponent("optuna_results.json")

                let proc = Process()
                proc.executableURL = URL(fileURLWithPath: "/usr/bin/scp")
                proc.arguments = scpFlags + ["\(remoteHost):\(pollRemoteDir)/optuna_results.json", tempResults.path]
                proc.standardOutput = FileHandle.nullDevice
                proc.standardError = FileHandle.nullDevice
                try? proc.run()
                proc.waitUntilExit()

                if proc.terminationStatus == 0, let data = try? Data(contentsOf: tempResults) {
                    if let trials = try? JSONDecoder().decode([AutoMLTrial].self, from: data) {
                        await MainActor.run {
                            state.liveTrials = trials
                            let completedTrials = trials.filter { $0.state == .complete }
                            if let best = completedTrials.max(by: { ($0.value ?? 0) < ($1.value ?? 0) }) {
                                state.liveBestValue = best.value
                                state.liveBestTrialNumber = best.trialNumber
                            }
                            // Persist partial results
                            if let study = state.studies.first(where: { $0.id == pollStudyID }) {
                                study.trials = trials
                                study.completedTrials = completedTrials.count
                                AutoMLStudyStore.saveStudy(study)
                            }
                        }
                    }
                }
                try? FileManager.default.removeItem(at: tempDir)
            }
        }

        // Install deps + run training
        let totalTrials = study.configuration.numTrials
        await MainActor.run {
            state.runningStatus = .installingDependencies
            state.appendLog("Installing dependencies and starting training...")
        }

        // Smart pip install: check for existing CUDA PyTorch, install Optuna + deps
        let pipFlags = "--root-user-action=ignore --break-system-packages"
        let pipCommand = """
            if python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null && python3 -c "import optuna" 2>/dev/null; then \
                echo "CUDA PyTorch and Optuna already available"; \
            elif python3 -c "import torch; assert torch.cuda.is_available()" 2>/dev/null; then \
                echo "CUDA PyTorch available, installing Optuna..."; \
                pip3 install \(pipFlags) optuna>=3.0 pandas>=1.5 Pillow>=9.0 numpy>=1.24 scikit-learn>=1.2; \
            else \
                echo "Installing CUDA PyTorch + Optuna..."; \
                pip3 install \(pipFlags) torch torchvision --index-url https://download.pytorch.org/whl/cu124; \
                pip3 install \(pipFlags) optuna>=3.0 pandas>=1.5 Pillow>=9.0 numpy>=1.24 scikit-learn>=1.2; \
            fi
            """
        let remoteCommand = "cd \(remoteDir) && \(pipCommand) && echo 'Starting AutoML search...' && PYTHONUNBUFFERED=1 python3 automl_train.py"

        let sshTrainCode: Int32
        do {
            sshTrainCode = try await runProcess(
                executable: "/usr/bin/ssh",
                arguments: sshFlags + [remoteHost, remoteCommand],
                workingDirectory: localWorkDir,
                environment: ProcessInfo.processInfo.environment,
                onStdoutLine: { line in
                    Task { @MainActor in
                        state.appendLog(line)
                        // Detect transition from pip install to training
                        if line.contains("Starting AutoML search") || line.hasPrefix("AUTOML_START") {
                            state.runningStatus = .running(trial: 0, totalTrials: totalTrials)
                        }
                        parseAutoMLLine(line, state: state, totalTrials: totalTrials)
                    }
                },
                onStderrLine: { line in
                    Task { @MainActor in state.appendLog("[ssh] \(line)") }
                }
            )
        } catch {
            checkpointTask?.cancel()
            checkpointTask = nil
            await handleFailure(error: error, study: study, state: state)
            return
        }

        checkpointTask?.cancel()
        checkpointTask = nil

        if sshTrainCode != 0 {
            await MainActor.run {
                state.savePartialResults()
                state.runningStatus = .failed(reason: "Cloud AutoML search failed (exit code \(sshTrainCode))")
                study.status = .failed
                AutoMLStudyStore.saveStudy(study)
            }
            return
        }

        // Download results
        await MainActor.run {
            state.runningStatus = .downloadingResults
            state.appendLog("Downloading results...")
        }

        // Download optuna_results.json, best_metrics.json, best_model.pth
        for filename in ["optuna_results.json", "best_metrics.json", "best_model.pth"] {
            let dlCode: Int32
            do {
                dlCode = try await runProcess(
                    executable: "/usr/bin/scp",
                    arguments: scpFlags + ["\(remoteHost):\(remoteDir)/\(filename)", localWorkDir.appendingPathComponent(filename).path],
                    workingDirectory: localWorkDir,
                    environment: ProcessInfo.processInfo.environment,
                    onStdoutLine: { _ in },
                    onStderrLine: { line in Task { @MainActor in state.appendLog("[scp] \(line)") } }
                )
            } catch {
                await MainActor.run { state.appendLog("Warning: Failed to download \(filename)") }
                continue
            }
            if dlCode == 0 {
                await MainActor.run { state.appendLog("Downloaded \(filename)") }
            }
        }

        // Import results
        await importResults(study: study, state: state, modelState: modelState, workDir: localWorkDir)
    }

    // MARK: - Cancel

    @MainActor
    static func cancel(state: AutoMLState) {
        currentProcess?.terminate()
        currentProcess = nil
        checkpointTask?.cancel()
        checkpointTask = nil
        state.savePartialResults()
        if let study = state.runningStudy {
            study.status = .cancelled
            AutoMLStudyStore.saveStudy(study)
        }
        state.runningStatus = .cancelled
        state.appendLog("AutoML search cancelled by user.")
    }

    // MARK: - Results Import

    @MainActor
    private static func importResults(study: AutoMLStudy, state: AutoMLState, modelState: ModelState, workDir: URL) async {
        state.runningStatus = .importingResults
        state.appendLog("Importing results...")

        // Load optuna_results.json
        let resultsURL = workDir.appendingPathComponent("optuna_results.json")
        if FileManager.default.fileExists(atPath: resultsURL.path) {
            do {
                let data = try Data(contentsOf: resultsURL)
                let trials = try JSONDecoder().decode([AutoMLTrial].self, from: data)
                study.trials = trials
                study.completedTrials = trials.filter { $0.state == .complete }.count
                state.appendLog("Imported \(trials.count) trial results")
            } catch {
                state.appendLog("Warning: Failed to parse optuna_results.json: \(error.localizedDescription)")
            }
        }

        // Load best_metrics.json and create a SiameseModel
        let metricsURL = workDir.appendingPathComponent("best_metrics.json")
        if FileManager.default.fileExists(atPath: metricsURL.path) {
            do {
                let data = try Data(contentsOf: metricsURL)
                let metrics = try JSONDecoder().decode(TrainingMetrics.self, from: data)

                // Find best trial and reconstruct architecture
                let completedTrials = study.trials.filter { $0.state == .complete }
                let config = study.configuration
                let isMaximise = config.optimisationMetric.direction == "maximize"
                let bestTrial = isMaximise
                    ? completedTrials.max(by: { ($0.value ?? -Double.infinity) < ($1.value ?? -Double.infinity) })
                    : completedTrials.min(by: { ($0.value ?? Double.infinity) < ($1.value ?? Double.infinity) })

                if let bestTrial = bestTrial {
                    study.bestTrialNumber = bestTrial.trialNumber

                    let arch = architectureFromParams(config.baseArchitecture, bestTrial.params)
                    let model = SiameseModel(
                        name: "\(study.name) - Best (Trial \(bestTrial.trialNumber))",
                        sourceDatasetID: study.sourceDatasetID,
                        sourceDatasetName: study.sourceDatasetName,
                        architecture: arch,
                        status: .trained,
                        metrics: metrics,
                        sourcePresetName: study.sourcePresetName,
                        notes: "Auto-imported from AutoML study '\(study.name)'. Trial \(bestTrial.trialNumber) of \(study.configuration.numTrials).",
                        trainedAt: Date()
                    )
                    modelState.addModel(model)
                    study.bestModelID = model.id
                    state.appendLog("Created model '\(model.name)' from best trial")
                }
            } catch {
                state.appendLog("Warning: Failed to import best model: \(error.localizedDescription)")
            }
        }

        // Mark complete
        study.status = .completed
        AutoMLStudyStore.saveStudy(study)
        state.runningStatus = .completed
        state.appendLog("AutoML search complete!")
    }

    // MARK: - Architecture Reconstruction

    /// Reconstruct a SiameseArchitecture from Optuna trial params merged with base architecture.
    static func architectureFromParams(_ base: SiameseArchitecture, _ params: [String: String]) -> SiameseArchitecture {
        var arch = base

        if let n = Int(params["numConvBlocks"] ?? "") {
            let filtersBase = Int(params["filtersBase"] ?? "") ?? (base.convBlocks.first?.filters ?? 32)
            let ks = Int(params["kernelSize"] ?? "") ?? (base.convBlocks.first?.kernelSize ?? 3)
            let bn: Bool
            if let bnStr = params["useBatchNorm"] {
                bn = bnStr.lowercased() == "true"
            } else {
                bn = base.convBlocks.first?.useBatchNorm ?? true
            }
            arch.convBlocks = (0..<n).map { i in
                ConvBlock(filters: filtersBase * (1 << min(i, 4)), kernelSize: ks, useBatchNorm: bn, useMaxPool: true)
            }
        } else {
            // Maybe just filtersBase or kernelSize changed
            if let fb = Int(params["filtersBase"] ?? "") {
                let ks = Int(params["kernelSize"] ?? "") ?? (base.convBlocks.first?.kernelSize ?? 3)
                let bn: Bool
                if let bnStr = params["useBatchNorm"] {
                    bn = bnStr.lowercased() == "true"
                } else {
                    bn = base.convBlocks.first?.useBatchNorm ?? true
                }
                arch.convBlocks = (0..<base.convBlocks.count).map { i in
                    ConvBlock(filters: fb * (1 << min(i, 4)), kernelSize: ks, useBatchNorm: bn, useMaxPool: true)
                }
            }
        }

        if let emb = Int(params["embeddingDimension"] ?? "") {
            arch.embeddingDimension = emb
        }
        if let comp = params["comparisonMethod"], let method = ComparisonMethod(rawValue: comp) {
            arch.comparisonMethod = method
        }
        if let d = Double(params["dropout"] ?? "") {
            arch.dropout = d
        }
        if let lr = Double(params["learningRate"] ?? "") {
            arch.learningRate = lr
        }
        if let bs = Int(params["batchSize"] ?? "") {
            arch.batchSize = bs
        }
        if let ep = Int(params["epochs"] ?? "") {
            arch.epochs = ep
        }
        if let fc = params["useFourClass"] {
            arch.useFourClass = fc.lowercased() == "true"
        }
        if let so = params["useSeamOnly"] {
            arch.useSeamOnly = so.lowercased() == "true"
        }
        if let sw = Int(params["seamWidth"] ?? "") {
            arch.seamWidth = sw
        }

        return arch
    }

    // MARK: - Stdout Parsing

    /// Parse structured AutoML stdout lines and update state.
    @MainActor
    private static func parseAutoMLLine(_ line: String, state: AutoMLState, totalTrials: Int) {
        // AUTOML_START total=N completed=M remaining=R
        if line.hasPrefix("AUTOML_START") {
            if let completed = extractInt(from: line, key: "completed") {
                state.runningStatus = .running(trial: completed, totalTrials: totalTrials)
            }
            return
        }

        // AUTOML_EPOCH Trial T Epoch E/N | Train Loss: X Acc: Y | Valid Loss: X Acc: Y
        if line.hasPrefix("AUTOML_EPOCH") {
            if let parsed = parseAutoMLEpochLine(line) {
                state.currentTrialNumber = parsed.trial
                state.currentTrialEpoch = parsed.epoch
                state.currentTrialTotalEpochs = parsed.totalEpochs
                // Update live metrics for current trial
                if state.currentTrialLiveMetrics == nil || parsed.epoch == 1 {
                    state.currentTrialLiveMetrics = TrainingMetrics()
                }
                state.currentTrialLiveMetrics?.trainLoss.append(MetricPoint(epoch: parsed.epoch, value: parsed.trainLoss))
                state.currentTrialLiveMetrics?.validLoss.append(MetricPoint(epoch: parsed.epoch, value: parsed.validLoss))
                state.currentTrialLiveMetrics?.trainAccuracy.append(MetricPoint(epoch: parsed.epoch, value: parsed.trainAcc))
                state.currentTrialLiveMetrics?.validAccuracy.append(MetricPoint(epoch: parsed.epoch, value: parsed.validAcc))
            }
            return
        }

        // AUTOML_TRIAL_COMPLETE T value=V valid_acc=A valid_loss=L duration=D
        if line.hasPrefix("AUTOML_TRIAL_COMPLETE") {
            if let parsed = parseTrialCompleteLine(line) {
                let trial = AutoMLTrial(
                    trialNumber: parsed.trialNumber,
                    state: .complete,
                    value: parsed.value,
                    params: [:],  // Params will come from optuna_results.json
                    duration: parsed.duration,
                    bestValidAccuracy: parsed.validAcc,
                    bestValidLoss: parsed.validLoss
                )

                // Update or append
                if let idx = state.liveTrials.firstIndex(where: { $0.trialNumber == parsed.trialNumber }) {
                    state.liveTrials[idx] = trial
                } else {
                    state.liveTrials.append(trial)
                }

                // Update best
                let direction = state.runningStudy?.configuration.optimisationMetric.direction ?? "maximize"
                if direction == "maximize" {
                    if state.liveBestValue == nil || parsed.value > (state.liveBestValue ?? -Double.infinity) {
                        state.liveBestValue = parsed.value
                        state.liveBestTrialNumber = parsed.trialNumber
                    }
                } else {
                    if state.liveBestValue == nil || parsed.value < (state.liveBestValue ?? Double.infinity) {
                        state.liveBestValue = parsed.value
                        state.liveBestTrialNumber = parsed.trialNumber
                    }
                }

                let completedCount = state.liveTrials.filter { $0.state == .complete }.count
                state.runningStatus = .running(trial: completedCount, totalTrials: totalTrials)

                // Reset current trial metrics
                state.currentTrialLiveMetrics = nil
            }
            return
        }

        // AUTOML_PRUNED Trial T pruned at epoch E
        if line.hasPrefix("AUTOML_PRUNED") {
            if let trialNum = extractTrialNumber(from: line) {
                let trial = AutoMLTrial(
                    trialNumber: trialNum,
                    state: .pruned,
                    value: nil,
                    params: [:],
                    duration: nil,
                    bestValidAccuracy: nil,
                    bestValidLoss: nil
                )
                if let idx = state.liveTrials.firstIndex(where: { $0.trialNumber == trialNum }) {
                    state.liveTrials[idx] = trial
                } else {
                    state.liveTrials.append(trial)
                }
                state.currentTrialLiveMetrics = nil
            }
            return
        }

        // AUTOML_COMPLETE best_trial=T best_value=V
        if line.hasPrefix("AUTOML_COMPLETE") {
            // Final completion handled in importResults
            return
        }
    }

    // MARK: - Parsing Helpers

    private struct AutoMLEpochResult {
        let trial: Int
        let epoch: Int
        let totalEpochs: Int
        let trainLoss: Double
        let trainAcc: Double
        let validLoss: Double
        let validAcc: Double
    }

    private static func parseAutoMLEpochLine(_ line: String) -> AutoMLEpochResult? {
        let pattern = #"AUTOML_EPOCH Trial (\d+) Epoch (\d+)/(\d+) \| Train Loss: ([\d.]+) Acc: ([\d.]+) \| Valid Loss: ([\d.]+) Acc: ([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }

        func capture(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: line) else { return nil }
            return String(line[r])
        }

        guard
            let trial = Int(capture(1) ?? ""),
            let epoch = Int(capture(2) ?? ""),
            let totalEpochs = Int(capture(3) ?? ""),
            let trainLoss = Double(capture(4) ?? ""),
            let trainAcc = Double(capture(5) ?? ""),
            let validLoss = Double(capture(6) ?? ""),
            let validAcc = Double(capture(7) ?? "")
        else { return nil }

        return AutoMLEpochResult(trial: trial, epoch: epoch, totalEpochs: totalEpochs,
                                  trainLoss: trainLoss, trainAcc: trainAcc,
                                  validLoss: validLoss, validAcc: validAcc)
    }

    private struct TrialCompleteResult {
        let trialNumber: Int
        let value: Double
        let validAcc: Double
        let validLoss: Double
        let duration: Double
    }

    private static func parseTrialCompleteLine(_ line: String) -> TrialCompleteResult? {
        let pattern = #"AUTOML_TRIAL_COMPLETE (\d+) value=([\d.]+) valid_acc=([\d.]+) valid_loss=([\d.]+) duration=([\d.]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range) else { return nil }

        func capture(_ i: Int) -> String? {
            guard let r = Range(match.range(at: i), in: line) else { return nil }
            return String(line[r])
        }

        guard
            let trialNum = Int(capture(1) ?? ""),
            let value = Double(capture(2) ?? ""),
            let validAcc = Double(capture(3) ?? ""),
            let validLoss = Double(capture(4) ?? ""),
            let duration = Double(capture(5) ?? "")
        else { return nil }

        return TrialCompleteResult(trialNumber: trialNum, value: value,
                                    validAcc: validAcc, validLoss: validLoss, duration: duration)
    }

    private static func extractInt(from line: String, key: String) -> Int? {
        let pattern = "\(key)=(\\d+)"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let r = Range(match.range(at: 1), in: line) else { return nil }
        return Int(line[r])
    }

    private static func extractTrialNumber(from line: String) -> Int? {
        let pattern = #"Trial (\d+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(line.startIndex..<line.endIndex, in: line)
        guard let match = regex.firstMatch(in: line, range: range),
              let r = Range(match.range(at: 1), in: line) else { return nil }
        return Int(line[r])
    }

    // MARK: - Helpers

    private static func buildEnvironment() -> [String: String] {
        var env = ProcessInfo.processInfo.environment
        let existingPath = env["PATH"] ?? "/usr/bin:/bin"
        env["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + existingPath
        env["PYTHONUNBUFFERED"] = "1"
        return env
    }

    private static func handleFailure(error: Error, study: AutoMLStudy, state: AutoMLState) async {
        await MainActor.run {
            state.savePartialResults()
            if (error as NSError).domain == NSCocoaErrorDomain {
                state.runningStatus = .cancelled
                state.appendLog("AutoML search cancelled.")
            } else {
                state.runningStatus = .failed(reason: error.localizedDescription)
            }
            study.status = .configured
            AutoMLStudyStore.saveStudy(study)
        }
    }

    /// Run a process and stream stdout/stderr line by line.
    private static func runProcess(
        executable: String,
        arguments: [String],
        workingDirectory: URL,
        environment: [String: String],
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

    /// Run a simple SSH command and return exit code.
    private static func runSSHCommand(
        sshFlags: [String],
        remoteHost: String,
        command: String,
        state: AutoMLState
    ) async throws -> Int32 {
        try await runProcess(
            executable: "/usr/bin/ssh",
            arguments: sshFlags + [remoteHost, command],
            workingDirectory: FileManager.default.temporaryDirectory,
            environment: ProcessInfo.processInfo.environment,
            onStdoutLine: { _ in },
            onStderrLine: { line in Task { @MainActor in state.appendLog("[ssh] \(line)") } }
        )
    }
}
