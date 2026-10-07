import Foundation

extension TimelineReview {
    /// Info issues from the edit's credits (P2-H9): AI media to disclose (with each output platform's rule and the
    /// share of AI picture), credit lines a licence requires, and media whose rights are unclear or restricted. Only
    /// when the project turns it on (`review.credits`): by default nothing about licences is reported.
    static func rightsIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard ReviewProfile(project).credits else { return [] }
        let credits = ProjectCredits.of(project, platforms: context.targets.platforms)
        var issues: [ReviewIssue] = []
        let fix = ReviewFix(command: "project.credits", hint: "project credits lists the lines, disclosures and flags.")
        if !credits.aiMedia.isEmpty {
            let rules = credits.disclosures.map { "\($0.platform): \($0.rule)" }
            issues.append(ReviewIssue(
                id: "ai-disclosure", title: "The edit uses AI-made media",
                detail: String(format: "%d AI media; AI picture on top for %.0f%% of the edit.", credits.aiMedia.count,
                               credits.aiPictureShare * 100)
                    + (rules.isEmpty ? " No output platform with a disclosure rule is set." : " " + rules.joined(separator: " ")),
                frame: 0, severity: .info, fix: fix))
        }
        let required = credits.lines.filter(\.required)
        if !required.isEmpty {
            issues.append(ReviewIssue(
                id: "credits-required", title: "Licences ask for credit",
                detail: "\(required.count) credit line(s) to put in the description: "
                    + required.map(\.text).joined(separator: "; "),
                frame: 0, severity: .info, fix: fix))
        }
        let flagged = [("non-commercial licence", credits.nonCommercial), ("all rights reserved", credits.allRightsReserved),
                       ("licence unknown", credits.unknown)].filter { !$0.1.isEmpty }
        if !flagged.isEmpty {
            issues.append(ReviewIssue(
                id: "rights-unclear", title: "Some media may not be yours to publish",
                detail: flagged.map { "\($0.0): \($0.1.joined(separator: ", "))" }.joined(separator: "; ") + ".",
                frame: 0, severity: .info,
                fix: ReviewFix(command: "media.import", hint: "Record each file's licence (media import --license …), "
                               + "or replace what cannot be used.")))
        }
        return issues
    }
}
