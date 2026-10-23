import Foundation
import Observation

/// The creator's view of one split: progress, each person's state, nudges and the shareable link.
@MainActor
@Observable
final class SplitDetailViewModel {
    private(set) var split: SplitDTO
    private(set) var error: AppError?
    /// One line after a nudge or "remind everyone": what happened, or why nothing did.
    private(set) var notice: String?
    private(set) var busyRequestIds: Set<String> = []
    private(set) var isRemindingAll = false
    private(set) var isCancelling = false
    private(set) var isLoading = false
    let justCreated: Bool

    private let api: APIClient

    init(api: APIClient, split: SplitDTO, justCreated: Bool = false) {
        self.api = api
        self.split = split
        self.justCreated = justCreated
    }

    var progress: Double {
        split.shareCount == 0 ? 0 : Double(split.paidCount) / Double(split.shareCount)
    }

    var dueReminderCount: Int {
        split.sharesDueAReminder().count
    }

    var openCount: Int {
        split.shares.filter { $0.status == .pending }.count
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }
        do {
            split = try await api.send(API.split(id: split.id))
            error = nil
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            error = appError
        } catch {
            self.error = .unknown(error.localizedDescription)
        }
    }

    /// Nudge one person. The server allows one per 24 hours per request and says when the next one is possible.
    func nudge(_ share: SplitShareDTO) async {
        guard !busyRequestIds.contains(share.requestId) else { return }
        busyRequestIds.insert(share.requestId)
        defer { busyRequestIds.remove(share.requestId) }
        do {
            _ = try await api.send(API.remindRequest(id: share.requestId))
            notice = "Nudged \(share.firstName). You can nudge again tomorrow."
            await load()
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            notice = appError.userMessage
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }

    /// "Remind everyone unpaid": everyone open who wasn't nudged in the last day.
    func remindAll() async {
        guard !isRemindingAll else { return }
        isRemindingAll = true
        defer { isRemindingAll = false }
        do {
            let result = try await api.send(API.remindSplit(id: split.id))
            split = result.split
            notice = SplitDetailViewModel.summary(of: result, in: result.split)
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            notice = appError.userMessage
        } catch {
            notice = error.localizedDescription
        }
    }

    nonisolated static func summary(of result: SplitReminderResultDTO, in split: SplitDTO) -> String {
        let names = result.reminded.compactMap { id in split.shares.first { $0.requestId == id }?.displayName }
        let tooSoon = result.skipped.filter { $0.reason == "too_soon" }.count
        if names.isEmpty {
            return tooSoon > 0 ? "Everyone unpaid was nudged in the last day. Try again tomorrow." : "Nobody is left to remind."
        }
        var line = "Reminded \(NameList.firstNames(names))."
        if tooSoon > 0 {
            line += tooSoon == 1 ? " 1 person was nudged in the last day." : " \(tooSoon) people were nudged in the last day."
        }
        return line
    }

    /// Withdraws every open request. People who already paid or declined keep their state; a payment someone has
    /// already started at their bank still counts if it goes through.
    func cancelOpenRequests() async {
        guard !isCancelling, openCount > 0 else { return }
        isCancelling = true
        defer { isCancelling = false }
        do {
            let result = try await api.send(API.cancelSplit(id: split.id))
            split = result.split
            let names = result.cancelled.compactMap { id in result.split.shares.first { $0.requestId == id }?.displayName }
            notice = names.isEmpty ? "Nobody had anything left to pay." : "Cancelled. \(NameList.firstNames(names)) can't pay this any more."
        } catch is CancellationError {
            return
        } catch let appError as AppError {
            notice = appError.userMessage
            await load()
        } catch {
            notice = error.localizedDescription
        }
    }

    static let cancelExplanation = "Everyone who hasn't paid yet will see it as cancelled and can't pay it. People who have already paid aren't affected."

    func dismissNotice() {
        notice = nil
    }
}
