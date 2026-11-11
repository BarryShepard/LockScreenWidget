import Foundation

struct ApocalypseEventModel: Codable {
    let id: String
    let date: String
    let title: String
    let explanation: String
    let source: String
    let sourceURL: URL
    let dateLabel: String?
    let countdownEnabled: Bool?
    let reviewStatus: String?
    let reviewNote: String?
    let caveat: String?
    let researchTitle: String?
    let researchNumber: Int?
}
