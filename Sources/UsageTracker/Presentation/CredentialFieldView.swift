import AppKit
import SwiftUI

/// What the credential field knows about its Keychain item: the draft being
/// typed and, once saved, the masked ends of the stored value. The full value
/// is never held here.
struct CredentialFieldState: Equatable {
    var draft = ""
    private(set) var mask: CredentialMask?

    init(mask: CredentialMask?) {
        self.mask = mask
    }

    var isSaved: Bool { mask != nil }
    var trimmedDraft: String { draft.trimmingCharacters(in: .whitespacesAndNewlines) }
    var hasSavableChange: Bool { !trimmedDraft.isEmpty }

    mutating func markSaved(mask: CredentialMask?) {
        self.mask = mask
        draft = ""
    }

    mutating func markRemoved() {
        mask = nil
        draft = ""
    }
}

/// A write-only credential input backed by Keychain, or a plain budget field for `api-budget`.
struct CredentialFieldView: View {
    static let commitDelay: Duration = .milliseconds(800)
    nonisolated static let budgetFieldID = "api-budget"

    let field: CredentialField
    let key: CredentialKey
    let store: CredentialStoring
    var onBudgetChange: (Decimal?) -> Void = { _ in }
    var opensHelp = false
    let onChange: () async -> Void

    @State private var state: CredentialFieldState
    @State private var showsHelp: Bool
    @State private var showsCopied = false
    @State private var hasLoaded = false
    @State private var readFailed = false
    @State private var saveFailed = false
    @State private var formatProblem: String?
    @State private var removeFailed = false
    @State private var commitTask: Task<Void, Never>?
    @State private var budget: Decimal?

    init(
        field: CredentialField,
        key: CredentialKey,
        store: CredentialStoring,
        budget: Decimal? = nil,
        onBudgetChange: @escaping (Decimal?) -> Void = { _ in },
        opensHelp: Bool = false,
        onChange: @escaping () async -> Void
    ) {
        self.field = field
        self.key = key
        self.store = store
        self.onBudgetChange = onBudgetChange
        self.opensHelp = opensHelp
        self.onChange = onChange
        _state = State(initialValue: CredentialFieldState(mask: nil))
        _showsHelp = State(initialValue: opensHelp)
        _budget = State(initialValue: budget)
    }

    private var isBudget: Bool { field.id == Self.budgetFieldID }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(field.title)
                    .font(.subheadline.weight(.medium))

                Button {
                    showsHelp.toggle()
                } label: {
                    Image(systemName: "questionmark.circle")
                }
                .buttonStyle(.borderless)
                .help("How do I get this?")
                .accessibilityLabel("How do I get this?")

                Spacer(minLength: 0)

                if !isBudget, state.isSaved {
                    if state.draft.isEmpty {
                        Text("Saved")
                            .font(.caption2.weight(.medium))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Capsule().fill(Color.green.opacity(0.15)))
                    }

                    Button {
                        remove()
                    } label: {
                        Image(systemName: "trash")
                    }
                    .buttonStyle(.borderless)
                    .help("Remove")
                    .accessibilityLabel("Remove")
                }
            }

            if showsHelp {
                helpBox
            }

            if isBudget {
                TextField("0", value: $budget, format: .number)
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: budget) { _, newValue in
                        onBudgetChange(newValue)
                    }
            } else {
                NonCopyableTokenTextField(
                    text: $state.draft, placeholderMask: state.mask,
                    allowsMultipleLines: field.isMultiline, height: fieldHeight
                )
                    .frame(height: fieldHeight)
                    .accessibilityLabel(field.title)
                    .onChange(of: state.draft) {
                        formatProblem = nil
                        scheduleCommit()
                    }
            }

            if readFailed {
                Text("Unable to read credential.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if removeFailed {
                Text("Unable to remove credential.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if saveFailed {
                Text("Unable to save credential.")
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if let formatProblem {
                Text(formatProblem)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
        .onAppear {
            loadSavedState()
        }
        .onChange(of: opensHelp) { _, opens in
            if opens {
                showsHelp = true
            }
        }
        .onDisappear {
            commitTask?.cancel()
            commitTask = nil
            commit()
        }
    }

    private var helpBox: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(field.helpSteps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if field.helpSteps.count > 1 {
                        Text("\(index + 1).")
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }

                    Text(LocalizedStringKey(step))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let chip = field.copyChip {
                copyChipButton(chip)
            }
        }
        .font(.caption)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.primary.opacity(0.04))
        )
    }

    private func copyChipButton(_ chip: String) -> some View {
        HStack(spacing: 8) {
            Button {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(chip, forType: .string)
                showsCopied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    showsCopied = false
                }
            } label: {
                HStack(spacing: 4) {
                    Text(chip)
                        .font(.caption.monospaced())
                    Image(systemName: "doc.on.doc")
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(Capsule().fill(Color.primary.opacity(0.08)))
            }
            .buttonStyle(.plain)
            .help("Copy")
            .accessibilityLabel("Copy \(chip)")

            if showsCopied {
                Label("Copied", systemImage: "checkmark")
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.green)
            }
        }
    }

    /// Seeds once; reads the stored value a single time and keeps only its masked ends.
    private func loadSavedState() {
        guard !hasLoaded else {
            return
        }

        hasLoaded = true

        guard !isBudget else {
            return
        }

        do {
            state = CredentialFieldState(mask: try store.credential(for: key).flatMap(field.format.mask(of:)))
        } catch {
            readFailed = true
        }
    }

    /// Multi-line fields grow so a masked document shows whole.
    private var fieldHeight: CGFloat {
        field.isMultiline ? max(96, NonCopyableTokenTextView.height(fitting: state.mask)) : 26
    }

    private func scheduleCommit() {
        commitTask?.cancel()

        guard state.hasSavableChange else {
            commitTask = nil
            return
        }

        commitTask = Task {
            try? await Task.sleep(for: Self.commitDelay)

            guard !Task.isCancelled else {
                return
            }

            commit()
        }
    }

    private func commit() {
        guard state.hasSavableChange else {
            return
        }

        if let problem = field.format.problem(with: state.trimmedDraft) {
            formatProblem = problem
            return
        }

        do {
            try store.set(state.trimmedDraft, for: key)
        } catch {
            saveFailed = true
            return
        }

        saveFailed = false
        state.markSaved(mask: field.format.mask(of: state.trimmedDraft))
        Task { await onChange() }
    }

    private func remove() {
        commitTask?.cancel()
        commitTask = nil

        do {
            try store.remove(key)
        } catch {
            removeFailed = true
            return
        }

        removeFailed = false
        state.markRemoved()
        Task { await onChange() }
    }
}
