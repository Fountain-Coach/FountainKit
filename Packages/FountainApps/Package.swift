// swift-tools-version: 6.1
import PackageDescription
import Foundation

let ROBOT_ONLY = ProcessInfo.processInfo.environment["ROBOT_ONLY"] == "1" || ProcessInfo.processInfo.environment["FK_ROBOT_ONLY"] == "1"

let USE_SDLKIT = ProcessInfo.processInfo.environment["FK_USE_SDLKIT"] == "1"

let FK_DISABLE_QFCELLS = ProcessInfo.processInfo.environment["FK_DISABLE_QFCELLS"] == "1"
let FK_SKIP_NOISY = ProcessInfo.processInfo.environment["FK_SKIP_NOISY_TARGETS"] == "1" || ProcessInfo.processInfo.environment["FK_EDITOR_MINIMAL"] == "1"

let EDITOR_MINIMAL = ProcessInfo.processInfo.environment["FK_EDITOR_MINIMAL"] == "1" || ProcessInfo.processInfo.environment["FK_SKIP_NOISY_TARGETS"] == "1"
let EDITOR_VRT_ONLY = ProcessInfo.processInfo.environment["FK_EDITOR_VRT_ONLY"] == "1"
let BLANK_VRT_ONLY = ProcessInfo.processInfo.environment["FK_BLANK_VRT_ONLY"] == "1"

