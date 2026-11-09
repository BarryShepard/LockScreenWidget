import Foundation

func loadEventCatalog(_ url: URL) throws -> EventCatalogModel {
    let events = try JSONDecoder().decode([ApocalypseEventModel].self, from: Data(contentsOf: url))
    guard !events.isEmpty, Set(events.map(\.id)).count == events.count,
          events.allSatisfy({ (eventHasCountdown($0) ? parseEventDay($0.date) != nil :
                ($0.countdownEnabled == false && !$0.date.isEmpty && $0.reviewStatus != nil)) &&
              !$0.title.isEmpty && !$0.explanation.isEmpty && !$0.source.isEmpty &&
              $0.sourceURL.scheme == "https" && $0.sourceURL.host != nil }) else {
        throw NSError(domain: "TEotW.Catalog", code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Не удалось проверить даты и источники каталога."])
    }
    let sorted = events.enumerated().sorted {
        if eventHasCountdown($0.element) != eventHasCountdown($1.element) { return eventHasCountdown($0.element) }
        if eventHasCountdown($0.element) { return eventTarget($0.element) < eventTarget($1.element) }
        return $0.offset < $1.offset
    }.map(\.element)
    return EventCatalogModel(events: sorted)
}
