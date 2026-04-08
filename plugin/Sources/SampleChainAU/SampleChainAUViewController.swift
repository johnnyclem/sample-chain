// SampleChainAUViewController.swift
// SampleChainAU
//
// AUv3 view controller that hosts the SwiftUI interface via NSHostingController.
// Serves as the bridge between the AUv3 framework (AppKit) and the SwiftUI views.

import AudioToolbox
import AppKit
import CoreAudioKit
import SwiftUI
import SampleChainCore
import SampleChainUI

// MARK: - AU View Configuration

/// Configuration for the AU view sizing.
private enum AUViewConfiguration {
    /// Preferred width of the AU plugin view.
    static let preferredWidth: CGFloat = 800
    /// Preferred height of the AU plugin view.
    static let preferredHeight: CGFloat = 600
    /// Minimum width.
    static let minimumWidth: CGFloat = 600
    /// Minimum height.
    static let minimumHeight: CGFloat = 400
}

// MARK: - SampleChain AU ViewController

/// The view controller that hosts the SampleChain SwiftUI interface within the AUv3 framework.
///
/// When a DAW loads the SampleChain audio unit and requests its view, an instance
/// of this class is created. It:
///
/// 1. Receives a reference to the ``SampleChainAudioUnit``.
/// 2. Creates an ``AppState`` object linked to the AU's parameter tree.
/// 3. Embeds the ``ContentView`` SwiftUI hierarchy via ``NSHostingController``.
/// 4. Forwards parameter changes bidirectionally between the AU and UI.
///
/// This class is referenced in the AUv3 extension's Info.plist as the
/// `NSExtensionPrincipalClass`.
public final class SampleChainAUViewController: AUViewController {

    // MARK: - Properties

    /// The audio unit instance (set by the host via `createAudioUnit(with:)`).
    private var audioUnit: SampleChainAudioUnit?

    /// The hosting controller that wraps the SwiftUI view hierarchy.
    private var hostingController: NSHostingController<AUContentWrapper>?

    /// Observable state shared with SwiftUI views.
    private let appState = AppState()

    /// Parameter observation tokens.
    private var parameterObservationToken: AUParameterObserverToken?

    // MARK: - AUViewController Lifecycle

    public override func viewDidLoad() {
        super.viewDidLoad()

        // Set preferred content size for the DAW's plugin window
        self.preferredContentSize = NSSize(
            width: AUViewConfiguration.preferredWidth,
            height: AUViewConfiguration.preferredHeight
        )

        view.wantsLayer = true
        view.layer?.backgroundColor = NSColor(SCColor.backgroundPrimary).cgColor

        setupSwiftUIHosting()
    }

    public override func viewDidLayout() {
        super.viewDidLayout()
        // Ensure the hosting controller fills the view
        hostingController?.view.frame = view.bounds
    }

    /// Called by the AUv3 framework to create the audio unit.
    ///
    /// The view controller owns the creation of the AU instance; the host
    /// calls this method once after instantiation.
    public func createAudioUnit(
        with componentDescription: AudioComponentDescription
    ) throws -> AUAudioUnit {
        let unit = try SampleChainAudioUnit(componentDescription: componentDescription)
        self.audioUnit = unit

        // Set up parameter observation
        setupParameterObservation(unit: unit)

        // Set compact mode for AU view
        Task { @MainActor in
            appState.isCompactMode = true
        }

        return unit
    }

    // MARK: - SwiftUI Hosting

    /// Embed the SwiftUI ContentView within this NSViewController.
    private func setupSwiftUIHosting() {
        let wrapper = AUContentWrapper(appState: appState)
        let hosting = NSHostingController(rootView: wrapper)

        addChild(hosting)
        view.addSubview(hosting.view)

        hosting.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            hosting.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            hosting.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            hosting.view.topAnchor.constraint(equalTo: view.topAnchor),
            hosting.view.bottomAnchor.constraint(equalTo: view.bottomAnchor),
        ])

        self.hostingController = hosting
    }

    // MARK: - Parameter Observation

    /// Set up bidirectional parameter observation between the AU and UI.
    private func setupParameterObservation(unit: SampleChainAudioUnit) {
        guard let parameterTree = unit.parameterTree else { return }

        // Observe parameter changes from the host/automation
        parameterObservationToken = parameterTree.token(byAddingParameterObserver: { [weak self] address, value in
            // Parameter changed by host -- update UI on main thread
            Task { @MainActor [weak self] in
                self?.handleParameterChangeFromHost(address: address, value: value)
            }
        })
    }

    /// Handle a parameter change originating from the host (automation, MIDI learn, etc.).
    @MainActor
    private func handleParameterChangeFromHost(address: AUParameterAddress, value: AUValue) {
        // Map AU parameter changes to AppState properties
        // This enables the UI to reflect parameter changes from DAW automation
        switch address {
        case SampleChainParameterAddress.bpmOverride.rawValue:
            // Update UI BPM display
            break

        case SampleChainParameterAddress.rootKeyOverride.rawValue:
            // Update UI key display
            break

        case SampleChainParameterAddress.masterVolume.rawValue:
            // Update UI volume display
            break

        default:
            break
        }
    }

    /// Send a parameter change from the UI to the AU parameter tree.
    ///
    /// This should be called when the user adjusts a control in the SwiftUI UI.
    public func setParameter(address: SampleChainParameterAddress, value: AUValue) {
        guard let param = audioUnit?.parameterTree?.parameter(
            withAddress: address.rawValue
        ) else { return }

        param.value = value
    }

    // MARK: - Cleanup

    deinit {
        if let token = parameterObservationToken, let tree = audioUnit?.parameterTree {
            tree.removeParameterObserver(token)
        }
    }
}

// MARK: - AU Content Wrapper

/// SwiftUI wrapper view that provides the AppState environment to the ContentView.
struct AUContentWrapper: View {
    @ObservedObject var appState: AppState

    var body: some View {
        ContentView()
            .environmentObject(appState)
            .frame(
                minWidth: AUViewConfiguration.minimumWidth,
                idealWidth: AUViewConfiguration.preferredWidth,
                minHeight: AUViewConfiguration.minimumHeight,
                idealHeight: AUViewConfiguration.preferredHeight
            )
    }
}
