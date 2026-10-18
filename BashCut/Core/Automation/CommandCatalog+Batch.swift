import BashCutProject

/// Batch pipelines (P2-C1): the same steps over many inputs, one project per input (decision D4).
extension CommandCatalog {
    static let batchPipelineSummary = "A pipeline is JSON: {name, inputs (paths of media files, folders or projects; "
        + "or {path, kind}), template {canvas, resolution, fps, language, brand, outputs (export presets)}, steps "
        + "[{action, params, label}], onFailure skip|stop, concurrency, outputName ({name}-{preset} by default; "
        + "{name}, {preset}, {index}, {pipeline}), projectsFolder}. Each file becomes a new project from the template "
        + "(its folder linked as footage); a project input is that project. A step's action is a command that runs "
        + "immediately or as a job (never one that needs approval, nor project open/create/close) or a plugin action; "
        + "the export step (action export, params presets, includeSRT, normalizeAudio, bitrate, without) exports each "
        + "preset (else the template outputs). String params may use {input}, {name}, {project} and {media} (the media "
        + "the last step returned). Items run one at a time in the open editor, each project saved after its steps; "
        + "the app must stay open (no headless runs)."

    static let batchSpecs: [CommandSpec] = batchRunSpecs + batchFixSpecs

    private static let batchRunSpecs: [CommandSpec] = [
        CommandSpec(
            "batch.run", .privileged,
            "Run a pipeline over its inputs after the user approves the batch once in the app (that approval covers "
                + "its exports). Returns the batch ID at once (state awaiting_approval or running); follow it with batch "
                + "status --wait. " + batchPipelineSummary,
            parameters: [
                CommandParameter("pipeline", .object, "The pipeline (CLI: path to pipeline.json)", cli: .positionalJSONFile),
                CommandParameter("preset", .string, "A saved pipeline (batch presets) instead of pipeline",
                                 cli: .option("preset")),
                CommandParameter("inputs", .string, "Comma-separated input paths, replacing the pipeline's inputs",
                                 cli: .option("inputs")),
                CommandParameter("base", .string, "Folder that relative input paths resolve against; the CLI sets "
                                 + "it to the pipeline file's folder", isPath: true, cli: .option("base")),
            ] + leaveCurrent,
            execution: .approval),
        CommandSpec(
            "batch.retry", .privileged,
            "Rerun a batch's failed or interrupted items from the step that did not complete. Default: the latest "
                + "batch with failed, cancelled, skipped or interrupted items (a batch BashCut quit during comes back "
                + "interrupted); each item goes on in the project it made, after the user approves once. Returns at once; "
                + "follow it with batch status --wait.",
            parameters: [
                CommandParameter("batch", .string, "Batch ID", cli: .positional),
                CommandParameter("items", .string, "Comma-separated item numbers (from 1) to retry; default all of them",
                                 cli: .option("items")),
            ] + leaveCurrent,
            execution: .approval),
        CommandSpec(
            "batch.status", .read,
            "Read a batch (default: the latest): state, concurrency {asked, used}, counts, elapsedSeconds, "
                + "remainingSeconds (an estimate while it runs), retryable, and per item its input, kind, "
                + "project, state, current step, outputs and steps (action, state, job, error, errorCategory, outputs, "
                + "result). Without batch and with all, every kept batch in short form. With wait, holds until the "
                + "batch or an item changes state or step, or it finishes (changed, timedOut).",
            parameters: [
                CommandParameter("batch", .string, "Batch ID", cli: .positional),
                CommandParameter("all", .boolean, "Every kept batch, short form", default: .bool(false), cli: .flag("all")),
                CommandParameter("wait", .integer, "Seconds to wait for a change, at most \(JobWaitDefaults.maximum)",
                                 minimum: 0, maximum: JobWaitDefaults.maximum, cli: .option("wait")),
            ]),
        CommandSpec(
            "batch.cancel", .edit,
            "Cancel a batch (default: the running one) and the job of its running step; items not run yet end "
                + "cancelled, projects already made stay.",
            parameters: [CommandParameter("batch", .string, "Batch ID", cli: .positional)]),
        CommandSpec(
            "batch.presets", .edit,
            "Saved pipelines in the user store (Application Support/BashCut/Batch/Presets): list them; with pipeline "
                + "save it (name from name, else the pipeline's; inputs are dropped unless keepInputs; a relative "
                + "projectsFolder or input is saved absolute, resolved against base), with get return one, with remove "
                + "delete one.",
            parameters: [
                CommandParameter("pipeline", .object, "Pipeline to save (CLI: path to pipeline.json)",
                                 cli: .positionalJSONFile),
                CommandParameter("name", .string, "Preset name for save", cli: .option("name")),
                CommandParameter("keepInputs", .boolean, "Save the pipeline's inputs too", default: .bool(false),
                                 cli: .flag("keep-inputs")),
                CommandParameter("get", .string, "Preset name to return", cli: .option("get")),
                CommandParameter("remove", .string, "Preset name to delete", cli: .option("remove")),
                CommandParameter("base", .string, "Folder that relative paths (projectsFolder, kept inputs) resolve "
                                 + "against before saving; the CLI sets it to the pipeline file's folder", isPath: true,
                                 cli: .option("base")),
            ]),
    ]
}