// Products list with optional minimal gating for editor-only scenarios
let PRODUCTS: [Product] = BLANK_VRT_ONLY ? [
    .executable(name: "blank-page-app", targets: ["blank-page-app"])
] : (EDITOR_VRT_ONLY ? [
    .executable(name: "quietframe-editor-app", targets: ["quietframe-editor-app"]),
    .executable(name: "editor-snapshots", targets: ["editor-snapshots"])
] : (EDITOR_MINIMAL ? [
    .executable(name: "fountain-editor-service-server", targets: ["fountain-editor-service-server"]),
    .library(name: "FountainEditorCoreKit", targets: ["fountain-editor-service-core"]),
    .executable(name: "service-minimal-seed", targets: ["service-minimal-seed"])
] : (ROBOT_ONLY ? [
        // Robot-only: expose just what PatchBay tests need
        .executable(name: "patchbay-app", targets: ["patchbay-app"]),
        .executable(name: "replay-export", targets: ["replay-export"]),
        .executable(name: "midi-instrument-host", targets: ["midi-instrument-host"]),
        .library(name: "MetalViewKit", targets: ["MetalViewKit"]) ,
        .library(name: "FountainEditorCoreKit", targets: ["fountain-editor-service-core"]) ,
        .executable(name: "metalviewkit-cc-fuzz", targets: ["metalviewkit-cc-fuzz"]) 
        
    ] : [
        .executable(name: "gateway-server", targets: ["gateway-server"]),
        .executable(name: "instrument-catalog-server", targets: ["instrument-catalog-server"]),
        .executable(name: "store-apply-seed", targets: ["store-apply-seed"]),
        .executable(name: "mpe-pad-app-seed", targets: ["mpe-pad-app-seed"]),
        .executable(name: "agent-host", targets: ["midi-instrument-host"]),
        .executable(name: "gateway-ci-smoke", targets: ["gateway-ci-smoke"]),
        .executable(name: "secrets-seed", targets: ["secrets-seed"]),
        .executable(name: "facts-validate", targets: ["facts-validate"]),
        .executable(name: "tools-factory-server", targets: ["tools-factory-server"]),
        .executable(name: "tool-server", targets: ["tool-server"]),
        .executable(name: "agent-validate", targets: ["agent-validate"]),
        .executable(name: "agent-descriptor-seed", targets: ["agent-descriptor-seed"]),
        .executable(name: "planner-server", targets: ["planner-server"]),
        .executable(name: "function-caller-server", targets: ["function-caller-server"]),
        .executable(name: "persist-server", targets: ["persist-server"]),
        .executable(name: "baseline-awareness-server", targets: ["baseline-awareness-server"]),
        .executable(name: "bootstrap-server", targets: ["bootstrap-server"]),
        .executable(name: "publishing-frontend", targets: ["publishing-frontend"]),
        .executable(name: "quietframe-service-server", targets: ["quietframe-service-server"]),
        .executable(name: "tutor-dashboard", targets: ["tutor-dashboard"]),
        .executable(name: "pbvrt-server", targets: ["pbvrt-server"]),
        // removed: add-instruments-seed (context menu removed from baseline)
        .executable(name: "store-dump", targets: ["store-dump"]),
        .executable(name: "service-minimal-seed", targets: ["service-minimal-seed"]),
        .executable(name: "FountainLauncherUI", targets: ["FountainLauncherUI"]),
        .executable(name: "local-agent-manager", targets: ["local-agent-manager"]),
        .executable(name: "mock-localagent-server", targets: ["mock-localagent-server"]),
        .executable(name: "audiotalk-server", targets: ["audiotalk-server"])
        ,
        .executable(name: "pbvrt-embed-ci", targets: ["pbvrt-embed-ci"]),
        .executable(name: "pbvrt-rig-seed", targets: ["pbvrt-rig-seed"]),
        .executable(name: "pbvrt-clip-seed", targets: ["pbvrt-clip-seed"]),
        .executable(name: "pbvrt-quietframe-seed", targets: ["pbvrt-quietframe-seed"]),
        .executable(name: "pbvrt-quietframe-dump", targets: ["pbvrt-quietframe-dump"]),
        .executable(name: "pbvrt-quietframe-proof", targets: ["pbvrt-quietframe-proof"]),
        .executable(name: "pbvrt-tone", targets: ["pbvrt-tone"]),
        .executable(name: "pbvrt-present", targets: ["pbvrt-present"]),
        .executable(name: "engraver-studio-app", targets: ["engraver-studio-app"]),
        .executable(name: "sysx-json-sender", targets: ["sysx-json-sender"]),
        .executable(name: "sysx-json-receiver", targets: ["sysx-json-receiver"]),
        .executable(name: "gateway-console", targets: ["gateway-console"]),
        .executable(name: "gateway-console-app", targets: ["gateway-console-app"]),
        .executable(name: "engraver-chat-tui", targets: ["engraver-chat-tui"]),
        .executable(name: "audiotalk-cli", targets: ["audiotalk-cli"]),
        .executable(name: "audiotalk-ci-smoke", targets: ["audiotalk-ci-smoke"]),
        .executable(name: "m2-smoke", targets: ["m2-smoke"]),
        .executable(name: "engraving-app", targets: ["engraving-app"]),
        .executable(name: "memchat-app", targets: ["memchat-app"]),
        .executable(name: "memchat-teatro", targets: ["memchat-teatro"]),
        .executable(name: "engraving-demo-seed", targets: ["engraving-demo-seed"]),
        .executable(name: "memchat-concept-seed", targets: ["memchat-concept-seed"]),
        .executable(name: "memchat-save-reply", targets: ["memchat-save-reply"]),
        .executable(name: "memchat-save-continuity", targets: ["memchat-save-continuity"]),
        .executable(name: "memchat-save-plan", targets: ["memchat-save-plan"]),
        .executable(name: "llm-doctor", targets: ["llm-doctor"]),
        .executable(name: "engraver-direct", targets: ["engraver-direct"]),
        .library(name: "EngraverChatCore", targets: ["EngraverChatCore"]),
        .library(name: "EngraverStudio", targets: ["EngraverStudio"]),
        .library(name: "MetalViewKit", targets: ["MetalViewKit"]),
        .library(name: "FountainEditorCoreKit", targets: ["fountain-editor-service-core"]),
        .executable(name: "metalviewkit-cc-fuzz", targets: ["metalviewkit-cc-fuzz"]),
        .library(name: "MetalComputeKit", targets: ["MetalComputeKit"]),
        .library(name: "CoreMLKit", targets: ["CoreMLKit"]),
        .executable(name: "metalcompute-demo", targets: ["metalcompute-demo"]),
        .executable(name: "metalcompute-tests", targets: ["metalcompute-tests"]),
        .executable(name: "coreml-demo", targets: ["coreml-demo"]),
        .executable(name: "coreml-fetch", targets: ["coreml-fetch"]),
        .executable(name: "ml-audio2midi", targets: ["ml-audio2midi"]),
        .executable(name: "ml-basicpitch2midi", targets: ["ml-basicpitch2midi"]),
        .executable(name: "ml-yamnet2midi", targets: ["ml-yamnet2midi"]),
        .executable(name: "ml-sampler-smoke", targets: ["ml-sampler-smoke"]),
        .executable(name: "metalview-demo-app", targets: ["metalview-demo-app"]),
        .executable(name: "fk", targets: ["fk"])
        ,
        .executable(name: "composer-studio", targets: ["composer-studio"]),
        .executable(name: "composer-studio-seed", targets: ["composer-studio-seed"]),
        .executable(name: "qc-mock-app", targets: ["qc-mock-app"]),
        .executable(name: "qcmockcore-tests", targets: ["qcmockcore-tests"]),
        .executable(name: "patchbay-service-server", targets: ["patchbay-service-server"]),
        .executable(name: "patchbay-app", targets: ["patchbay-app"]),
        .executable(name: "replay-export", targets: ["replay-export"]),
        // Baseline app alias for PatchBay UI (default starting point for FountainAI apps)
        .executable(name: "baseline-patchbay", targets: ["grid-dev-app"]),
        .executable(name: "grid-dev-app", targets: ["grid-dev-app"]),
        .executable(name: "grid-dev-seed", targets: ["grid-dev-seed"])
        ,
        .executable(name: "mpe-pad-app", targets: ["mpe-pad-app"])
        ,
        .executable(name: "baseline-robot-seed", targets: ["baseline-robot-seed"])
        ,
        .executable(name: "flow-instrument-seed", targets: ["flow-instrument-seed"]),
        .executable(name: "llm-adapter-seed", targets: ["llm-adapter-seed"]),
        .executable(name: "baseline-editor-seed", targets: ["baseline-editor-seed"]),
        .executable(name: "patchbay-graph-seed", targets: ["patchbay-graph-seed"]),
        .executable(name: "patchbay-test-scene-seed", targets: ["patchbay-test-scene-seed"])
        ,
        .executable(name: "patchbay-docs-seed", targets: ["patchbay-docs-seed"])
        ,
        .executable(name: "patchbay-saliency-seed", targets: ["patchbay-saliency-seed"])
        ,
        .executable(name: "quietframe-sonify-app", targets: ["quietframe-sonify-app"]),
        .executable(name: "quietframe-cc-mapping-seed", targets: ["quietframe-cc-mapping-seed"]),
        .executable(name: "quietframe-orchestra-seed", targets: ["quietframe-orchestra-seed"]),
        .executable(name: "quietframe-orchestra-generate", targets: ["quietframe-orchestra-generate"]),
        .executable(name: "die-maschine-teatro-seed", targets: ["die-maschine-teatro-seed"]),
        .executable(name: "die-maschine-scenes-assign", targets: ["die-maschine-scenes-assign"]),
        .executable(name: "fountain-editor-seed", targets: ["fountain-editor-seed"]),
        .executable(name: "quietframe-companion-app", targets: ["quietframe-companion-app"]),
        // removed: quietframe-smoke (CoreMIDI)
        .executable(name: "metalviewkit-runtime-server", targets: ["metalviewkit-runtime-server"]),
        .executable(name: "fountain-gui-demo-app", targets: ["fountain-gui-demo-app"])
        
    ])))

