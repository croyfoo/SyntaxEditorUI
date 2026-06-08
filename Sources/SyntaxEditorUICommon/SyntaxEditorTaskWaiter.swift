package func syntaxEditorWaitForTaskCompletionForTesting(
    _ task: Task<Void, Never>,
    timeoutNanoseconds: UInt64,
    onTimeout: @escaping @Sendable () -> Void
) async -> Bool {
    await withCheckedContinuation { continuation in
        let state = SyntaxEditorTaskWaiterState(continuation: continuation)
        let completionTask = Task {
            await task.value
            _ = await state.resume(returning: true)
        }
        let timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: timeoutNanoseconds)
            } catch {
                return
            }
            let didResume = await state.resume(returning: false)
            if didResume {
                onTimeout()
            }
        }

        Task {
            await state.setTasks(
                completionTask: completionTask,
                timeoutTask: timeoutTask
            )
        }
    }
}

private actor SyntaxEditorTaskWaiterState {
    var continuation: CheckedContinuation<Bool, Never>?
    var completionTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?

    init(continuation: CheckedContinuation<Bool, Never>) {
        self.continuation = continuation
    }

    func setTasks(
        completionTask: Task<Void, Never>,
        timeoutTask: Task<Void, Never>
    ) {
        guard continuation != nil else {
            completionTask.cancel()
            timeoutTask.cancel()
            return
        }

        self.completionTask = completionTask
        self.timeoutTask = timeoutTask
    }

    func resume(returning result: Bool) -> Bool {
        guard let continuation else { return false }

        self.continuation = nil
        completionTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(returning: result)
        return true
    }
}
