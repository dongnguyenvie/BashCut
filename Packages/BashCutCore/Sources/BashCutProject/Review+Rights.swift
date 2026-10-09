import Foundation

extension TimelineReview {
    /// An info issue when the edit plays AI-made media (P2-H9), with the share of AI picture. Only when the project
    /// turns it on (`review.credits`): by default nothing about rights is reported. What to disclose or credit is the
    /// agent's, from `project credits`.
    static func rightsIssues(_ project: Project, context: ReviewContext) -> [ReviewIssue] {
        guard ReviewProfile(project).credits else { return [] }
        let credits = ProjectCredits.of(project)
        guard !credits.aiMedia.isEmpty else { return [] }
        return [ReviewIssue(
            id: "ai-media", title: "The edit plays AI-made media",
            detail: String(format: "%d AI media; AI picture on top for %.0f%% of the edit.", credits.aiMedia.count,
                           credits.aiPictureShare * 100),
            frame: 0, severity: .info, fix: ReviewFix(command: "project.credits", hint: "project credits lists the facts."))]
    }
}