// Dependencies list with minimal mode avoiding heavy stacks
let DEPENDENCIES: [Package.Dependency] = BLANK_VRT_ONLY ? [
    // no external deps
] : (EDITOR_VRT_ONLY ? [
    .package(path: "../FountainCore")
] : (EDITOR_MINIMAL ? [
    .package(path: "../FountainCore"),
    .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
    .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0")
] : [
        .package(path: "../FountainCore"),
        .package(path: "../FountainAIKit"),
        .package(path: "../FountainProviders"),
        .package(path: "../../Tools/fountain-editor-mini-tests"),
        // SDLKit (optional, only when FK_USE_SDLKIT=1)
    ] + (USE_SDLKIT ? [
        .package(url: "https://github.com/Fountain-Coach/SDLKit.git", branch: "main")
    ] : []) + [
        .package(path: "../MemChatKit"),
        .package(path: "../FountainDevHarness"),
        .package(path: "../FountainAPIClients"),
        .package(path: "../FountainGatewayKit"),
        .package(path: "../FountainServiceKit-Planner"),
        .package(path: "../FountainServiceKit-FunctionCaller"),
        .package(path: "../FountainServiceKit-Bootstrap"),
        .package(path: "../FountainServiceKit-Awareness"),
        .package(path: "../FountainServiceKit-Persist"),
        .package(path: "../FountainServiceKit-AudioTalk"),
        .package(path: "../FountainServiceKit-MIDI"),
        .package(url: "https://github.com/Fountain-Coach/FountainGUIKit.git", from: "0.2.0"),
        .package(path: "../FountainServiceKit-ToolsFactory"),
        .package(path: "../FountainServiceKit-ToolServer"),
        .package(path: "../FountainServiceKit-FKOps"),
        .package(path: "../FountainTooling"),
        // Removed unused swift-nio-extras to eliminate warnings in host-only builds
        // External UI graph editor used by PatchBay
        .package(url: "https://github.com/AudioKit/Flow.git", from: "1.0.4"),
        .package(path: "../FountainTelemetryKit"),
        .package(path: "../../Tools/PersistenceSeeder"),
        // Teatro (path-based until repo splits subpackages for URL consumption)
        .package(path: "../../External/TeatroFull"),
    ] + [
        
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", from: "3.0.0"),
        .package(url: "https://github.com/apple/swift-certificates.git", from: "1.0.0"),
        .package(url: "https://github.com/Fountain-Coach/swiftcurseskit.git", exact: "0.2.0"),
        .package(url: "https://github.com/Fountain-Coach/swift-secretstore.git", exact: "0.1.0"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-openapi-runtime.git", from: "1.4.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession.git", from: "1.0.0"),
        // MIDI 2.0 + MIDI-CI helpers (Discovery, Property Exchange)
        .package(url: "https://github.com/Fountain-Coach/midi2.git", from: "0.3.1"),
        // MIDI2 Instrument Bridge (sampler) — pin to released tag
        .package(url: "https://github.com/Fountain-Coach/midi2sampler.git", exact: "0.1.1")
    ]
))
    
// Targets list; in minimal mode, only editor core + server
let TARGETS: [Target] = BLANK_VRT_ONLY ? [
    .executableTarget(
        name: "blank-page-app",
        dependencies: [
        ],
        path: "Sources/blank-page-app"
    ),
    .executableTarget(
        name: "midi-instrument-host",
        dependencies: [
            .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
            .product(name: "FountainStoreClient", package: "FountainCore"),
            .product(name: "MIDI2CI", package: "midi2"),
            .product(name: "MIDI2", package: "midi2")
        ],
        path: "Sources/midi-instrument-host"
    ),
    .testTarget(
        name: "BlankAppUITests",
        dependencies: [
            "blank-page-app"
        ],
        path: "Tests/BlankAppUITests",
        resources: [
            .process("Baselines")
        ]
    )
] : (EDITOR_VRT_ONLY ? [
    .executableTarget(
        name: "quietframe-editor-app",
        dependencies: [
            .product(name: "FountainStoreClient", package: "FountainCore")
        ],
        path: "Sources/quietframe-editor-app"
    ),
    .executableTarget(
        name: "editor-snapshots",
        dependencies: [
            "quietframe-editor-app"
        ],
        path: "Sources/editor-snapshots"
    ),
    .executableTarget(
        name: "midi-instrument-host",
        dependencies: [
            .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
            .product(name: "FountainStoreClient", package: "FountainCore"),
            .product(name: "MIDI2CI", package: "midi2"),
            .product(name: "MIDI2", package: "midi2")
        ],
        path: "Sources/midi-instrument-host"
    ),
    .testTarget(
        name: "EditorAppUITests",
        dependencies: [
            "quietframe-editor-app"
        ],
        path: "Tests/EditorAppUITests",
        resources: [
            .process("Baselines")
        ]
    ),
    .testTarget(
        name: "QuietFrameEditorUITests",
        dependencies: [
            "quietframe-sonify-app"
        ],
        path: "Tests/QuietFrameEditorUITests",
        resources: [
            .process("Baselines")
        ]
    )
] : (EDITOR_MINIMAL ? [
    .target(
        name: "fountain-editor-service-core",
        dependencies: [
            .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
            .product(name: "FountainStoreClient", package: "FountainCore")
        ],
        path: "Sources/fountain-editor-service",
        plugins: [
            .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
        ]
    ),
    .executableTarget(
        name: "fountain-editor-service-server",
        dependencies: [
            "fountain-editor-service-core",
            .product(name: "FountainRuntime", package: "FountainCore"),
            .product(name: "LauncherSignature", package: "FountainCore")
        ],
        path: "Sources/fountain-editor-service-server"
    ),
    .executableTarget(
        name: "service-minimal-seed",
        dependencies: [
            .product(name: "FountainStoreClient", package: "FountainCore")
        ],
        path: "Sources/service-minimal-seed"
    ),
    .executableTarget(
        name: "midi-instrument-host",
        dependencies: [
            .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
            .product(name: "FountainStoreClient", package: "FountainCore"),
            .product(name: "MIDI2CI", package: "midi2"),
            .product(name: "MIDI2", package: "midi2")
        ],
        path: "Sources/midi-instrument-host"
    )
] : (ROBOT_ONLY ? [
        .target(
            name: "MetalViewKit",
            dependencies: [
                .product(name: "MIDI2CI", package: "midi2"),
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/MetalViewKit",
            exclude: ["AGENTS.md"]
        ),
        .executableTarget(
            name: "secrets-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/secrets-seed"
        ),
        .executableTarget(
            name: "agent-pe-bridge",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/agent-pe-bridge"
        ),
        .executableTarget(
            name: "facts-validate",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/facts-validate"
        ),
        .executableTarget(
            name: "planner-pe-bridge",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/planner-pe-bridge"
        ),
        .executableTarget(
            name: "function-caller-pe-bridge",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/function-caller-pe-bridge"
        ),
        .executableTarget(
            name: "persist-pe-bridge",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/persist-pe-bridge"
        ),
    .executableTarget(
        name: "midi-instrument-host",
        dependencies: [
            .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
            .product(name: "FountainStoreClient", package: "FountainCore")
        ],
        path: "Sources/midi-instrument-host"
    ),
        .executableTarget(
            name: "sysx-json-sender",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/sysx-json-sender"
        ),
        .executableTarget(
            name: "sysx-json-receiver",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/sysx-json-receiver"
        ),
    .executableTarget(
        name: "midi-instrument-host",
        dependencies: [
            .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
            .product(name: "FountainStoreClient", package: "FountainCore")
        ],
        path: "Sources/midi-instrument-host",
        resources: [ .process("Resources") ]
    ),
        .executableTarget(
            name: "facts-validate",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/facts-validate"
        ),
        
        .target(
            name: "gateway-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            path: "Sources/gateway-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        
        .target(
            name: "CoreMLKit",
            dependencies: [],
            path: "Sources/CoreMLKit",
            exclude: ["AGENTS.md"]
        ),
        .executableTarget(
            name: "patchbay-docs-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/patchbay-docs-seed"
        ),
        .executableTarget(
            name: "pbvrt-rig-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-rig-seed"
        ),
        .executableTarget(
            name: "pbvrt-clip-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-clip-seed"
        ),
        .executableTarget(
            name: "pbvrt-quietframe-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-quietframe-seed"
        ),
        
        .executableTarget(
            name: "pbvrt-quietframe-dump",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-quietframe-dump"
        ),
        .executableTarget(
            name: "pbvrt-quietframe-proof",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-quietframe-proof"
        ),
        .executableTarget(
            name: "pbvrt-tone",
            dependencies: [],
            path: "Sources/pbvrt-tone"
        ),
        .executableTarget(
            name: "pbvrt-present",
            dependencies: [],
            path: "Sources/pbvrt-present"
        ),
        
        .executableTarget(
            name: "flow-instrument-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/flow-instrument-seed"
        ),
        .executableTarget(
            name: "llm-adapter-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/llm-adapter-seed"
        ),
        .executableTarget(
            name: "patchbay-graph-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/patchbay-graph-seed"
        ),
        .executableTarget(
            name: "patchbay-test-scene-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore"),
            ],
            path: "Sources/patchbay-test-scene-seed"
        ),
        .executableTarget(
            name: "patchbay-saliency-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/patchbay-saliency-seed"
        ),
        .executableTarget(
            name: "mpe-pad-app-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/mpe-pad-app-seed"
        ),
        .executableTarget(
            name: "fountain-gui-demo-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/fountain-gui-demo-seed"
        ),
        .executableTarget(
            name: "baseline-editor-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/baseline-editor-seed"
        ),
        .executableTarget(
            name: "patchbay-app",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "Flow", package: "Flow"),
                "MetalViewKit",
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "ProviderLocalLLM", package: "FountainProviders"),
                .product(name: "LLMGatewayAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "TutorDashboard", package: "FountainAPIClients"),
                .product(name: "TeatroRenderAPI", package: "TeatroFull")
            ],
            path: "Sources/patchbay-app",
            exclude: ["AGENTS.md"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .testTarget(
            name: "MPEPadAppTests",
            dependencies: ["mpe-pad-app"],
            path: "Tests/MPEPadAppTests"
        ),
        .testTarget(
            name: "PBVRTServerTests",
            dependencies: [
                "pbvrt-server",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Tests/PBVRTServerTests"
        ),
        .executableTarget(
            name: "replay-export",
            dependencies: ["MetalViewKit"],
            path: "Sources/replay-export"
        ),
        // QuietFrameCells (migrated into app via shim; target removed to avoid manifest hiccups)
        .target(
            name: "QuietFrameKit",
            dependencies: [
                .product(name: "MIDI2CI", package: "midi2"),
                .product(name: "MIDI2", package: "midi2")
            ],
            path: "Sources/QuietFrameKit"
        ),
        .testTarget(
            name: "QuietFrameKitTests",
            dependencies: [
                "QuietFrameKit",
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Tests/QuietFrameKitTests"
        ),
        .testTarget(
            name: "MetalInstrumentSysExTests",
            dependencies: [
                "MetalViewKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Tests/MetalInstrumentSysExTests"
        ),
        .testTarget(
            name: "MetalInstrumentRTPTests",
            dependencies: [
                "MetalViewKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Tests/MetalInstrumentRTPTests"
        ),
        .testTarget(
            name: "MetalInstrumentCoreMIDITests",
            dependencies: ["MetalViewKit"],
            path: "Tests/MetalInstrumentCoreMIDITests"
        ),
        // Audio engine (for focused builds with ROBOT_ONLY)
        .target(
            name: "FountainAudioEngine",
            dependencies: [
                .product(name: "SDLKitAudio", package: "SDLKit")
            ],
            path: "Sources/FountainAudioEngine"
        ),
        .testTarget(
            name: "ComposerScoreServiceTests",
            dependencies: [
                "composer-score-service"
            ],
            path: "Tests/ComposerScoreServiceTests"
        ),
        .testTarget(
            name: "ComposerScriptServiceTests",
            dependencies: [
                "composer-script-service"
            ],
            path: "Tests/ComposerScriptServiceTests"
        ),
        .testTarget(
            name: "ComposerCuesServiceTests",
            dependencies: [
                "composer-cues-service"
            ],
            path: "Tests/ComposerCuesServiceTests"
        )
    ] : [
        .target(
            name: "QCMockCore",
            dependencies: [],
            path: "Sources/QCMockCore"
        ),
        .executableTarget(
            name: "facts-validate",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/facts-validate"
        ),
        .target(
            name: "QCMockServiceCore",
            dependencies: ["QCMockCore"],
            path: "Sources/QCMockServiceCore"
        ),
        // Service cores owning OpenAPI generation
        .target(
            name: "gateway-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime")
            ],
            path: "Sources/gateway-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "pbvrt-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "gateway-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                "gateway-service",
                .product(name: "PublishingFrontend", package: "FountainGatewayKit"),
                .product(name: "LLMGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "PolicyGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "AuthGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "CuratorGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "RateLimiterGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "BudgetBreakerGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "PayloadInspectionGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "DestructiveGuardianGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "RoleHealthCheckGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "SecuritySentinelGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "ChatKitGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "GatewayPersonaOrchestrator", package: "FountainGatewayKit"),
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
                "Yams"
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "midi-service-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "MIDIService", package: "FountainServiceKit-MIDI")
            ],
            path: "Sources/midi-service-server"
        ),
        .executableTarget(
            name: "planner-pe-bridge",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/planner-pe-bridge"
        ),
        .executableTarget(
            name: "function-caller-pe-bridge",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/function-caller-pe-bridge"
        ),
        .executableTarget(
            name: "persist-pe-bridge",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/persist-pe-bridge"
        ),
        .executableTarget(
            name: "ml-sampler-smoke",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ml-sampler-smoke"
        ),
        .executableTarget(
            name: "ml-audio2midi",
            dependencies: [
                "CoreMLKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Midi2SamplerDSP", package: "midi2sampler")
            ],
            path: "Sources/ml-audio2midi"
        ),
        .executableTarget(
            name: "ml-basicpitch2midi",
            dependencies: [
                "CoreMLKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                .product(name: "Midi2SamplerDSP", package: "midi2sampler")
            ],
            path: "Sources/ml-basicpitch2midi"
        ),
        .executableTarget(
            name: "ml-yamnet2midi",
            dependencies: [
                "CoreMLKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/ml-yamnet2midi"
        ),
        .executableTarget(
            name: "agent-validate",
            dependencies: [
                "Yams",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/agent-validate"
        ),
        .executableTarget(
            name: "agent-descriptor-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                "Yams",
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/agent-descriptor-seed"
        ),
        .executableTarget(
            name: "metalcompute-demo",
            dependencies: ["MetalComputeKit"],
            path: "Sources/metalcompute-demo"
        ),
        .executableTarget(
            name: "metalcompute-tests",
            dependencies: ["MetalComputeKit"],
            path: "Sources/metalcompute-tests"
        ),
        .executableTarget(
            name: "fountain-gui-demo-app",
            dependencies: [
                .product(name: "FountainGUIKit", package: "FountainGUIKit")
            ],
            path: "Sources/fountain-gui-demo"
        ),
        .executableTarget(
            name: "coreml-demo",
            dependencies: ["CoreMLKit"],
            path: "Sources/coreml-demo"
        ),
        .executableTarget(
            name: "coreml-fetch",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            path: "Sources/coreml-fetch"
        ),
        .testTarget(
            name: "FountainGUIDemoTests",
            dependencies: [
                "fountain-gui-demo-app",
                .product(name: "FountainGUIKit", package: "FountainGUIKit")
            ],
            path: "Tests/FountainGUIDemoTests"
        ),
        .target(
            name: "MetalViewKit",
            dependencies: [
                .product(name: "MIDI2CI", package: "midi2"),
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/MetalViewKit",
            exclude: ["AGENTS.md"]
        ),
        .target(
            name: "MetalComputeKit",
            dependencies: [],
            path: "Sources/MetalComputeKit",
            exclude: ["AGENTS.md"]
        ),
        .target(
            name: "CoreMLKit",
            dependencies: [],
            path: "Sources/CoreMLKit",
            exclude: ["AGENTS.md"]
        ),
        .executableTarget(
            name: "composer-studio-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/composer-studio-seed"
        ),
        .executableTarget(
            name: "composer-studio",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                "composer-score-service",
                "composer-script-service",
                "composer-cues-service"
            ],
            path: "Sources/composer-studio",
            exclude: ["AGENTS.md"]
        ),
        .target(
            name: "composer-score-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/composer-score-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "composer-script-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/composer-script-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "composer-cues-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/composer-cues-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "qc-mock-app",
            dependencies: [
                "QCMockCore",
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/qc-mock-app",
            exclude: ["AGENTS.md"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "patchbay-app",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "Flow", package: "Flow"),
                // Pivot: use MetalViewKit for canvas rendering; keep Flow only for legacy EditorCanvas in tests
                "MetalViewKit",
                .product(name: "ProviderLocalLLM", package: "FountainProviders"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "LLMGatewayAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "TutorDashboard", package: "FountainAPIClients"),
                .product(name: "TeatroRenderAPI", package: "TeatroFull")
                // ScoreKit and RulesKit are available in the workspace; we will gradually adopt them in PatchBay.
                // .product(name: "ScoreKit", package: "ScoreKit"),
                // .product(name: "RulesKit", package: "RulesKit-SPM")
            ],
            path: "Sources/patchbay-app",
            exclude: ["AGENTS.md"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "qc-mock-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                "QCMockServiceCore"
            ],
            path: "Sources/qc-mock-service",
            exclude: ["AGENTS.md"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "patchbay-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/patchbay-service",
            exclude: ["AGENTS.md"],
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "patchbay-service-server",
            dependencies: [
                "patchbay-service",
                .product(name: "FountainRuntime", package: "FountainCore")
            ],
            path: "Sources/patchbay-service-server"
        ),
        .testTarget(
            name: "PatchBayServiceTests",
            dependencies: ["patchbay-service"],
            path: "Tests/PatchBayServiceTests"
        ),
        .testTarget(
            name: "PatchBayAppUITests",
            dependencies: ["patchbay-app"],
            path: "Tests/PatchBayAppUITests",
            resources: [
                .process("Baselines"),
                .process("Fixtures")
            ]
        ),
        .testTarget(
            name: "PBVRTServerTests",
            dependencies: [
                "pbvrt-server",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Tests/PBVRTServerTests"
        ),
        .executableTarget(
            name: "patchbay-snapshots",
            dependencies: ["patchbay-app"],
            path: "Sources/patchbay-snapshots"
        ),
        .executableTarget(
            name: "grid-dev-app",
            dependencies: [
                "MetalViewKit",
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "Teatro", package: "TeatroFull"),
                .product(name: "TeatroRenderAPI", package: "TeatroFull")
            ],
            path: "Sources/grid-dev-app",
            exclude: ["AGENTS.md"]
        ),
        
        .executableTarget(
            name: "grid-dev-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/grid-dev-seed"
        ),
        .executableTarget(
            name: "mpe-pad-app",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/mpe-pad-app"
        ),
        .executableTarget(
            name: "mpe-pad-app-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/mpe-pad-app-seed"
        ),
        .executableTarget(
            name: "patchbay-graph-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/patchbay-graph-seed"
        ),
        .executableTarget(
            name: "llm-adapter-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/llm-adapter-seed"
        ),
        .executableTarget(
            name: "flow-instrument-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/flow-instrument-seed"
        ),
        .executableTarget(
            name: "fountain-editor-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/fountain-editor-seed"
        ),
        .executableTarget(
            name: "service-minimal-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/service-minimal-seed"
        ),
        .executableTarget(
            name: "baseline-robot-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/baseline-robot-seed"
        ),
        .executableTarget(
            name: "corpus-instrument-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/corpus-instrument-seed"
        ),
        .executableTarget(
            name: "patchbay-test-scene-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/patchbay-test-scene-seed"
        ),
        .executableTarget(
            name: "baseline-editor-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/baseline-editor-seed"
        ),
        .executableTarget(
            name: "img-rmse",
            dependencies: [],
            path: "Sources/img-rmse"
        ),
        
        .executableTarget(
            name: "qc-mock-service-server",
            dependencies: [
                "qc-mock-service",
                .product(name: "FountainRuntime", package: "FountainCore")
            ],
            path: "Sources/qc-mock-service-server"
        ),
        .executableTarget(
            name: "qcmockcore-tests",
            dependencies: ["QCMockCore"],
            path: "Sources/qcmockcore-tests"
        ),
        .testTarget(
            name: "QCMockCoreTests",
            dependencies: ["QCMockCore"],
            path: "Tests/QCMockCoreTests"
        ),
        .testTarget(
            name: "QCMockServiceSpecTests",
            dependencies: [
                .product(name: "Yams", package: "Yams")
            ],
            path: "Tests/QCMockServiceSpecTests"
        ),
        .testTarget(
            name: "QCMockHandlersTests",
            dependencies: [
                "qc-mock-service",
                "QCMockServiceCore"
            ],
            path: "Tests/QCMockHandlersTests"
        ),
        .executableTarget(
            name: "qcmockservice-tests",
            dependencies: ["QCMockServiceCore"],
            path: "Sources/qcmockservice-tests"
        ),
        .executableTarget(
            name: "qc-mock-handlers-tests",
            dependencies: ["qc-mock-service"],
            path: "Sources/qc-mock-handlers-tests"
        ),
        .executableTarget(
            name: "m2-smoke",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FunctionCallerService", package: "FountainServiceKit-FunctionCaller"),
                .product(name: "PlannerService", package: "FountainServiceKit-Planner")
            ]
        ),
        .executableTarget(
            name: "audiotalk-ci-smoke",
            dependencies: [
                .product(name: "AudioTalkAPI", package: "FountainAPIClients"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ]
        ),
        .executableTarget(
            name: "audiotalk-cli",
            dependencies: [
                .product(name: "AudioTalkAPI", package: "FountainAPIClients"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "memchat-save-continuity",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-save-continuity"
        ),
        .executableTarget(
            name: "memchat-save-plan",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-save-plan"
        ),
        .executableTarget(
            name: "midi-service-headless-tests",
            dependencies: [],
            path: "Sources/midi-service-headless-tests"
        ),
        .executableTarget(
            name: "memchat-save-reply",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-save-reply"
        ),
        .executableTarget(
            name: "memchat-concept-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/memchat-concept-seed"
        ),
        .executableTarget(
            name: "engraving-demo-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/engraving-demo-seed"
        ),
        .executableTarget(
            name: "llm-doctor",
            dependencies: [],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "engraver-direct",
            dependencies: [],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "gateway-ci-smoke",
            dependencies: [
                .product(name: "GatewayAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "Crypto", package: "swift-crypto")
            ]
        ),
        .executableTarget(
            name: "fk",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .executableTarget(
            name: "tools-factory-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "ToolsFactoryService", package: "FountainServiceKit-ToolsFactory"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md", "AGENTS.md"]
        ),
        .executableTarget(
            name: "tool-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "ToolServerService", package: "FountainServiceKit-ToolServer"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "planner-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "PlannerService", package: "FountainServiceKit-Planner"),
                "Yams",
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "function-caller-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FunctionCallerService", package: "FountainServiceKit-FunctionCaller"),
                "Yams",
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "persist-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "PersistService", package: "FountainServiceKit-Persist"),
                .product(name: "SpeechAtlasService", package: "FountainServiceKit-Persist"),
                "Yams",
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "baseline-awareness-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "AwarenessService", package: "FountainServiceKit-Awareness"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "bootstrap-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "BootstrapService", package: "FountainServiceKit-Bootstrap"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "audiotalk-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "AudioTalkService", package: "FountainServiceKit-AudioTalk"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            exclude: ["README.md", "Static"]
        ),
        .executableTarget(
            name: "instrument-catalog-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/instrument-catalog-server"
        ),
        .executableTarget(
            name: "store-apply-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/store-apply-seed"
        ),
        .executableTarget(
            name: "publishing-frontend",
            dependencies: [
                .product(name: "PublishingFrontend", package: "FountainGatewayKit")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "midi-instrument-host",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "MIDI2CI", package: "midi2"),
                .product(name: "MIDI2", package: "midi2")
            ],
            path: "Sources/midi-instrument-host"
        ),
        .executableTarget(
            name: "ble-midi-scan",
            dependencies: [],
            path: "Sources/ble-midi-scan"
        ),
        .executableTarget(
            name: "ble-midi-adv-check",
            dependencies: [.product(name: "MIDI2Transports", package: "FountainTelemetryKit")],
            path: "Sources/ble-midi-adv-check"
        ),
        // removed: midi-coremidi-integration-check (CoreMIDI)
        // QuietFrame OpenAPI service (control + MIDI)
        .target(
            name: "quietframe-service",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                "MetalViewKit"
            ],
            path: "Sources/quietframe-service",
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "quietframe-service-server",
            dependencies: [
                "quietframe-service",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession")
            ],
            path: "Sources/quietframe-service-server"
        ),
        // Fountain Editor service (server stubs via OpenAPI)
        .target(
            name: "fountain-editor-service-core",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/fountain-editor-service",
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "fountain-editor-service-server",
            dependencies: [
                "fountain-editor-service-core",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/fountain-editor-service-server"
        ),
        .testTarget(
            name: "FountainEditorCoreTests",
            dependencies: ["fountain-editor-service-core"],
            path: "Tests/FountainEditorCoreTests"
        ),
        .testTarget(
            name: "FountainEditorAlignmentTests",
            dependencies: [
                "fountain-editor-service-core",
                .product(name: "FountainEditorMiniCore", package: "fountain-editor-mini-tests"),
                .product(name: "Teatro", package: "TeatroFull")
            ],
            path: "Tests/FountainEditorAlignmentTests",
            resources: [
                .copy("Fixtures")
            ]
        ),
        .testTarget(
            name: "FountainEditorServerTests",
            dependencies: [
                "fountain-editor-service-server",
                "fountain-editor-service-core",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Tests/FountainEditorServerTests"
        ),
        .executableTarget(
            name: "tutor-dashboard",
            dependencies: [
                .product(name: "TutorDashboard", package: "FountainAPIClients"),
                .product(name: "SwiftCursesKit", package: "swiftcurseskit")
            ],
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "pbvrt-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                "pbvrt-service",
                "CoreMLKit"
            ],
            path: "Sources/pbvrt-server"
        ),
        .executableTarget(
            name: "pbvrt-embed-ci",
            dependencies: ["pbvrt-server"],
            path: "Sources/pbvrt-embed-ci"
        ),
        // Quiet‑frame convenience tools (non‑ROBOT_ONLY)
        .executableTarget(
            name: "pbvrt-quietframe-dump",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-quietframe-dump"
        ),
        .executableTarget(
            name: "pbvrt-quietframe-proof",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-quietframe-proof"
        ),
        .executableTarget(
            name: "pbvrt-quietframe-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-quietframe-seed"
        ),
        .executableTarget(
            name: "pbvrt-present",
            dependencies: [],
            path: "Sources/pbvrt-present"
        ),
        .executableTarget(
            name: "pbvrt-tone",
            dependencies: [],
            path: "Sources/pbvrt-tone"
        ),
        .executableTarget(
            name: "pbvrt-clip-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-clip-seed"
        ),
        .executableTarget(
            name: "pbvrt-rig-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/pbvrt-rig-seed"
        ),
        .executableTarget(
            name: "patchbay-docs-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/patchbay-docs-seed"
        ),
        // removed: add-instruments-seed target
        .executableTarget(
            name: "store-dump",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "store-list",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "secrets-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ],
            path: "Sources/secrets-seed"
        ),
        .executableTarget(
            name: "FountainLauncherUI",
            dependencies: [
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/FountainLauncherUI",
            exclude: ["README.md", "AGENTS.md"]
        ),
        .executableTarget(
            name: "engraver-studio-app",
            dependencies: [
                "EngraverStudio",
                "EngraverChatCore",
                .product(name: "FountainDevHarness", package: "FountainDevHarness")
            ],
            path: "Sources/engraver-studio-app"
        ),
        .executableTarget(
            name: "gateway-console",
            dependencies: [
                .product(name: "FountainDevHarness", package: "FountainDevHarness"),
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients")
            ],
            path: "Sources/gateway-console"
        ),
        .executableTarget(
            name: "gateway-console-app",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/gateway-console-app"
        ),
        .executableTarget(
            name: "local-agent-manager",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ]
        ),
        .executableTarget(
            name: "mock-localagent-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore")
            ]
        ),
        .target(
            name: "EngraverChatCore",
            dependencies: [
                .product(name: "FountainAICore", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "LLMGatewayAPI", package: "FountainAPIClients"),
                .product(name: "AwarenessAPI", package: "FountainAPIClients"),
                .product(name: "BootstrapAPI", package: "FountainAPIClients"),
                .product(name: "SemanticBrowserAPI", package: "FountainAPIClients"),
                .product(name: "ApiClientsCore", package: "FountainAPIClients"),
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/EngraverChatCore"
        ),
        .target(
            name: "EngraverStudio",
            dependencies: [
                "EngraverChatCore",
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "ProviderOpenAI", package: "FountainProviders"),
                .product(name: "ProviderLocalLLM", package: "FountainProviders"),
                .product(name: "ProviderGateway", package: "FountainProviders"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "Teatro", package: "TeatroFull")
            ],
            path: "Sources/engraver-studio",
            exclude: ["README.md"]
        ),
        .executableTarget(
            name: "engraver-chat-tui",
            dependencies: [
                "EngraverChatCore",
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "FountainDevHarness", package: "FountainDevHarness"),
                .product(name: "ProviderOpenAI", package: "FountainProviders"),
                .product(name: "ProviderLocalLLM", package: "FountainProviders"),
                .product(name: "ProviderGateway", package: "FountainProviders"),
                .product(name: "SwiftCursesKit", package: "swiftcurseskit"),
                .product(name: "FountainAIAdapters", package: "FountainGatewayKit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/engraver-chat-tui"
        ),
        .executableTarget(
            name: "engraving-tui",
            dependencies: [
                .product(name: "SwiftCursesKit", package: "swiftcurseskit"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/engraving-tui"
        ),
        .executableTarget(
            name: "engraving-app",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainAIKit", package: "FountainAIKit"),
                .product(name: "ProviderOpenAI", package: "FountainProviders")
            ],
            path: "Sources/engraving-app"
        ),
        .executableTarget(
            name: "quietframe-editor-app",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/quietframe-editor-app"
        ),
        .executableTarget(
            name: "memchat-app",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "MemChatKit", package: "MemChatKit"),
                .product(name: "SecretStore", package: "swift-secretstore")
            ],
            path: "Sources/memchat-app"
        ),
        .executableTarget(
            name: "memchat-teatro",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "MemChatKit", package: "MemChatKit"),
                .product(name: "SecretStore", package: "swift-secretstore"),
                .product(name: "Teatro", package: "TeatroFull")
            ],
            path: "Sources/memchat-teatro"
        ),
        .executableTarget(
            name: "fk-ops-server",
            dependencies: [
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "FKOpsService", package: "FountainServiceKit-FKOps"),
                .product(name: "LauncherSignature", package: "FountainCore")
            ]
        ),
        .testTarget(
            name: "FountainLauncherUITests",
            dependencies: ["FountainLauncherUI"]
        ),
        .testTarget(
            name: "EngraverStudioTests",
            dependencies: ["EngraverStudio", "EngraverChatCore", "engraver-chat-tui"],
            path: "Tests/EngraverStudioTests"
        ),
        .testTarget(
            name: "FountainDevScriptsTests",
            dependencies: []
        ),
        .testTarget(
            name: "GatewayServerTests",
            dependencies: [
                "gateway-server",
                .product(name: "FountainRuntime", package: "FountainCore"),
                .product(name: "ChatKitGatewayPlugin", package: "FountainGatewayKit"),
                .product(name: "GatewayAPI", package: "FountainAPIClients")
            ]
        )
        ,
        .testTarget(
            name: "MetalComputeKitTests",
            dependencies: ["MetalComputeKit"],
            path: "Tests/MetalComputeKitTests"
        ),
        .executableTarget(
            name: "metalview-demo-app",
            dependencies: [
                "MetalViewKit",
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit"),
                .product(name: "Teatro", package: "TeatroFull"),
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Sources/metalview-demo-app",
            exclude: ["AGENTS.md"]
        ),
        
        .executableTarget(
            name: "replay-export",
            dependencies: ["patchbay-app"],
            path: "Sources/replay-export"
        )
        ,
        .executableTarget(
            name: "patchbay-saliency-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/patchbay-saliency-seed"
        ),
        // removed: midi-ump2m1-bridge (CoreMIDI)
        // QuietFrameKit — core utilities for MIDI2 PE + Vendor JSON (UI-free)
        .target(
            name: "QuietFrameKit",
            dependencies: [
                .product(name: "MIDI2CI", package: "midi2"),
                .product(name: "MIDI2", package: "midi2")
            ],
            path: "Sources/QuietFrameKit"
        ),
        // Lightweight autarkic audio engine (SDLKit-backed when available; no-op fallback otherwise)
        .target(
            name: "FountainAudioEngine",
            dependencies: USE_SDLKIT ? [ .product(name: "SDLKitAudio", package: "SDLKit") ] : [],
            path: "Sources/FountainAudioEngine"
        ),
        // AUM-inspired MIDI routing matrix kit (SwiftUI)
        .target(
            name: "Midi2MappingKit",
            dependencies: [],
            path: "Sources/Midi2MappingKit"
        ),
        .executableTarget(
            name: "quietframe-sonify-app",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Teatro", package: "TeatroFull"),
                "MetalViewKit",
                "FountainAudioEngine",
                "QuietFrameKit"
                // Routing view removed; Midi2MappingKit/Yams/Crypto not required here
            ],
            path: "Sources/quietframe-sonify-app"
        ),
        .executableTarget(
            name: "quietframe-cc-mapping-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/quietframe-cc-mapping-seed"
        ),
        .executableTarget(
            name: "quietframe-orchestra-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/quietframe-orchestra-seed"
        ),
        .executableTarget(
            name: "quietframe-orchestra-generate",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Yams", package: "Yams")
            ],
            path: "Sources/quietframe-orchestra-generate"
        ),
        .executableTarget(
            name: "die-maschine-teatro-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/die-maschine-teatro-seed"
        ),
        .executableTarget(
            name: "die-maschine-scenes-assign",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/die-maschine-scenes-assign"
        ),
        
        .executableTarget(
            name: "quietframe-companion-app",
            dependencies: [
                "FountainAudioEngine",
                "MetalViewKit",
                "QuietFrameKit",
                .product(name: "MIDI2CI", package: "midi2"),
                .product(name: "MIDI2", package: "midi2")
            ],
            path: "Sources/quietframe-companion-app"
        ),
        // removed: quietframe-smoke (CoreMIDI)
        .testTarget(
            name: "QuietFrameKitTests",
            dependencies: [
                "QuietFrameKit",
                .product(name: "MIDI2CI", package: "midi2")
            ],
            path: "Tests/QuietFrameKitTests"
        ),
        .executableTarget(
            name: "quietframe-sonify-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/quietframe-sonify-seed"
        ),
        .executableTarget(
            name: "quietframe-companion-seed",
            dependencies: [
                .product(name: "LauncherSignature", package: "FountainCore"),
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/quietframe-companion-seed"
        ),
        .executableTarget(
            name: "quietframe-teatro-seed",
            dependencies: [
                .product(name: "FountainStoreClient", package: "FountainCore")
            ],
            path: "Sources/quietframe-teatro-seed"
        ),
        // MVK Runtime Server split: library (kit) + thin executable
        .target(
            name: "MetalViewKitRuntimeServerKit",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "FountainRuntime", package: "FountainCore"),
                "MetalViewKit"
            ],
            path: "Sources/MetalViewKitRuntimeServerKit",
            plugins: [
                .plugin(name: "EnsureOpenAPIConfigPlugin", package: "FountainTooling"),
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .executableTarget(
            name: "metalviewkit-runtime-server",
            dependencies: [
                "MetalViewKitRuntimeServerKit"
            ],
            path: "Sources/metalviewkit-runtime-server"
        ),
        .executableTarget(
            name: "csound-audio-test",
            dependencies: [],
            path: "Sources/csound-audio-test"
        ),
        .executableTarget(
            name: "mvk-runtime-tests",
            dependencies: [
                "MetalViewKitRuntimeServerKit",
                .product(name: "FountainRuntime", package: "FountainCore")
            ],
            path: "Sources/mvk-runtime-tests"
        ),
        .executableTarget(
            name: "metalviewkit-cc-fuzz",
            dependencies: [
                "MetalViewKit"
            ],
            path: "Sources/metalviewkit-cc-fuzz"
        ),
        .executableTarget(
            name: "sysx-json-sender",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/sysx-json-sender"
        ),
        .executableTarget(
            name: "sysx-json-receiver",
            dependencies: [
                .product(name: "MIDI2Transports", package: "FountainTelemetryKit")
            ],
            path: "Sources/sysx-json-receiver"
        ),
        .executableTarget(
            name: "editor-snapshots",
            dependencies: [
                "quietframe-editor-app"
            ],
            path: "Sources/editor-snapshots"
        ),
        .testTarget(
            name: "MVKRuntimeServerTests",
            dependencies: [
                "metalviewkit-runtime-server",
                "MetalViewKit",
                .product(name: "FountainRuntime", package: "FountainCore")
            ],
            path: "Tests/MVKRuntimeServerTests"
        ),
        .testTarget(
            name: "EditorAppUITests",
            dependencies: [
                "quietframe-editor-app"
            ],
            path: "Tests/EditorAppUITests",
            resources: [
                .process("Baselines")
            ]
        ),
        .testTarget(
            name: "QuietFrameEditorUITests",
            dependencies: [
                "quietframe-sonify-app"
            ],
            path: "Tests/QuietFrameEditorUITests",
            resources: [
                .process("Baselines")
            ]
        )
        
    ] )))

let package = Package(
    name: "FountainApps",
    platforms: [
        .macOS(.v14)
    ],
    products: PRODUCTS,
    dependencies: DEPENDENCIES,
    targets: TARGETS
)
