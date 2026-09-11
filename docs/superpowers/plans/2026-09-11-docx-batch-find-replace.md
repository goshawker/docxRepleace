# DocxReplace 实现计划

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 构建一个 macOS 桌面应用，批量查找并替换指定文件夹下所有 `.docx` 文件中的文字，且除目标文字外 XML 字节级不变，从而保证格式完全不变。

**Architecture:** 自研零依赖引擎。`ZipArchive`/`ZipWriter` 基于系统 `Compression` 框架实现 ZIP 读写；`XmlTextLocator` 在原始 XML 字节上定位 `w:t` 元素并做外科手术式改写；`DocxXmlAnalyzer` 用 `XMLDocument` 解析段落结构（解决文字被拆成多个 run 的问题）；`ParagraphMatcher` 是纯文本匹配/替换逻辑。SwiftUI 界面通过 `ReplaceCoordinator` 编排扫描与替换。

**Tech Stack:** Swift（语言模式 5.0，编译器 Swift 6.3）、SwiftUI、XCTest、Foundation `XMLDocument`、`Compression` 框架、系统 `textutil`/`unzip`（仅测试使用）。

---

## 前置约束（每个任务都要遵守）

- **零第三方依赖**：本机无法访问 GitHub，禁止引入任何 SPM/CocoaPods 依赖。
- **`.docx` 之外一律不处理**：`.doc` 在扫描时列出并提示「需先转为 .docx」。
- **不做无备份的原地修改**：备份失败必须跳过该文件。
- **共享约定**：所有路径相对于仓库根 `/Users/LB/Documents/AIProjects/DocxRepleace`。
- **构建/测试命令**（后续任务中的 `Run:` 均指这两条）：
  - 构建：`xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' build`
  - 测试：`xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test`
  - 单测类：在上面测试命令后追加 `-only-testing:DocxReplaceTests/XmlTextLocatorTests`
  - **注意**：`xcodebuild` 输出很长，判定结果看最后几行。成功以 `** TEST SUCCEEDED **` / `** BUILD SUCCEEDED **` 为准。

## 文件结构

| 文件 | 职责 |
|---|---|
| `DocxReplace.xcodeproj/project.pbxproj` | 工程文件（手工编写，Xcode 16+ 同步文件夹格式） |
| `DocxReplace.xcodeproj/xcshareddata/xcschemes/DocxReplace.xcscheme` | 共享 scheme（CLI 构建/测试需要） |
| `DocxReplace/DocxReplaceApp.swift` | `@main` 入口 |
| `DocxReplace/Models.swift` | `ReplaceOptions` / `ScanItem` / `FileScanResult` / `ReplaceReport` 等值类型 |
| `DocxReplace/Core/ZipCRC32.swift` | CRC32 校验和 |
| `DocxReplace/Core/ZipCompression.swift` | raw DEFLATE 压缩/解压（Compression 框架） |
| `DocxReplace/Core/ZipArchive.swift` | ZIP 读取 |
| `DocxReplace/Core/ZipWriter.swift` | ZIP 写出 |
| `DocxReplace/Core/XmlTextLocator.swift` | `w:t` 定位与原始 XML 字节改写 |
| `DocxReplace/Core/DocxXmlAnalyzer.swift` | 段落/分段结构（XMLDocument） |
| `DocxReplace/Core/ParagraphMatcher.swift` | 纯文本查找与替换区间计算 |
| `DocxReplace/Core/DocxTextReplacer.swift` | `.docx` 替换主流程（Data → Data） |
| `DocxReplace/Core/FileScanner.swift` | 递归扫描文件夹 |
| `DocxReplace/Core/BackupManager.swift` | 备份 |
| `DocxReplace/Core/ReplaceCoordinator.swift` | 扫描/替换编排、进度、取消 |
| `DocxReplace/AppViewModel.swift` | `@MainActor` 状态机 |
| `DocxReplace/ContentView.swift` | 主界面 |
| `DocxReplaceTests/*.swift` | XCTest 测试与夹具生成器 |

---

## Task 1: Xcode 工程骨架

**Files:**
- Create: `DocxReplace.xcodeproj/project.pbxproj`
- Create: `DocxReplace.xcodeproj/xcshareddata/xcschemes/DocxReplace.xcscheme`
- Create: `DocxReplace/DocxReplaceApp.swift`
- Create: `DocxReplace/Models.swift`
- Create: `DocxReplaceTests/SanityTests.swift`

- [ ] **Step 1: 创建目录**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
mkdir -p DocxReplace/Core DocxReplaceTests DocxReplace.xcodeproj/xcshareddata/xcschemes
```

- [ ] **Step 2: 写 `DocxReplace/Models.swift`**

```swift
import Foundation

struct ReplaceOptions: Equatable {
    var caseSensitive: Bool = false
    var wholeWord: Bool = false
}

enum FileKind {
    case docx
    case legacyDoc
}

struct ScanItem: Equatable {
    var url: URL
    var relativePath: String
    var kind: FileKind
}

enum FileOutcome: Equatable {
    case matched(Int)
    case noMatch
    case unsupported(String)
    case failed(String)
}

struct FileScanResult: Identifiable, Equatable {
    var item: ScanItem
    var outcome: FileOutcome

    var id: String { item.relativePath }
    var relativePath: String { item.relativePath }

    var matchCount: Int {
        if case .matched(let count) = outcome { return count }
        return 0
    }
}

struct ReportedFile: Equatable {
    var path: String
    var reason: String
}

struct ReplaceReport: Equatable {
    var modifiedFiles: Int = 0
    var replacedCount: Int = 0
    var skipped: [ReportedFile] = []
    var failed: [ReportedFile] = []
    var backupDirectory: URL?
    var cancelled: Bool = false
}
```

- [ ] **Step 3: 写 `DocxReplace/DocxReplaceApp.swift`**

```swift
import SwiftUI

@main
struct DocxReplaceApp: App {
    var body: some Scene {
        WindowGroup("Word 批量查找替换") {
            ContentView()
                .frame(minWidth: 760, minHeight: 560)
        }
    }
}
```

- [ ] **Step 4: 写临时的 `DocxReplace/ContentView.swift`**

（Task 14 会替换成真正的界面，这里只要能编译。）

```swift
import SwiftUI

struct ContentView: View {
    var body: some View {
        Text("DocxReplace")
            .padding()
    }
}
```

- [ ] **Step 5: 写 `DocxReplaceTests/SanityTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class SanityTests: XCTestCase {
    func testModuleLoads() {
        XCTAssertFalse(ReplaceOptions().caseSensitive)
        XCTAssertTrue(ReplaceOptions(caseSensitive: true, wholeWord: true).wholeWord)
    }
}
```

- [ ] **Step 6: 写 `DocxReplace.xcodeproj/project.pbxproj`**

原样复制以下内容。UUID 必须与 scheme 中的 `BlueprintIdentifier` 一致。

```
// !$*UTF8*$!
{
	archiveVersion = 1;
	classes = {
	};
	objectVersion = 77;
	objects = {

/* Begin PBXFileReference section */
		A100000000000000000000A5 /* DocxReplace.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DocxReplace.app; sourceTree = BUILT_PRODUCTS_DIR; };
		A100000000000000000000A6 /* DocxReplaceTests.xctest */ = {isa = PBXFileReference; explicitFileType = wrapper.cfbundle; includeInIndex = 0; path = DocxReplaceTests.xctest; sourceTree = BUILT_PRODUCTS_DIR; };
/* End PBXFileReference section */

/* Begin PBXFileSystemSynchronizedRootGroup section */
		A100000000000000000000A3 /* DocxReplace */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = DocxReplace;
			sourceTree = "<group>";
		};
		A100000000000000000000A4 /* DocxReplaceTests */ = {
			isa = PBXFileSystemSynchronizedRootGroup;
			path = DocxReplaceTests;
			sourceTree = "<group>";
		};
/* End PBXFileSystemSynchronizedRootGroup section */

/* Begin PBXFrameworksBuildPhase section */
		A100000000000000000000C2 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A100000000000000000000C5 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		A100000000000000000000A1 = {
			isa = PBXGroup;
			children = (
				A100000000000000000000A3 /* DocxReplace */,
				A100000000000000000000A4 /* DocxReplaceTests */,
				A100000000000000000000A2 /* Products */,
			);
			sourceTree = "<group>";
		};
		A100000000000000000000A2 /* Products */ = {
			isa = PBXGroup;
			children = (
				A100000000000000000000A5 /* DocxReplace.app */,
				A100000000000000000000A6 /* DocxReplaceTests.xctest */,
			);
			name = Products;
			sourceTree = "<group>";
		};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		A100000000000000000000B1 /* DocxReplace */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A100000000000000000000E2 /* Build configuration list for PBXNativeTarget "DocxReplace" */;
			buildPhases = (
				A100000000000000000000C1 /* Sources */,
				A100000000000000000000C2 /* Frameworks */,
				A100000000000000000000C3 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			fileSystemSynchronizedGroups = (
				A100000000000000000000A3 /* DocxReplace */,
			);
			name = DocxReplace;
			packageProductDependencies = (
			);
			productName = DocxReplace;
			productReference = A100000000000000000000A5 /* DocxReplace.app */;
			productType = "com.apple.product-type.application";
		};
		A100000000000000000000B2 /* DocxReplaceTests */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = A100000000000000000000E3 /* Build configuration list for PBXNativeTarget "DocxReplaceTests" */;
			buildPhases = (
				A100000000000000000000C4 /* Sources */,
				A100000000000000000000C5 /* Frameworks */,
				A100000000000000000000C6 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
				A100000000000000000000F7 /* PBXTargetDependency */,
			);
			fileSystemSynchronizedGroups = (
				A100000000000000000000A4 /* DocxReplaceTests */,
			);
			name = DocxReplaceTests;
			packageProductDependencies = (
			);
			productName = DocxReplaceTests;
			productReference = A100000000000000000000A6 /* DocxReplaceTests.xctest */;
			productType = "com.apple.product-type.bundle.unit-test";
		};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		A100000000000000000000D1 /* Project object */ = {
			isa = PBXProject;
			attributes = {
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 2660;
				LastUpgradeCheck = 2660;
				TargetAttributes = {
					A100000000000000000000B1 = {
						CreatedOnToolsVersion = 26.6;
					};
					A100000000000000000000B2 = {
						CreatedOnToolsVersion = 26.6;
						TestTargetID = A100000000000000000000B1;
					};
				};
			};
			buildConfigurationList = A100000000000000000000E1 /* Build configuration list for PBXProject "DocxReplace" */;
			compatibilityVersion = "Xcode 15.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = A100000000000000000000A1;
			minimizedProjectReferenceProxies = 1;
			preferredProjectObjectVersion = 77;
			productRefGroup = A100000000000000000000A2 /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				A100000000000000000000B1 /* DocxReplace */,
				A100000000000000000000B2 /* DocxReplaceTests */,
			);
		};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		A100000000000000000000C3 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A100000000000000000000C6 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		A100000000000000000000C1 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		A100000000000000000000C4 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
/* End PBXSourcesBuildPhase section */

/* Begin PBXTargetDependency section */
		A100000000000000000000F7 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = A100000000000000000000B1 /* DocxReplace */;
			targetProxy = A100000000000000000000F8 /* PBXContainerItemProxy */;
		};
/* End PBXTargetDependency section */

/* Begin PBXContainerItemProxy section */
		A100000000000000000000F8 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = A100000000000000000000D1 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = A100000000000000000000B1;
			remoteInfo = DocxReplace;
		};
/* End PBXContainerItemProxy section */

/* Begin XCBuildConfiguration section */
		A100000000000000000000F1 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = macosx;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		A100000000000000000000F2 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_C_LANGUAGE_STANDARD = gnu17;
				GCC_NO_COMMON_BLOCKS = YES;
				MACOSX_DEPLOYMENT_TARGET = 14.0;
				MTL_ENABLE_DEBUG_INFO = NO;
				SDKROOT = macosx;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		A100000000000000000000F3 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = NO;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				INFOPLIST_KEY_NSPrincipalClass = NSApplication;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = local.DocxReplace;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			};
			name = Debug;
		};
		A100000000000000000000F4 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				COMBINE_HIDPI_IMAGES = YES;
				CURRENT_PROJECT_VERSION = 1;
				ENABLE_APP_SANDBOX = NO;
				ENABLE_HARDENED_RUNTIME = NO;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSHumanReadableCopyright = "";
				INFOPLIST_KEY_NSPrincipalClass = NSApplication;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = local.DocxReplace;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
			};
			name = Release;
		};
		A100000000000000000000F5 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@loader_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = local.DocxReplaceTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/DocxReplace.app/Contents/MacOS/DocxReplace";
			};
			name = Debug;
		};
		A100000000000000000000F6 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				BUNDLE_LOADER = "$(TEST_HOST)";
				CODE_SIGN_IDENTITY = "-";
				CODE_SIGN_STYLE = Automatic;
				GENERATE_INFOPLIST_FILE = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/../Frameworks",
					"@loader_path/../Frameworks",
				);
				PRODUCT_BUNDLE_IDENTIFIER = local.DocxReplaceTests;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_VERSION = 5.0;
				TEST_HOST = "$(BUILT_PRODUCTS_DIR)/DocxReplace.app/Contents/MacOS/DocxReplace";
			};
			name = Release;
		};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		A100000000000000000000E1 /* Build configuration list for PBXProject "DocxReplace" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A100000000000000000000F1 /* Debug */,
				A100000000000000000000F2 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A100000000000000000000E2 /* Build configuration list for PBXNativeTarget "DocxReplace" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A100000000000000000000F3 /* Debug */,
				A100000000000000000000F4 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
		A100000000000000000000E3 /* Build configuration list for PBXNativeTarget "DocxReplaceTests" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				A100000000000000000000F5 /* Debug */,
				A100000000000000000000F6 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		};
/* End XCConfigurationList section */
	};
	rootObject = A100000000000000000000D1 /* Project object */;
}
```

- [ ] **Step 7: 写 `DocxReplace.xcodeproj/xcshareddata/xcschemes/DocxReplace.xcscheme`**

```xml
<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "2660"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "A100000000000000000000B1"
               BuildableName = "DocxReplace.app"
               BlueprintName = "DocxReplace"
               ReferencedContainer = "container:DocxReplace.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference
            skipped = "NO">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "A100000000000000000000B2"
               BuildableName = "DocxReplaceTests.xctest"
               BlueprintName = "DocxReplaceTests"
               ReferencedContainer = "container:DocxReplace.xcodeproj">
            </BuildableReference>
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "A100000000000000000000B1"
            BuildableName = "DocxReplace.app"
            BlueprintName = "DocxReplace"
            ReferencedContainer = "container:DocxReplace.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "A100000000000000000000B1"
            BuildableName = "DocxReplace.app"
            BlueprintName = "DocxReplace"
            ReferencedContainer = "container:DocxReplace.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
```

- [ ] **Step 8: 验证工程可被识别**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -list
```

Expected: 输出列出 `Targets: DocxReplace, DocxReplaceTests` 与 `Schemes: DocxReplace`。若报 `project cannot be opened`，说明 pbxproj 语法有误，逐字核对上面的内容（尤其是括号与分号）。

- [ ] **Step 9: 构建并跑测试**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test
```

Expected: `** TEST SUCCEEDED **`，且输出中有 `SanityTests.testModuleLoads` 通过。

**若手工 pbxproj 反复失败超过 3 次**，停止并告知用户，改用回退方案：请用户打开 Xcode → File → New → Project → macOS → App，Product Name 填 `DocxReplace`，Interface 选 SwiftUI，Language 选 Swift，勾选 Include Tests，保存到本项目根目录，然后用 `DocxReplace/` 下的源码覆盖模板生成的同名文件。

- [ ] **Step 10: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace.xcodeproj DocxReplace DocxReplaceTests
git commit -m "chore: 搭建 Xcode 工程骨架（零依赖，含单元测试目标）"
```

---

## Task 2: CRC32 与 DEFLATE 压缩

**Files:**
- Create: `DocxReplace/Core/ZipCRC32.swift`
- Create: `DocxReplace/Core/ZipCompression.swift`
- Test: `DocxReplaceTests/ZipCompressionTests.swift`

- [ ] **Step 1: 写失败测试 `DocxReplaceTests/ZipCompressionTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class ZipCompressionTests: XCTestCase {
    func testCRC32KnownVector() {
        // "123456789" 的 CRC32 标准值
        XCTAssertEqual(ZipCRC32.checksum(Data("123456789".utf8)), 0xCBF43926)
    }

    func testCRC32OfEmptyData() {
        XCTAssertEqual(ZipCRC32.checksum(Data()), 0)
    }

    func testDeflateThenInflateRoundTrip() throws {
        let original = Data(String(repeating: "测试 abcdefg 12345 ", count: 500).utf8)
        let deflated = try XCTUnwrap(ZipCompression.deflate(original))
        XCTAssertLessThan(deflated.count, original.count)
        let inflated = try XCTUnwrap(ZipCompression.inflate(deflated, expectedSize: original.count))
        XCTAssertEqual(inflated, original)
    }

    func testInflateIncompressibleData() throws {
        var bytes = [UInt8]()
        var seed: UInt32 = 12345
        for _ in 0..<4096 {
            seed = seed &* 1664525 &+ 1013904223
            bytes.append(UInt8(truncatingIfNeeded: seed >> 16))
        }
        let original = Data(bytes)
        let deflated = try XCTUnwrap(ZipCompression.deflate(original))
        let inflated = try XCTUnwrap(ZipCompression.inflate(deflated, expectedSize: original.count))
        XCTAssertEqual(inflated, original)
    }

    func testInflateRejectsGarbage() {
        let garbage = Data([0x01, 0x02, 0x03, 0x04, 0x05])
        XCTAssertNil(ZipCompression.inflate(garbage, expectedSize: 100))
    }

    func testInflateRecoversWhenExpectedSizeTooSmall() throws {
        // compression_decode_buffer 在缓冲区不足时返回已解出的字节数（截断）而非报错，
        // 因此 must 靠「未填满缓冲区」判定成功，并自动扩容重试
        let original = Data(String(repeating: "截断风险 abcdefg ", count: 500).utf8)
        let deflated = try XCTUnwrap(ZipCompression.deflate(original))
        let inflated = try XCTUnwrap(ZipCompression.inflate(deflated, expectedSize: original.count / 2))
        XCTAssertEqual(inflated, original)
    }

    func testInflateAcceptsOversizedExpectedSize() throws {
        let original = Data(String(repeating: "hello 你好 ", count: 300).utf8)
        let deflated = try XCTUnwrap(ZipCompression.deflate(original))
        XCTAssertEqual(ZipCompression.inflate(deflated, expectedSize: original.count * 2), original)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipCompressionTests 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'ZipCRC32' in scope`。

- [ ] **Step 3: 写 `DocxReplace/Core/ZipCRC32.swift`**

```swift
import Foundation

enum ZipCRC32 {
    private static let table: [UInt32] = (0..<256).map { i -> UInt32 in
        var c = UInt32(i)
        for _ in 0..<8 {
            c = (c & 1) != 0 ? (0xEDB88320 ^ (c >> 1)) : (c >> 1)
        }
        return c
    }

    static func checksum(_ data: Data) -> UInt32 {
        var c: UInt32 = 0xFFFFFFFF
        for byte in data {
            c = table[Int((c ^ UInt32(byte)) & 0xFF)] ^ (c >> 8)
        }
        return c ^ 0xFFFFFFFF
    }
}
```

- [ ] **Step 4: 写 `DocxReplace/Core/ZipCompression.swift`**

`COMPRESSION_ZLIB` 产出的是 raw DEFLATE 流（RFC 1951），正是 ZIP 所需，不含 zlib 头尾。

```swift
import Compression
import Foundation

enum ZipCompression {
    /// raw DEFLATE 压缩；缓冲区不足时返回 nil（调用方应改为 stored 存储）
    static func deflate(_ data: Data) -> Data? {
        guard !data.isEmpty else { return Data() }
        let capacity = data.count + data.count / 1000 + 64
        var output = Data(count: capacity)
        let written = output.withUnsafeMutableBytes { dst -> Int in
            guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
            return data.withUnsafeBytes { src -> Int in
                guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return compression_encode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
            }
        }
        guard written > 0, written < capacity else { return nil }
        output.removeSubrange(written...)
        return output
    }

    /// raw DEFLATE 解压。expectedSize 来自 ZIP 中央目录。
    ///
    /// 关键：`compression_decode_buffer` 在缓冲区不足时**不报错**，而是返回已解出的
    /// 字节数（即截断）。因此初始容量取 `expectedSize + 1`，并且只接受「未填满缓冲区」
    /// 的结果——否则会把截断的数据当作完整结果返回。
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return expectedSize == 0 ? Data() : nil }
        guard expectedSize > 0 else { return nil }
        var capacity = expectedSize + 1
        for _ in 0..<5 {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { dst -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return data.withUnsafeBytes { src -> Int in
                    guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0, written < capacity {
                output.removeSubrange(written...)
                return output
            }
            capacity = capacity * 4 + 64
        }
        return nil
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipCompressionTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，7 个测试全部通过。

若 `testInflateRejectsGarbage` 意外通过解码（返回非 nil），删除该断言改成「解码结果不等于原始垃圾数据」的断言即可——不同系统的 Compression 实现对垃圾输入容忍度不同，这不是本项目的关键行为。

- [ ] **Step 6: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ZipCRC32.swift DocxReplace/Core/ZipCompression.swift DocxReplaceTests/ZipCompressionTests.swift
git commit -m "feat: 加入 CRC32 与 raw DEFLATE 压缩解压"
```

---

## Task 3: ZIP 读取

**Files:**
- Create: `DocxReplace/Core/ZipArchive.swift`
- Test: `DocxReplaceTests/ZipArchiveTests.swift`

- [ ] **Step 1: 写失败测试 `DocxReplaceTests/ZipArchiveTests.swift`**

`makeRealDocx` 用系统 `textutil` 生成一个真实 docx，作为独立于我们自己实现的读取验证。

```swift
import XCTest
@testable import DocxReplace

final class ZipArchiveTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("ZipArchiveTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    /// 用系统 textutil 生成真实 docx
    /// 注意：HTML 必须显式声明 charset，否则中文系统下 textutil 会按 GBK 解释，docx 内容成乱码
    static func makeRealDocx(text: String, into directory: URL) throws -> URL {
        let htmlURL = directory.appendingPathComponent("source.html")
        let docxURL = directory.appendingPathComponent("source.docx")
        try "<html><head><meta charset=\"utf-8\"></head><body><p>\(text)</p></body></html>"
            .write(to: htmlURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", "-output", docxURL.path, htmlURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "textutil 生成 docx 失败")
        return docxURL
    }

    func testReadsRealDocx() throws {
        let url = try Self.makeRealDocx(text: "示例文档内容", into: tempDir)
        let archive = try ZipArchive(data: Data(contentsOf: url))
        let entry = try XCTUnwrap(archive.entry(named: "word/document.xml"))
        let xml = try archive.contents(of: entry)
        let text = String(decoding: xml, as: UTF8.self)
        XCTAssertTrue(text.contains("示例文档内容"), "应能解出正文文字")
    }

    func testStoredEntryRoundTrip() throws {
        let payload = Data("stored payload 内容".utf8)
        let entry = ZipOutputEntry(name: "a.txt", dosTime: 0, dosDate: 0, method: 0,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: payload)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        XCTAssertEqual(try archive.contents(of: try XCTUnwrap(archive.entry(named: "a.txt"))), payload)
    }

    func testDeflatedEntryRoundTrip() throws {
        let payload = Data(String(repeating: "hello world 你好 ", count: 200).utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let entry = ZipOutputEntry(name: "dir/b.txt", dosTime: 0, dosDate: 0, method: 8,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: compressed)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        XCTAssertEqual(try archive.contents(of: try XCTUnwrap(archive.entry(named: "dir/b.txt"))), payload)
    }

    func testRejectsNonZipData() {
        XCTAssertThrowsError(try ZipArchive(data: Data(repeating: 0x41, count: 200)))
    }

    func testDetectsCRCMismatch() throws {
        let payload = Data("hello".utf8)
        let entry = ZipOutputEntry(name: "c.txt", dosTime: 0, dosDate: 0, method: 0,
                                   crc32: 0xDEADBEEF, uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: payload)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        XCTAssertThrowsError(try archive.contents(of: try XCTUnwrap(archive.entry(named: "c.txt"))))
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipArchiveTests 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'ZipArchive' in scope`（`ZipWriter` 也还没写，属正常）。

- [ ] **Step 3: 写 `DocxReplace/Core/ZipArchive.swift`**

```swift
import Foundation

enum ZipError: Error, Equatable {
    case notAZipFile
    case zip64Unsupported
    case unsupportedCompression(UInt16)
    case encryptedEntry(String)
    case corruptEntry(String)
    case crcMismatch(String)

    var message: String {
        switch self {
        case .notAZipFile: return "不是有效的 .docx 文件（可能是 .doc 或已损坏）"
        case .zip64Unsupported: return "ZIP64 格式暂不支持"
        case .unsupportedCompression(let method): return "不支持的压缩方式（\(method)）"
        case .encryptedEntry(let name): return "文档已加密，无法读取（\(name)）"
        case .corruptEntry(let name): return "文件结构损坏（\(name)）"
        case .crcMismatch(let name): return "数据校验失败（\(name)）"
        }
    }
}

struct ZipEntry: Equatable {
    var name: String
    var versionMadeBy: UInt16
    var flags: UInt16
    var method: UInt16
    var modTime: UInt16
    var modDate: UInt16
    var crc32: UInt32
    var compressedSize: UInt32
    var uncompressedSize: UInt32
    var externalAttributes: UInt32
    var localHeaderOffset: UInt32
}

struct ZipArchive {
    let entries: [ZipEntry]
    private let bytes: [UInt8]

    init(data: Data) throws {
        let bytes = [UInt8](data)
        self.bytes = bytes
        guard bytes.count >= 22 else { throw ZipError.notAZipFile }

        var eocd = -1
        let minStart = max(0, bytes.count - 65557)
        var i = bytes.count - 22
        while i >= minStart {
            if Self.readU32(bytes, i) == 0x06054b50 { eocd = i; break }
            i -= 1
        }
        guard eocd >= 0 else { throw ZipError.notAZipFile }

        let totalEntries = Int(Self.readU16(bytes, eocd + 10))
        let cdSize = Int(Self.readU32(bytes, eocd + 12))
        let cdOffset = Int(Self.readU32(bytes, eocd + 16))
        if totalEntries == 0xFFFF || cdSize == 0xFFFFFFFF || cdOffset == 0xFFFFFFFF {
            throw ZipError.zip64Unsupported
        }
        guard cdOffset >= 0, cdSize >= 0, cdOffset + cdSize <= bytes.count else {
            throw ZipError.corruptEntry("中央目录越界")
        }

        var parsed: [ZipEntry] = []
        var p = cdOffset
        for _ in 0..<totalEntries {
            guard p + 46 <= bytes.count, Self.readU32(bytes, p) == 0x02014b50 else {
                throw ZipError.corruptEntry("中央目录条目损坏")
            }
            let flags = Self.readU16(bytes, p + 8)
            let method = Self.readU16(bytes, p + 10)
            let crc = Self.readU32(bytes, p + 16)
            let compressedSize = Self.readU32(bytes, p + 20)
            let uncompressedSize = Self.readU32(bytes, p + 24)
            let nameLen = Int(Self.readU16(bytes, p + 28))
            let extraLen = Int(Self.readU16(bytes, p + 30))
            let commentLen = Int(Self.readU16(bytes, p + 32))
            let localOffset = Self.readU32(bytes, p + 42)
            guard p + 46 + nameLen + extraLen + commentLen <= bytes.count else {
                throw ZipError.corruptEntry("中央目录条目越界")
            }
            if compressedSize == 0xFFFFFFFF || uncompressedSize == 0xFFFFFFFF || localOffset == 0xFFFFFFFF {
                throw ZipError.zip64Unsupported
            }
            let name = String(decoding: bytes[(p + 46)..<(p + 46 + nameLen)], as: UTF8.self)
            parsed.append(ZipEntry(name: name,
                                   versionMadeBy: Self.readU16(bytes, p + 4),
                                   flags: flags,
                                   method: method,
                                   modTime: Self.readU16(bytes, p + 12),
                                   modDate: Self.readU16(bytes, p + 14),
                                   crc32: crc,
                                   compressedSize: compressedSize,
                                   uncompressedSize: uncompressedSize,
                                   externalAttributes: Self.readU32(bytes, p + 38),
                                   localHeaderOffset: localOffset))
            p += 46 + nameLen + extraLen + commentLen
        }
        self.entries = parsed
    }

    func entry(named name: String) -> ZipEntry? {
        entries.first { $0.name == name }
    }

    /// 未解压的原始压缩字节（用于原样拷贝）
    func rawData(of entry: ZipEntry) throws -> Data {
        if entry.flags & 0x0001 != 0 { throw ZipError.encryptedEntry(entry.name) }
        let base = Int(entry.localHeaderOffset)
        guard base + 30 <= bytes.count, Self.readU32(bytes, base) == 0x04034b50 else {
            throw ZipError.corruptEntry(entry.name)
        }
        let nameLen = Int(Self.readU16(bytes, base + 26))
        let extraLen = Int(Self.readU16(bytes, base + 28))
        let start = base + 30 + nameLen + extraLen
        let end = start + Int(entry.compressedSize)
        guard start >= 0, end <= bytes.count else { throw ZipError.corruptEntry(entry.name) }
        return Data(bytes[start..<end])
    }

    func contents(of entry: ZipEntry) throws -> Data {
        if entry.flags & 0x0001 != 0 { throw ZipError.encryptedEntry(entry.name) }
        let raw = try rawData(of: entry)
        let out: Data
        switch entry.method {
        case 0:
            out = raw
        case 8:
            guard let inflated = ZipCompression.inflate(raw, expectedSize: Int(entry.uncompressedSize)) else {
                throw ZipError.corruptEntry(entry.name)
            }
            out = inflated
        default:
            throw ZipError.unsupportedCompression(entry.method)
        }
        guard ZipCRC32.checksum(out) == entry.crc32 else {
            throw ZipError.crcMismatch(entry.name)
        }
        return out
    }

    static func readU16(_ b: [UInt8], _ o: Int) -> UInt16 {
        UInt16(b[o]) | (UInt16(b[o + 1]) << 8)
    }

    static func readU32(_ b: [UInt8], _ o: Int) -> UInt32 {
        UInt32(b[o]) | (UInt32(b[o + 1]) << 8) | (UInt32(b[o + 2]) << 16) | (UInt32(b[o + 3]) << 24)
    }
}
```

- [ ] **Step 4: 写 `DocxReplace/Core/ZipWriter.swift` 的最小实现**

Task 4 会补全测试，这里先让 Task 3 的测试能编译通过。

```swift
import Foundation

struct ZipOutputEntry {
    var name: String
    var dosTime: UInt16
    var dosDate: UInt16
    var method: UInt16
    var crc32: UInt32
    var uncompressedSize: UInt32
    var externalAttributes: UInt32
    var compressedData: Data
}

enum ZipWriter {
    static func build(_ entries: [ZipOutputEntry]) -> Data {
        var out = Data()
        var central = Data()
        for entry in entries {
            let nameBytes = Array(entry.name.utf8)
            let offset = UInt32(out.count)
            let flags: UInt16 = nameBytes.contains { $0 >= 0x80 } ? 0x0800 : 0

            appendU32(&out, 0x04034b50)
            appendU16(&out, 20)
            appendU16(&out, flags)
            appendU16(&out, entry.method)
            appendU16(&out, entry.dosTime)
            appendU16(&out, entry.dosDate)
            appendU32(&out, entry.crc32)
            appendU32(&out, UInt32(entry.compressedData.count))
            appendU32(&out, entry.uncompressedSize)
            appendU16(&out, UInt16(nameBytes.count))
            appendU16(&out, 0)
            out.append(contentsOf: nameBytes)
            out.append(entry.compressedData)

            appendU32(&central, 0x02014b50)
            appendU16(&central, 20)
            appendU16(&central, 20)
            appendU16(&central, flags)
            appendU16(&central, entry.method)
            appendU16(&central, entry.dosTime)
            appendU16(&central, entry.dosDate)
            appendU32(&central, entry.crc32)
            appendU32(&central, UInt32(entry.compressedData.count))
            appendU32(&central, entry.uncompressedSize)
            appendU16(&central, UInt16(nameBytes.count))
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU16(&central, 0)
            appendU32(&central, entry.externalAttributes)
            appendU32(&central, offset)
            central.append(contentsOf: nameBytes)
        }
        let cdOffset = UInt32(out.count)
        out.append(central)

        appendU32(&out, 0x06054b50)
        appendU16(&out, 0)
        appendU16(&out, 0)
        appendU16(&out, UInt16(entries.count))
        appendU16(&out, UInt16(entries.count))
        appendU32(&out, UInt32(central.count))
        appendU32(&out, cdOffset)
        appendU16(&out, 0)
        return out
    }

    private static func appendU16(_ data: inout Data, _ value: UInt16) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
    }

    private static func appendU32(_ data: inout Data, _ value: UInt32) {
        data.append(UInt8(value & 0xFF))
        data.append(UInt8((value >> 8) & 0xFF))
        data.append(UInt8((value >> 16) & 0xFF))
        data.append(UInt8((value >> 24) & 0xFF))
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipArchiveTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，5 个测试全部通过（含用 `textutil` 生成的真实 docx）。

- [ ] **Step 6: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ZipArchive.swift DocxReplace/Core/ZipWriter.swift DocxReplaceTests/ZipArchiveTests.swift
git commit -m "feat: 实现 ZIP 读取与基础写出"
```

---

## Task 4: ZIP 层加固与写出完整性

**Files:**
- Modify: `DocxReplace/Core/ZipArchive.swift`（解压尺寸上限）
- Modify: `DocxReplace/Core/ZipWriter.swift`（`makeEntry` / `copyEntry` / `dosDateTime`；`build` 改为 `throws` 并防 UInt32 截断）
- Modify: `DocxReplaceTests/ZipArchiveTests.swift`

**为什么这一步要加固（Task 3 代码审查的结论，均为计划层面的缺陷）：**

1. **损坏文件头可触发失控分配**：`inflate` 以 `expectedSize + 1` 起步、失败后 ×4 递增地申请内存。中央目录若声称解压后有 `0xFFFFFFFE` 字节，会依次尝试分配 4 GB → 17 GB → 69 GB → 275 GB → 1100 GB，表现为整机卡死或被系统杀掉，而不是设计要求的「报告并跳过」。
2. **`build` 会静默写出截断偏移**：`UInt32(out.count)` 在归档总长超过 4 GB 时溢出，产出的中央目录偏移是错的 —— 正是最需要避免的「静默损坏」。

两处都必须变成**响亮的失败**。

- [ ] **Step 1: 先把 Task 3 遗留的 3 处调用改成 `try`**

`DocxReplaceTests/ZipArchiveTests.swift` 中 `testStoredEntryRoundTrip`、`testDeflatedEntryRoundTrip`、`testDetectsCRCMismatch` 三处：

```swift
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
```

改为：

```swift
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
```

- [ ] **Step 2: 追加失败测试到 `DocxReplaceTests/ZipArchiveTests.swift`**

在 `ZipArchiveTests` 类中追加（`appendLE16`/`appendLE32` 放到文件末尾、类外，用 `private`）：

```swift
    func testMakeEntryChoosesDeflateWhenSmaller() {
        let compressible = Data(String(repeating: "abcabcabc", count: 100).utf8)
        let entry = ZipWriter.makeEntry(name: "x.xml", contents: compressible, date: Date())
        XCTAssertEqual(entry.method, 8)
        XCTAssertEqual(entry.uncompressedSize, UInt32(compressible.count))
        XCTAssertLessThan(entry.compressedData.count, compressible.count)
    }

    func testMakeEntryChoosesStoredWhenDeflateLarger() {
        var bytes = [UInt8]()
        var seed: UInt32 = 999
        for _ in 0..<64 {
            seed = seed &* 1664525 &+ 1013904223
            bytes.append(UInt8(truncatingIfNeeded: seed >> 16))
        }
        let incompressible = Data(bytes)
        let entry = ZipWriter.makeEntry(name: "y.bin", contents: incompressible, date: Date())
        XCTAssertEqual(entry.method, 0)
        XCTAssertEqual(entry.compressedData, incompressible)
    }

    func testCopiedEntryKeepsRawCompressedBytes() throws {
        let url = try Self.makeRealDocx(text: "原始内容", into: tempDir)
        let original = try ZipArchive(data: Data(contentsOf: url))
        let target = try XCTUnwrap(original.entry(named: "word/document.xml"))
        let rawBefore = try original.rawData(of: target)

        let outputs = try original.entries.map { entry -> ZipOutputEntry in
            ZipWriter.copyEntry(entry, raw: try original.rawData(of: entry))
        }
        let rebuilt = try ZipArchive(data: try ZipWriter.build(outputs))
        let targetAfter = try XCTUnwrap(rebuilt.entry(named: "word/document.xml"))
        XCTAssertEqual(try rebuilt.rawData(of: targetAfter), rawBefore, "未改动条目必须字节级一致")
    }

    func testSystemUnzipAcceptsOurArchive() throws {
        let payload = Data(String(repeating: "内容 content ", count: 100).utf8)
        let entries = [
            ZipWriter.makeEntry(name: "hello.txt", contents: payload, date: Date()),
            ZipWriter.makeEntry(name: "dir/world.xml", contents: Data("<a>1</a>".utf8), date: Date()),
        ]
        let zipURL = tempDir.appendingPathComponent("out.zip")
        try ZipWriter.build(entries).write(to: zipURL)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", zipURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "系统 unzip 应能读取我们写出的 zip：\(output)")
    }

    /// 中央目录声称解压后有 4 GB，必须在申请内存之前拒绝
    func testRejectsImplausibleUncompressedSize() throws {
        let payload = Data("small".utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let entry = ZipOutputEntry(name: "bomb.xml", dosTime: 0, dosDate: 0, method: 8,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: 0xFFFFFFFE,
                                   externalAttributes: 0, compressedData: compressed)
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        let target = try XCTUnwrap(archive.entry(named: "bomb.xml"))
        XCTAssertThrowsError(try archive.contents(of: target)) { error in
            XCTAssertEqual(error as? ZipError, .implausibleSize("bomb.xml"))
        }
    }

    func testBuildRejectsOversizedEntryCount() {
        let entries = (0...Int(UInt16.max)).map { index in
            ZipOutputEntry(name: "f\(index)", dosTime: 0, dosDate: 0, method: 0, crc32: 0,
                           uncompressedSize: 0, externalAttributes: 0, compressedData: Data())
        }
        XCTAssertThrowsError(try ZipWriter.build(entries)) { error in
            XCTAssertEqual(error as? ZipError, .archiveTooLarge)
        }
    }

    func testRejectsUnsupportedCompressionMethod() throws {
        let entry = ZipOutputEntry(name: "m12.bin", dosTime: 0, dosDate: 0, method: 12, crc32: 0,
                                   uncompressedSize: 0, externalAttributes: 0, compressedData: Data([1, 2, 3]))
        let archive = try ZipArchive(data: try ZipWriter.build([entry]))
        let target = try XCTUnwrap(archive.entry(named: "m12.bin"))
        XCTAssertThrowsError(try archive.contents(of: target)) { error in
            XCTAssertEqual(error as? ZipError, .unsupportedCompression(12))
        }
    }

    func testRejectsEncryptedEntry() throws {
        let payload = Data("secret".utf8)
        // 手工置位加密标志（bit 0）
        var raw = try ZipWriter.build([ZipOutputEntry(name: "e.txt", dosTime: 0, dosDate: 0, method: 0,
                                                      crc32: ZipCRC32.checksum(payload),
                                                      uncompressedSize: UInt32(payload.count),
                                                      externalAttributes: 0, compressedData: payload)])
        raw[6] |= 0x01
        // 中央目录首条目的 flags 字节。不能用 raw.count - 22 + 8 —— 那是 EOCD 的条目数字段。
        // EOCD 位于最后 22 字节，其 +16 处记录中央目录偏移，偏移 +8 才是首条目的 flags。
        let cdOffset = Int(ZipArchive.readU32([UInt8](raw), raw.count - 22 + 16))
        raw[cdOffset + 8] |= 0x01
        let archive = try ZipArchive(data: raw)
        let target = try XCTUnwrap(archive.entry(named: "e.txt"))
        XCTAssertThrowsError(try archive.contents(of: target)) { error in
            XCTAssertEqual(error as? ZipError, .encryptedEntry("e.txt"))
        }
    }

    func testEmptyArchiveHasNoEntries() throws {
        let archive = try ZipArchive(data: try ZipWriter.build([]))
        XCTAssertTrue(archive.entries.isEmpty)
        XCTAssertNil(archive.entry(named: "anything"))
    }

    /// 手工构造带 data descriptor（标志位 3）的归档：本地头里的 crc/尺寸为 0，
    /// 真实值写在数据之后的描述符里，中央目录才是权威来源
    func testReadsEntryWithDataDescriptor() throws {
        let payload = Data("descriptor payload 内容".utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let crc = ZipCRC32.checksum(payload)
        let name = Array("dd.txt".utf8)

        var out = Data()
        appendLE32(&out, 0x04034b50)
        appendLE16(&out, 20)
        appendLE16(&out, 0x0008)
        appendLE16(&out, 8)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE32(&out, 0)
        appendLE32(&out, 0); appendLE32(&out, 0)
        appendLE16(&out, UInt16(name.count)); appendLE16(&out, 0)
        out.append(contentsOf: name)
        out.append(compressed)
        appendLE32(&out, 0x08074b50)
        appendLE32(&out, crc)
        appendLE32(&out, UInt32(compressed.count))
        appendLE32(&out, UInt32(payload.count))

        let cdOffset = UInt32(out.count)
        appendLE32(&out, 0x02014b50)
        appendLE16(&out, 20); appendLE16(&out, 20)
        appendLE16(&out, 0x0008)
        appendLE16(&out, 8)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE32(&out, crc)
        appendLE32(&out, UInt32(compressed.count))
        appendLE32(&out, UInt32(payload.count))
        appendLE16(&out, UInt16(name.count)); appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE32(&out, 0)
        appendLE32(&out, 0)
        out.append(contentsOf: name)
        let cdSize = UInt32(out.count) - cdOffset

        appendLE32(&out, 0x06054b50)
        appendLE16(&out, 0); appendLE16(&out, 0)
        appendLE16(&out, 1); appendLE16(&out, 1)
        appendLE32(&out, cdSize); appendLE32(&out, cdOffset)
        appendLE16(&out, 0)

        let archive = try ZipArchive(data: out)
        let entry = try XCTUnwrap(archive.entry(named: "dd.txt"))
        XCTAssertEqual(try archive.contents(of: entry), payload)
        XCTAssertEqual(try archive.rawData(of: entry), compressed, "描述符不得混进原始压缩字节")
    }
}

private func appendLE16(_ data: inout Data, _ value: UInt16) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
}

private func appendLE32(_ data: inout Data, _ value: UInt32) {
    data.append(UInt8(value & 0xFF))
    data.append(UInt8((value >> 8) & 0xFF))
    data.append(UInt8((value >> 16) & 0xFF))
    data.append(UInt8((value >> 24) & 0xFF))
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipArchiveTests 2>&1 | tail -20
```

Expected: 编译失败，`type 'ZipWriter' has no member 'makeEntry'` / `'copyEntry'`，以及 `no member 'archiveTooLarge'`。

- [ ] **Step 4: 改 `DocxReplace/Core/ZipArchive.swift`**

在 `ZipError` 中加两个 case，并补上对应的 `message`：

```swift
    case implausibleSize(String)
    case archiveTooLarge
```

```swift
        case .implausibleSize(let name): return "部件尺寸异常，已跳过（\(name)）"
        case .archiveTooLarge: return "文档过大，超出 ZIP 格式上限"
```

在 `contents(of:)` 的 `case 8:` 分支里，**在调用 inflate 之前**加上限判断：

```swift
        case 8:
            guard Int(entry.uncompressedSize) <= Self.inflateLimit(compressedSize: entry.compressedSize) else {
                throw ZipError.implausibleSize(entry.name)
            }
            guard let inflated = ZipCompression.inflate(raw, expectedSize: Int(entry.uncompressedSize)) else {
                throw ZipError.corruptEntry(entry.name)
            }
            out = inflated
```

并在 `ZipArchive` 内加一个私有静态方法：

```swift
    /// 解压尺寸上限：至少 64 MiB，或压缩数据的 256 倍。
    /// 防止损坏或恶意的 uncompressedSize 触发失控的内存分配。
    private static func inflateLimit(compressedSize: UInt32) -> Int {
        max(64 * 1024 * 1024, Int(compressedSize) * 256)
    }
```

- [ ] **Step 5: 改 `DocxReplace/Core/ZipWriter.swift`**

把 `build` 改成 `throws` 并在三处加护栏（入口的条目数、每个条目的名字长度、每次偏移计算前）：

```swift
    static func build(_ entries: [ZipOutputEntry]) throws -> Data {
        guard entries.count <= Int(UInt16.max) else { throw ZipError.archiveTooLarge }
        var out = Data()
        var central = Data()
        for entry in entries {
            guard out.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
            let nameBytes = Array(entry.name.utf8)
            guard nameBytes.count <= Int(UInt16.max) else { throw ZipError.archiveTooLarge }
            let offset = UInt32(out.count)
            let flags: UInt16 = nameBytes.contains { $0 >= 0x80 } ? 0x0800 : 0
            // ...（中间写本地头与数据的部分保持不变）...
        }
        guard out.count < Int(UInt32.max) else { throw ZipError.archiveTooLarge }
        let cdOffset = UInt32(out.count)
        // ...（其余保持不变）...
    }
```

再在 `ZipWriter` 内追加：

```swift
    /// 用未压缩内容构造条目，自动选择 deflate 或 stored
    static func makeEntry(name: String, contents: Data, date: Date,
                          externalAttributes: UInt32 = 0) -> ZipOutputEntry {
        let (dosTime, dosDate) = dosDateTime(from: date)
        let crc = ZipCRC32.checksum(contents)
        if let deflated = ZipCompression.deflate(contents), deflated.count < contents.count, !contents.isEmpty {
            return ZipOutputEntry(name: name, dosTime: dosTime, dosDate: dosDate, method: 8,
                                  crc32: crc, uncompressedSize: UInt32(contents.count),
                                  externalAttributes: externalAttributes, compressedData: deflated)
        }
        return ZipOutputEntry(name: name, dosTime: dosTime, dosDate: dosDate, method: 0,
                              crc32: crc, uncompressedSize: UInt32(contents.count),
                              externalAttributes: externalAttributes, compressedData: contents)
    }

    /// 原样拷贝一个条目（保留原始压缩字节与元数据）
    static func copyEntry(_ entry: ZipEntry, raw: Data) -> ZipOutputEntry {
        ZipOutputEntry(name: entry.name, dosTime: entry.modTime, dosDate: entry.modDate,
                       method: entry.method, crc32: entry.crc32,
                       uncompressedSize: entry.uncompressedSize,
                       externalAttributes: entry.externalAttributes, compressedData: raw)
    }

    static func dosDateTime(from date: Date) -> (time: UInt16, date: UInt16) {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let c = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max(1980, c.year ?? 1980)
        let dosDate = UInt16((((year - 1980) & 0x7F) << 9) | ((c.month ?? 1) << 5) | (c.day ?? 1))
        let dosTime = UInt16(((c.hour ?? 0) << 11) | ((c.minute ?? 0) << 5) | ((c.second ?? 0) / 2))
        return (dosTime, dosDate)
    }
```

- [ ] **Step 6: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipArchiveTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，15 个测试全部通过（其中 `testSystemUnzipAcceptsOurArchive` 证明我们产出的 ZIP 能被系统工具独立校验，`testReadsEntryWithDataDescriptor` 证明带描述符的归档能正确读取）。

- [ ] **Step 7: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ZipArchive.swift DocxReplace/Core/ZipWriter.swift DocxReplaceTests/ZipArchiveTests.swift
git commit -m "feat: ZIP 写出完整性 + 两处安全护栏（解压尺寸上限、归档大小溢出）"
```

---

## Task 5: 定位 `w:t` 元素

**Files:**
- Create: `DocxReplace/Core/XmlTextLocator.swift`
- Test: `DocxReplaceTests/XmlTextLocatorTests.swift`

- [ ] **Step 1: 写失败测试 `DocxReplaceTests/XmlTextLocatorTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class XmlTextLocatorTests: XCTestCase {
    private func nodes(_ xml: String) -> [XmlTextLocator.TextNode] {
        XmlTextLocator.findTextNodes(in: [UInt8](xml.utf8))
    }

    func testFindsSimpleTextNodes() {
        let xml = "<w:p><w:r><w:t>你好</w:t></w:r><w:r><w:t>世界</w:t></w:r></w:p>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 2)
        XCTAssertEqual(result[0].text, "你好")
        XCTAssertEqual(result[1].text, "世界")
        XCTAssertFalse(result[0].isSelfClosing)
    }

    func testTextPreservesSurroundingPunctuation() {
        let xml = "<w:t>,。！</w:t>"
        XCTAssertEqual(nodes(xml)[0].text, ",。！")
    }

    func testDecodesEntities() {
        let xml = "<w:t>a &amp; b &lt;c&gt; &quot;d&quot; &#65;</w:t>"
        XCTAssertEqual(nodes(xml)[0].text, "a & b <c> \"d\" A")
    }

    func testDetectsPreserveSpaceAttribute() {
        let yes = nodes("<w:t xml:space=\"preserve\"> x </w:t>")
        XCTAssertTrue(yes[0].hasPreserveSpace)
        let no = nodes("<w:t> x </w:t>")
        XCTAssertFalse(no[0].hasPreserveSpace)
    }

    func testHandlesSelfClosingTag() {
        let result = nodes("<w:p><w:r><w:t/></w:r></w:p>")
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].isSelfClosing)
        XCTAssertEqual(result[0].text, "")
    }

    func testIgnoresCommentsAndCDATA() {
        let xml = """
        <!-- <w:t>注释里的假元素</w:t> -->
        <w:t>真元素</w:t>
        <![CDATA[ <w:t>CDATA 里的假元素</w:t> ]]>
        """
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "真元素")
    }

    func testIgnoresSimilarElementNames() {
        let xml = "<w:tbl><w:tab/><w:tr><w:tc><w:t>唯一</w:t></w:tc></w:tr></w:tbl>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "唯一")
    }

    func testHandlesAttributesWithGreaterThanSign() {
        let xml = "<w:t w:foo=\"a&gt;b\">文字</w:t>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "文字")
    }

    func testParagraphIndexRangePointsAtInnerText() {
        let xml = "<w:t>abc</w:t>"
        let bytes = [UInt8](xml.utf8)
        let node = nodes(xml)[0]
        XCTAssertEqual(String(decoding: bytes[node.innerStart..<node.innerEnd], as: UTF8.self), "abc")
        XCTAssertEqual(String(decoding: bytes[node.elementStart..<node.elementEnd], as: UTF8.self), xml)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/XmlTextLocatorTests 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'XmlTextLocator' in scope`。

- [ ] **Step 3: 写 `DocxReplace/Core/XmlTextLocator.swift`**

```swift
import Foundation

/// 在原始 XML 字节上定位 `w:t` 元素。只在字节层面工作，
/// 因为 UTF-8 的多字节序列不含 ASCII 字节，搜索 ASCII 标记是安全的。
enum XmlTextLocator {
    struct TextNode: Equatable {
        var elementStart: Int
        var elementEnd: Int
        var innerStart: Int      // 自闭合元素为 -1
        var innerEnd: Int
        var isSelfClosing: Bool
        var hasPreserveSpace: Bool
        var attributes: String   // "<w:t" 之后到 ">" 或 "/" 之前的原文（含前导空白）
        var text: String         // 已解码实体的文字
    }

    static func findTextNodes(in xml: [UInt8]) -> [TextNode] {
        var nodes: [TextNode] = []
        var i = 0
        let n = xml.count
        while i < n {
            guard xml[i] == 0x3C else { i += 1; continue }   // '<'

            if matches(xml, at: i, utf8: "<!--") {
                i = skip(xml, from: i + 4, until: "-->")
                continue
            }
            if matches(xml, at: i, utf8: "<![CDATA[") {
                i = skip(xml, from: i + 9, until: "]]>")
                continue
            }
            if matches(xml, at: i, utf8: "<?") {
                i = skip(xml, from: i + 2, until: "?>")
                continue
            }
            guard isTextElementStart(xml, at: i) else { i += 1; continue }

            let tagEnd = findTagEnd(xml, from: i)
            guard tagEnd < n else { break }

            var p = tagEnd - 1
            while p > i, isWhitespace(xml[p]) { p -= 1 }
            let isSelfClosing = xml[p] == 0x2F   // '/'
            let attrStart = i + 4
            let attrEnd = isSelfClosing ? max(attrStart, p) : tagEnd
            let attributes = String(decoding: xml[attrStart..<max(attrStart, attrEnd)], as: UTF8.self)
            let hasPreserve = attributes.contains("xml:space") && attributes.contains("preserve")

            if isSelfClosing {
                nodes.append(TextNode(elementStart: i, elementEnd: tagEnd + 1,
                                      innerStart: -1, innerEnd: -1,
                                      isSelfClosing: true, hasPreserveSpace: hasPreserve,
                                      attributes: attributes, text: ""))
                i = tagEnd + 1
            } else {
                let innerStart = tagEnd + 1
                guard let closeStart = find(xml, from: innerStart, utf8: "</w:t") else { break }
                let closeEnd = findTagEnd(xml, from: closeStart)
                guard closeEnd < n else { break }
                let text = decodeText(Array(xml[innerStart..<closeStart]))
                nodes.append(TextNode(elementStart: i, elementEnd: closeEnd + 1,
                                      innerStart: innerStart, innerEnd: closeStart,
                                      isSelfClosing: false, hasPreserveSpace: hasPreserve,
                                      attributes: attributes, text: text))
                i = closeEnd + 1
            }
        }
        return nodes
    }

    // MARK: - 字节工具

    private static func matches(_ xml: [UInt8], at index: Int, utf8 pattern: String) -> Bool {
        let p = [UInt8](pattern.utf8)
        guard index + p.count <= xml.count else { return false }
        for k in 0..<p.count where xml[index + k] != p[k] { return false }
        return true
    }

    private static func find(_ xml: [UInt8], from index: Int, utf8 pattern: String) -> Int? {
        let p = [UInt8](pattern.utf8)
        guard !p.isEmpty, index >= 0 else { return nil }
        var i = index
        while i + p.count <= xml.count {
            if xml[i] == p[0], matches(xml, at: i, utf8: pattern) { return i }
            i += 1
        }
        return nil
    }

    /// 找到标签的结束 '>'，跳过属性值里的引号内容
    private static func findTagEnd(_ xml: [UInt8], from index: Int) -> Int {
        var i = index
        var quote: UInt8? = nil
        while i < xml.count {
            let b = xml[i]
            if let q = quote {
                if b == q { quote = nil }
            } else if b == 0x22 || b == 0x27 {
                quote = b
            } else if b == 0x3E {
                return i
            }
            i += 1
        }
        return xml.count
    }

    private static func isWhitespace(_ b: UInt8) -> Bool {
        b == 0x20 || b == 0x09 || b == 0x0A || b == 0x0D
    }

    /// 判断位置 i 是否是 "<w:t" 且后面紧跟空白、'>' 或 '/'（排除 <w:tab>/<w:tbl> 等）
    private static func isTextElementStart(_ xml: [UInt8], at index: Int) -> Bool {
        guard matches(xml, at: index, utf8: "<w:t") else { return false }
        let next = index + 4
        guard next < xml.count else { return false }
        let b = xml[next]
        return isWhitespace(b) || b == 0x3E || b == 0x2F
    }

    private static func skip(_ xml: [UInt8], from index: Int, until pattern: String) -> Int {
        if let found = find(xml, from: index, utf8: pattern) {
            return found + pattern.utf8.count
        }
        return xml.count
    }

    private static func decodeText(_ bytes: [UInt8]) -> String {
        let s = String(decoding: bytes, as: UTF8.self)
        if s.hasPrefix("<![CDATA[") && s.hasSuffix("]]>") {
            return String(s.dropFirst(9).dropLast(3))
        }
        return unescape(s)
    }

    // MARK: - 实体

    static func unescape(_ s: String) -> String {
        guard s.contains("&") else { return s }
        let chars = Array(s)
        var out = ""
        out.reserveCapacity(chars.count)
        var i = 0
        while i < chars.count {
            guard chars[i] == "&", let semi = chars[i...].firstIndex(of: ";"), semi - i <= 12 else {
                out.append(chars[i]); i += 1; continue
            }
            let entity = String(chars[(i + 1)..<semi])
            var handled = true
            switch entity {
            case "amp": out.append("&")
            case "lt": out.append("<")
            case "gt": out.append(">")
            case "quot": out.append("\"")
            case "apos": out.append("'")
            default:
                if entity.hasPrefix("#x") || entity.hasPrefix("#X"),
                   let v = UInt32(entity.dropFirst(2), radix: 16), let scalar = UnicodeScalar(v) {
                    out.unicodeScalars.append(scalar)
                } else if entity.hasPrefix("#"), let v = UInt32(entity.dropFirst()),
                          let scalar = UnicodeScalar(v) {
                    out.unicodeScalars.append(scalar)
                } else {
                    handled = false
                }
            }
            if handled { i = semi + 1 } else { out.append(chars[i]); i += 1 }
        }
        return out
    }

    static func escape(_ s: String) -> String {
        var out = ""
        out.reserveCapacity(s.count)
        for ch in s {
            switch ch {
            case "&": out += "&amp;"
            case "<": out += "&lt;"
            case ">": out += "&gt;"
            default: out.append(ch)
            }
        }
        return out
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/XmlTextLocatorTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，9 个测试全部通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/XmlTextLocator.swift DocxReplaceTests/XmlTextLocatorTests.swift
git commit -m "feat: 实现 w:t 元素的字节级定位与实体编解码"
```

---

## Task 6: 改写 `w:t` 文字

**Files:**
- Modify: `DocxReplace/Core/XmlTextLocator.swift`
- Modify: `DocxReplaceTests/XmlTextLocatorTests.swift`

- [ ] **Step 1: 追加失败测试到 `DocxReplaceTests/XmlTextLocatorTests.swift`**

```swift
    private func rebuild(_ xml: String, edits: [Int: String]) -> String {
        String(decoding: XmlTextLocator.rebuild(xml: [UInt8](xml.utf8), edits: edits), as: UTF8.self)
    }

    func testRebuildReplacesOnlyTargetText() {
        let xml = "<w:p><w:r><w:t>北京公司</w:t></w:r></w:p>"
        let out = rebuild(xml, edits: [0: "上海集团"])
        XCTAssertEqual(out, "<w:p><w:r><w:t>上海集团</w:t></w:r></w:p>")
    }

    func testRebuildKeepsRunPropertiesIntact() {
        let xml = "<w:p><w:r><w:rPr><w:b/><w:color w:val=\"FF0000\"/></w:rPr><w:t>旧</w:t></w:r></w:p>"
        let out = rebuild(xml, edits: [0: "新"])
        XCTAssertEqual(out, "<w:p><w:r><w:rPr><w:b/><w:color w:val=\"FF0000\"/></w:rPr><w:t>新</w:t></w:r></w:p>")
    }

    func testRebuildAddsPreserveSpaceWhenNeeded() {
        let out = rebuild("<w:t>abc</w:t>", edits: [0: " abc "])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> abc </w:t>")
    }

    func testRebuildDoesNotDuplicatePreserveSpace() {
        let out = rebuild("<w:t xml:space=\"preserve\">abc</w:t>", edits: [0: " abc "])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> abc </w:t>")
    }

    func testRebuildEscapesEntities() {
        let out = rebuild("<w:t>x</w:t>", edits: [0: "a & b <c>"])
        XCTAssertEqual(out, "<w:t>a &amp; b &lt;c&gt;</w:t>")
    }

    func testRebuildConvertsSelfClosingTag() {
        let out = rebuild("<w:p><w:r><w:t/></w:r></w:p>", edits: [0: "填入"])
        XCTAssertEqual(out, "<w:p><w:r><w:t>填入</w:t></w:r></w:p>")
    }

    func testRebuildCanEmptyText() {
        let out = rebuild("<w:t>要删掉</w:t>", edits: [0: ""])
        XCTAssertEqual(out, "<w:t></w:t>")
    }

    func testRebuildHandlesMultipleEditsAndAttributeOrder() {
        let xml = "<w:r><w:t xml:space=\"preserve\">A</w:t></w:r><w:r><w:t>B</w:t></w:r>"
        let out = rebuild(xml, edits: [0: "AAA", 1: "BBB"])
        XCTAssertEqual(out, "<w:r><w:t xml:space=\"preserve\">AAA</w:t></w:r><w:r><w:t>BBB</w:t></w:r>")
    }

    func testRebuildLeavesOtherElementsAlone() {
        let xml = "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t>旧</w:t></w:r></w:p>"
        let out = rebuild(xml, edits: [0: "新"])
        XCTAssertEqual(out, "<w:p><w:pPr><w:jc w:val=\"center\"/></w:pPr><w:r><w:t>新</w:t></w:r></w:p>")
    }

    func testRebuildWithNoEditsReturnsInput() {
        let xml = "<w:t>原样</w:t>"
        XCTAssertEqual(rebuild(xml, edits: [:]), xml)
    }

    func testIgnoresCloseTagInsideCDATA() {
        let xml = "<w:t><![CDATA[a</w:t>b]]></w:t>"
        let result = nodes(xml)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].text, "a</w:t>b")
        let bytes = [UInt8](xml.utf8)
        XCTAssertEqual(String(decoding: bytes[result[0].innerStart..<result[0].innerEnd], as: UTF8.self),
                       "<![CDATA[a</w:t>b]]>")
    }

    func testDecodesMixedCDATAContent() {
        XCTAssertEqual(nodes("<w:t>pre<![CDATA[<&]]>post</w:t>")[0].text, "pre<&post")
    }
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/XmlTextLocatorTests 2>&1 | tail -20
```

Expected: 编译失败，`type 'XmlTextLocator' has no member 'rebuild'`。

- [ ] **Step 3: 在 `DocxReplace/Core/XmlTextLocator.swift` 中追加 `rebuild`**

加在 `findTextNodes` 之后：

```swift
    /// 按 w:t 的出现序号应用新文字，返回新的 XML 字节。
    /// 只重建被编辑的 `w:t` 元素，其余字节原样拼接。
    static func rebuild(xml: [UInt8], edits: [Int: String]) -> [UInt8] {
        guard !edits.isEmpty else { return xml }
        let nodes = findTextNodes(in: xml)
        let targets: [(node: TextNode, newText: String)] = edits
            .compactMap { index, newText in
                guard index >= 0, index < nodes.count else { return nil }
                return (nodes[index], newText)
            }
            .sorted { $0.node.elementStart < $1.node.elementStart }

        var out = Data()
        var cursor = 0
        for target in targets {
            guard target.node.elementStart >= cursor else { continue }
            out.append(contentsOf: xml[cursor..<target.node.elementStart])
            var attributes = target.node.attributes
            if needsPreserveSpace(target.newText), !target.node.hasPreserveSpace {
                attributes += " xml:space=\"preserve\""
            }
            out.append(contentsOf: Array("<w:t\(attributes)>\(escape(target.newText))</w:t>".utf8))
            cursor = target.node.elementEnd
        }
        out.append(contentsOf: xml[cursor...])
        return [UInt8](out)
    }

    private static func needsPreserveSpace(_ text: String) -> Bool {
        guard let first = text.first, let last = text.last else { return false }
        return isSpace(first) || isSpace(last)
    }

    private static func isSpace(_ ch: Character) -> Bool {
        ch == " " || ch == "\t" || ch == "\n" || ch == "\r"
    }
```

- [ ] **Step 4: 顺带修掉 CDATA 内含 `</w:t` 的解析缺陷**

Task 5 的代码审查发现：`<w:t><![CDATA[a</w:t>b]]></w:t>` 这种输入下，第 57 行的
`find(xml, from: innerStart, utf8: "</w:t")` 会把 CDATA 里的字节当成结束标签，
导致 `innerEnd` 偏小、`text` 错误。Task 9 的「DOM 节点数 vs 原始节点数」校验**拦不住它**（两边都是 1 个节点），
而 Task 6 的 `rebuild` 按 `elementStart..<elementEnd` 重新生成整个元素，会写出**无法解析的 XML**。
真实 Word/WPS/Google Docs 都不会产出这种输入，但既然这个文件本轮就要改，顺手堵上。

把 `findTextNodes` 中查找结束标签的那一行：

```swift
                guard let closeStart = find(xml, from: innerStart, utf8: "</w:t") else { break }
```

改为调用新的单趟扫描函数：

```swift
                guard let closeStart = findCloseTag(xml, from: innerStart) else { break }
```

在 `findTextNodes` 之后新增这个函数（单趟扫描，内部跳过 CDATA；不要写成对每个元素再扫一遍 CDATA，
那会退化成 O(n²)）：

```swift
    /// 找到 w:t 的结束标签位置，单趟扫描并跳过内部的 CDATA 段（其中可能含 "</w:t" 字节）
    private static func findCloseTag(_ xml: [UInt8], from index: Int) -> Int? {
        var i = index
        while i < xml.count {
            if xml[i] == 0x3C {                                  // '<'
                if matches(xml, at: i, utf8: "</w:t") { return i }
                if matches(xml, at: i, utf8: "<![CDATA[") {
                    guard let end = find(xml, from: i + 9, utf8: "]]>") else { return nil }
                    i = end + 3
                    continue
                }
            }
            i += 1
        }
        return nil
    }
```

再把 `decodeText` 换成逐段解码版本（普通文本走实体解码，CDATA 段原样保留），
替换掉原来「只有整段被 CDATA 包裹才剥壳」的写法：

```swift
    private static func decodeText(_ bytes: [UInt8]) -> String {
        var out = ""
        var i = 0
        while i < bytes.count {
            if matches(bytes, at: i, utf8: "<![CDATA[") {
                guard let end = find(bytes, from: i + 9, utf8: "]]>") else {
                    out += String(decoding: bytes[i...], as: UTF8.self)
                    break
                }
                out += String(decoding: bytes[(i + 9)..<end], as: UTF8.self)
                i = end + 3
            } else if let next = find(bytes, from: i, utf8: "<![CDATA[") {
                out += unescape(String(decoding: bytes[i..<next], as: UTF8.self))
                i = next
            } else {
                out += unescape(String(decoding: bytes[i...], as: UTF8.self))
                break
            }
        }
        return out
    }
```

最后把 `TextNode.attributes` 的注释补全（现有注释只说「含前导空白」，实际尾部空白也保留，
而 `rebuild` 会原样拼回去，必须有说明，免得后人「顺手」裁剪）：

```swift
        var attributes: String   // "<w:t" 之后、">" 或 "/" 之前的原文，首尾空白均原样保留，rebuild 会原样拼回
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/XmlTextLocatorTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，21 个测试全部通过。

- [ ] **Step 6: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/XmlTextLocator.swift DocxReplaceTests/XmlTextLocatorTests.swift
git commit -m "feat: w:t 文字改写，含 xml:space 补写与实体转义；修正 CDATA 内结束标签误判"
```

---

## Task 6b: `rebuild` 接口加固（Task 6 代码审查结论）

**Files:**
- Modify: `DocxReplace/Core/XmlTextLocator.swift`
- Modify: `DocxReplaceTests/XmlTextLocatorTests.swift`

背景：审查确认当前实现不会损坏文档，但发现四处「静默出错」的可能。它们在 Task 10 依赖 `rebuild` 之前修最便宜。

- **序号越界被静默丢弃**：`rebuild` 用 `compactMap` 丢掉越界序号却不告诉调用方。一旦序号错位，会「只改了一部分，却按全部成功上报」——正是本项目最不能接受的静默错误。
- **`escape` 不处理 `\r`**：XML 解析器会把裸 `\r` 规范化为 `\n`，替换文字的语义会悄悄改变。
- **`xml:space="default"` 会写出重复属性**：检测逻辑只认 `preserve`，遇到 `default` 会再追加一个 `xml:space`，结果是 `XMLDocument` 拒绝的非法 XML。
- **首尾空白判断用的是 `Character`**：`" " + U+0301`（空格后跟组合字符）会被当成一个字素簇，导致漏写 `xml:space="preserve"`，Word 可能吃掉前导空格。

**Step 1: 追加失败测试到 `XmlTextLocatorTests.swift`**

```swift
    func testRebuildReportsAppliedCountAndDropsBadKeys() {
        let xml = "<w:t>a</w:t><w:t>b</w:t>"
        let result = XmlTextLocator.rebuild(xml: [UInt8](xml.utf8), edits: [0: "X", 99: "Y", -1: "Z"])
        XCTAssertEqual(result.applied, 1)
        XCTAssertEqual(String(decoding: result.xml, as: UTF8.self), "<w:t>X</w:t><w:t>b</w:t>")
    }

    func testRebuildPreservesOtherAttributesOnEditedElement() {
        let out = rebuild("<w:t w:rsidR=\"00AB12\">旧</w:t>", edits: [0: "新"])
        XCTAssertEqual(out, "<w:t w:rsidR=\"00AB12\">新</w:t>")
    }

    func testRebuildSelfClosingWithExistingAttribute() {
        let out = rebuild("<w:t xml:space=\"preserve\"/>", edits: [0: " x"])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> x</w:t>")
    }

    func testRebuildDoesNotDuplicateExplicitDefaultSpace() {
        let out = rebuild("<w:t xml:space=\"default\">abc</w:t>", edits: [0: " abc "])
        XCTAssertEqual(out, "<w:t xml:space=\"default\"> abc </w:t>")
    }

    func testRebuildEscapesCarriageReturn() {
        XCTAssertEqual(rebuild("<w:t>x</w:t>", edits: [0: "a\rb"]), "<w:t>a&#13;b</w:t>")
    }

    func testLeadingSpaceBeforeCombiningMarkGetsPreserve() {
        // 前导空格后紧跟组合字符：按 Character 判断会误判，必须按 UnicodeScalar
        let out = rebuild("<w:t>x</w:t>", edits: [0: " \u{0301}abc"])
        XCTAssertEqual(out, "<w:t xml:space=\"preserve\"> \u{0301}abc</w:t>")
    }
```

注意：类内的 `private func rebuild(_:edits:) -> String` 辅助方法要适配新的返回类型（取 `.xml`）。

**Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/XmlTextLocatorTests 2>&1 | tail -20
```

**Step 3: 改 `DocxReplace/Core/XmlTextLocator.swift`**

（a）`rebuild` 返回已应用数量，并在文档注释里写明序号不变量：

```swift
    /// 按 w:t 的出现序号应用新文字，返回新的 XML 字节与**实际应用**的编辑数。
    /// 只重建被编辑的 `w:t` 元素，其余字节原样拼接。
    ///
    /// 序号不变量：序号 i 表示文档顺序中的第 i 个 `w:t`。调用方必须按同样的文档顺序枚举，
    /// 否则会改错元素。调用方还应断言 `applied == edits.count`（越界序号会被丢弃，不报错）。
    static func rebuild(xml: [UInt8], edits: [Int: String]) -> (xml: [UInt8], applied: Int) {
        guard !edits.isEmpty else { return (xml, 0) }
        let nodes = findTextNodes(in: xml)
        let targets: [(node: TextNode, newText: String)] = edits
            .compactMap { index, newText in
                guard index >= 0, index < nodes.count else { return nil }
                return (nodes[index], newText)
            }
            .sorted { $0.node.elementStart < $1.node.elementStart }

        var out = Data()
        var cursor = 0
        for target in targets {
            guard target.node.elementStart >= cursor else { continue }
            out.append(contentsOf: xml[cursor..<target.node.elementStart])
            var attributes = target.node.attributes
            if needsPreserveSpace(target.newText), !target.node.hasSpaceAttribute {
                attributes += " xml:space=\"preserve\""
            }
            out.append(contentsOf: Array("<w:t\(attributes)>\(escape(target.newText))</w:t>".utf8))
            cursor = target.node.elementEnd
        }
        out.append(contentsOf: xml[cursor...])
        return ([UInt8](out), targets.count)
    }
```

（b）`TextNode.hasPreserveSpace` 改名为 `hasSpaceAttribute`，语义变为「开标签里存在 `xml:space` 属性」：

```swift
        var hasSpaceAttribute: Bool   // 开标签里存在 xml:space 属性（任何取值）
```

`findTextNodes` 中对应判断改为：

```swift
            let hasSpace = attributes.contains("xml:space")
```

同时把已有的 `testDetectsPreserveSpaceAttribute` 里的字段名一并改掉（断言值不变）。

（c）`escape` 增加 `\r`：

```swift
            case "\r": out += "&#13;"
```

（d）首尾空白按 UnicodeScalar 判断：

```swift
    private static func needsPreserveSpace(_ text: String) -> Bool {
        guard let first = text.unicodeScalars.first, let last = text.unicodeScalars.last else { return false }
        return isSpaceScalar(first) || isSpaceScalar(last)
    }

    // 注意：NBSP(U+00A0) 不算空白 —— Word 不会裁剪它，加 preserve 反而多余
    private static func isSpaceScalar(_ s: UnicodeScalar) -> Bool {
        s == " " || s == "\t" || s == "\n" || s == "\r"
    }
```

（e）把重复出现 4 次的 CDATA 字面量与模式串提成 `private static let`（审查实测可省一半扫描时间）：

```swift
    private static let cdataOpen = [UInt8]("<![CDATA[".utf8])
    private static let cdataClose = [UInt8]("]]>".utf8)
    private static let textOpen = [UInt8]("<w:t".utf8)
    private static let textClose = [UInt8]("</w:t".utf8)
    private static let commentOpen = [UInt8]("<!--".utf8)
    private static let commentClose = [UInt8]("-->".utf8)
    private static let piOpen = [UInt8]("<?".utf8)
    private static let piClose = [UInt8]("?>".utf8)
```

并给 `matches`/`find` 增加接受 `[UInt8]` 模式的重载，调用点改用模式数组（保留接受 `String` 的版本以免大改，但热路径用数组）。若这一步让改动面失控，可以只做 (a)–(d)，把 (e) 留到 Task 15 的收尾优化。

**Step 4: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，全量 50 个测试通过（44 + 6 新增）。

**Step 5: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/XmlTextLocator.swift DocxReplaceTests/XmlTextLocatorTests.swift
git commit -m "fix: rebuild 返回实际应用数、修 xml:space 重复属性与首尾空白误判"
```

---

## Task 7: 纯文本查找与计数

**Files:**
- Create: `DocxReplace/Core/ParagraphMatcher.swift`
- Test: `DocxReplaceTests/ParagraphMatcherTests.swift`

- [ ] **Step 1: 写失败测试 `DocxReplaceTests/ParagraphMatcherTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class ParagraphMatcherTests: XCTestCase {
    private let options = ReplaceOptions()

    func testCountsAcrossSplitRuns() {
        let texts = ["北", "京公", "司"]
        XCTAssertEqual(ParagraphMatcher.countMatches(in: texts, find: "北京公司", options: options), 1)
    }

    func testCountsMultipleOccurrencesInOneRun() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["abcabc"], find: "abc", options: options), 2)
    }

    func testNonOverlappingMatches() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["aaaa"], find: "aa", options: options), 2)
    }

    func testCaseInsensitiveByDefault() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["Hello World"], find: "hello", options: options), 1)
    }

    func testCaseSensitiveOption() {
        let opts = ReplaceOptions(caseSensitive: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["Hello World"], find: "hello", options: opts), 0)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["Hello World"], find: "Hello", options: opts), 1)
    }

    func testWholeWordOption() {
        let opts = ReplaceOptions(wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["cat category"], find: "cat", options: opts), 1)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["a cat."], find: "cat", options: opts), 1)
    }

    func testEmptyFindTextMatchesNothing() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["abc"], find: "", options: options), 0)
    }

    func testNoMatchReturnsZero() {
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["abc"], find: "xyz", options: options), 0)
    }

    func testCountsAcrossManyRunsAndSegments() {
        let texts = ["公司", "名称", "是", "北京", "公司"]
        XCTAssertEqual(ParagraphMatcher.countMatches(in: texts, find: "公司", options: options), 2)
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ParagraphMatcherTests 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'ParagraphMatcher' in scope`。

- [ ] **Step 3: 写 `DocxReplace/Core/ParagraphMatcher.swift`**

```swift
import Foundation

/// 在一个段落（或段落内被换行/制表符切分出的片段）的文字上做查找与替换。
/// texts 按 w:t 出现顺序给出，返回的 Edit.textIndex 即该数组下标。
enum ParagraphMatcher {
    struct Edit: Equatable {
        var textIndex: Int
        var newText: String
    }

    static func countMatches(in texts: [String], find: String, options: ReplaceOptions) -> Int {
        guard !find.isEmpty else { return 0 }
        return matchRanges(in: texts.joined(), find: find, options: options).count
    }

    static func replace(in texts: [String], find: String, replaceWith: String,
                        options: ReplaceOptions) -> [Edit] {
        guard !find.isEmpty, !texts.isEmpty else { return [] }
        let joined = texts.joined()
        let matches = matchRanges(in: joined, find: find, options: options)
        guard !matches.isEmpty else { return [] }

        var starts: [Int] = []
        var offset = 0
        for text in texts {
            starts.append(offset)
            offset += text.count
        }

        var editsByText: [Int: [(range: Range<Int>, replacement: String)]] = [:]
        for match in matches {
            func overlaps(_ index: Int) -> Bool {
                starts[index] < match.upperBound && starts[index] + texts[index].count > match.lowerBound
            }
            guard let first = texts.indices.first(where: overlaps),
                  let last = texts.indices.last(where: overlaps) else { continue }
            for index in first...last {
                let localStart = max(match.lowerBound - starts[index], 0)
                let localEnd = min(match.upperBound - starts[index], texts[index].count)
                guard localStart <= localEnd else { continue }
                editsByText[index, default: []].append((localStart..<localEnd, index == first ? replaceWith : ""))
            }
        }

        var edits: [Edit] = []
        for (index, changes) in editsByText {
            var chars = Array(texts[index])
            for change in changes.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
                chars.replaceSubrange(change.range, with: Array(change.replacement))
            }
            edits.append(Edit(textIndex: index, newText: String(chars)))
        }
        return edits.sorted { $0.textIndex < $1.textIndex }
    }

    /// 返回命中在拼接字符串中的位置（以 Character 计）
    static func matchRanges(in text: String, find: String, options: ReplaceOptions) -> [Range<Int>] {
        guard !find.isEmpty, !text.isEmpty else { return [] }
        var compareOptions: String.CompareOptions = [.literal]
        if !options.caseSensitive { compareOptions.insert(.caseInsensitive) }

        var ranges: [Range<Int>] = []
        var searchStart = text.startIndex
        while searchStart < text.endIndex,
              let found = text.range(of: find, options: compareOptions, range: searchStart..<text.endIndex) {
            if !options.wholeWord || isWholeWord(text, found) {
                ranges.append(text.distance(from: text.startIndex, to: found.lowerBound)
                              ..< text.distance(from: text.startIndex, to: found.upperBound))
            }
            searchStart = found.upperBound
        }
        return ranges
    }

    private static func isWholeWord(_ text: String, _ range: Range<String.Index>) -> Bool {
        if range.lowerBound > text.startIndex {
            let before = text[text.index(before: range.lowerBound)]
            if isWordCharacter(before) { return false }
        }
        if range.upperBound < text.endIndex {
            let after = text[range.upperBound]
            if isWordCharacter(after) { return false }
        }
        return true
    }

    private static func isWordCharacter(_ ch: Character) -> Bool {
        ch.isLetter || ch.isNumber
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ParagraphMatcherTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，9 个测试全部通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ParagraphMatcher.swift DocxReplaceTests/ParagraphMatcherTests.swift
git commit -m "feat: 实现跨 run 的文字查找与计数"
```

---

## Task 8: 替换区间计算

**Files:**
- Modify: `DocxReplaceTests/ParagraphMatcherTests.swift`

Task 7 已经实现了 `replace`，本任务用测试把它钉死。

- [ ] **Step 1: 追加测试到 `DocxReplaceTests/ParagraphMatcherTests.swift`**

```swift
    func testReplaceWithinSingleRun() {
        let edits = ParagraphMatcher.replace(in: ["北京公司"], find: "北京", replaceWith: "上海", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "上海公司")])
    }

    func testReplaceAcrossRunsPutsTextInFirstRun() {
        let edits = ParagraphMatcher.replace(in: ["北", "京", "公司"], find: "北京", replaceWith: "上海",
                                             options: options)
        XCTAssertEqual(edits, [
            ParagraphMatcher.Edit(textIndex: 0, newText: "上海"),
            ParagraphMatcher.Edit(textIndex: 1, newText: ""),
        ])
    }

    func testReplaceAcrossRunsKeepsSuffix() {
        let edits = ParagraphMatcher.replace(in: ["AB", "CD", "EF"], find: "BC", replaceWith: "X",
                                             options: options)
        XCTAssertEqual(edits, [
            ParagraphMatcher.Edit(textIndex: 0, newText: "AX"),
            ParagraphMatcher.Edit(textIndex: 1, newText: "D"),
        ])
    }

    func testReplaceWithLongerText() {
        let edits = ParagraphMatcher.replace(in: ["abc"], find: "b", replaceWith: "BETA", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "aBETAc")])
    }

    func testReplaceWithEmptyStringDeletes() {
        let edits = ParagraphMatcher.replace(in: ["aXbXc"], find: "X", replaceWith: "", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "abc")])
    }

    func testReplaceMultipleMatchesInOneRun() {
        let edits = ParagraphMatcher.replace(in: ["old-old"], find: "old", replaceWith: "new", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "new-new")])
    }

    func testReplaceMatchSpanningTwoRunsEditsBoth() {
        // joined = "abab"，"ba" 命中 [1,3)，横跨 run0 的 'b' 与 run1 的 'a'，
        // 因此两个 run 都必须重写（run1 若不动，残留的 'a' 会留下）
        let edits = ParagraphMatcher.replace(in: ["ab", "ab"], find: "ba", replaceWith: "X", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "aX"),
                               ParagraphMatcher.Edit(textIndex: 1, newText: "b")])
    }

    func testReplaceSkipsEmptySegments() {
        let edits = ParagraphMatcher.replace(in: ["", ""], find: "x", replaceWith: "y", options: options)
        XCTAssertTrue(edits.isEmpty)
    }

    func testReplaceCaseInsensitiveKeepsReplacementVerbatim() {
        let edits = ParagraphMatcher.replace(in: ["HELLO"], find: "hello", replaceWith: "hi", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "hi")])
    }

    func testReplaceWholeWordOnly() {
        let opts = ReplaceOptions(wholeWord: true)
        let edits = ParagraphMatcher.replace(in: ["cat category"], find: "cat", replaceWith: "dog", options: opts)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "dog category")])
    }

    func testReplaceNothingReturnsEmpty() {
        XCTAssertTrue(ParagraphMatcher.replace(in: ["abc"], find: "zzz", replaceWith: "y",
                                               options: options).isEmpty)
    }
```

- [ ] **Step 2: 运行测试**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ParagraphMatcherTests 2>&1 | tail -30
```

Expected: 全部通过（`** TEST SUCCEEDED **`）。若某个「跨 run」用例失败，先确认 `matchRanges` 的非重叠语义没写错：`"abab"` 中 `"ba"` 只有 1 处——第 1 处命中后搜索从命中末尾继续，剩下的 `"ab"` 不含 `"ba"`。

- [ ] **Step 3: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplaceTests/ParagraphMatcherTests.swift
git commit -m "test: 覆盖替换区间计算的各种情形"
```

---

## Task 7b: ParagraphMatcher 偏移单位改为 UTF-16（Task 7/8 审查结论）

**Files:**
- Modify: `DocxReplace/Core/ParagraphMatcher.swift`
- Modify: `DocxReplaceTests/ParagraphMatcherTests.swift`

背景：审查用对抗性输入找到两个真实缺陷，都源于「偏移量按 `Character` 计」：

1. **跨 run 的字素簇会静默改错文字**。`Character` 计数在字符串拼接时**不可加**：`"a"` + `"\u{0301}b"` 拼成 `"áb"` 只有 2 个 Character，但两个 run 的 `count` 之和是 3。于是 run 起始偏移与拼接串中的实际位置错位。实例：`texts = ["a", "\u{0301}b"]`、`find = "b"`、`replaceWith = "X"` → 当前实现返回 `Edit(1, "Xb")`，应用后得到 `"aXb"`，而正确答案是 `"áX"`（重音被删、要找的 `b` 反而留下）。同样的问题出现在肤色 emoji、国旗、韩文拼字、ZWJ 序列上。**这条路径绕过 Task 10 的两道防线**（结果仍是合法 XML、节点数不变）。
2. **`wholeWord` 会崩溃**。Foundation 的 `range(of:)` 可能返回边界落在字素簇内部的索引，`text.index(before:)` / `text[range.upperBound]` 会触发 fatal error。实例：`matchRanges(in: "🇳🇨", find: "🇨", options: ReplaceOptions(caseSensitive: true, wholeWord: true))`。

修法：偏移单位全部改用 **UTF-16 码元**（拼接时可加），匹配与边界判断都用 `NSString` API，代码里不再出现 `String.Index` 运算。

**Step 1: 追加失败测试到 `ParagraphMatcherTests.swift`**

```swift
    func testCombiningMarkSplitAcrossRuns() {
        // "a" + 组合符 拼成一个字素簇：按 Character 计偏移会错位，必须按 UTF-16
        let edits = ParagraphMatcher.replace(in: ["a", "\u{0301}b"], find: "b", replaceWith: "X",
                                             options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 1, newText: "\u{0301}X")])
    }

    func testEmojiSkinToneSplitAcrossRuns() {
        let edits = ParagraphMatcher.replace(in: ["👍", "🏽x"], find: "x", replaceWith: "X", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 1, newText: "🏽X")])
    }

    func testWholeWordWithFlagEmojiDoesNotCrash() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.matchRanges(in: "🇳🇨", find: "🇨", options: opts), [2..<4])
    }

    func testCountAndReplaceAgreeOnEmojiMatch() {
        // 不能出现「计数 1 处，却一处都没改」
        let texts = ["👍🏽"]
        XCTAssertEqual(ParagraphMatcher.countMatches(in: texts, find: "👍", options: options), 1)
        XCTAssertEqual(ParagraphMatcher.replace(in: texts, find: "👍", replaceWith: "X", options: options),
                       [ParagraphMatcher.Edit(textIndex: 0, newText: "X🏽")])
    }

    func testEmptyRunInsideMatchProducesNoSpuriousEdit() {
        let edits = ParagraphMatcher.replace(in: ["A", "", "B"], find: "AB", replaceWith: "X", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "X"),
                               ParagraphMatcher.Edit(textIndex: 2, newText: "")])
    }
```

**Step 2: 用新文件整体替换 `DocxReplace/Core/ParagraphMatcher.swift`**

```swift
import Foundation

/// 在一个段落（或段落内被换行/制表符切分出的片段）的文字上做查找与替换。
/// texts 按 w:t 出现顺序给出，返回的 Edit.textIndex 即该数组下标。
///
/// 所有偏移量一律以 **UTF-16 码元** 计。原因：
/// 1. UTF-16 偏移在字符串拼接时是可加的，而 Character 偏移不是 —— 当一个字素簇横跨
///    两个 run（组合符、肤色 emoji、国旗、韩文拼字、ZWJ 序列）时，按 Character 累加的
///    run 起始偏移会与拼接串中的实际位置错位，导致静默改错文字。
/// 2. 与 Foundation 的 NSString 匹配 API 单位一致，代码里不再出现 String.Index 运算，
///    也就不会因索引落在字素簇内部而崩溃。
enum ParagraphMatcher {
    struct Edit: Equatable {
        var textIndex: Int
        var newText: String
    }

    /// 词字符集合：字母与数字（含中日韩文字）。与 Word 的「全字匹配」行为一致。
    private static let wordCharacters = CharacterSet.letters.union(.decimalDigits)

    static func countMatches(in texts: [String], find: String, options: ReplaceOptions) -> Int {
        guard !find.isEmpty else { return 0 }
        return matchRanges(in: texts.joined(), find: find, options: options).count
    }

    static func replace(in texts: [String], find: String, replaceWith: String,
                        options: ReplaceOptions) -> [Edit] {
        guard !find.isEmpty, !texts.isEmpty else { return [] }
        let matches = matchRanges(in: texts.joined(), find: find, options: options)
        guard !matches.isEmpty else { return [] }

        var starts: [Int] = []
        var offset = 0
        for text in texts {
            starts.append(offset)
            offset += text.utf16.count
        }

        var editsByText: [Int: [(range: Range<Int>, replacement: String)]] = [:]
        for match in matches {
            func overlaps(_ index: Int) -> Bool {
                starts[index] < match.upperBound && starts[index] + texts[index].utf16.count > match.lowerBound
            }
            guard let first = texts.indices.first(where: overlaps),
                  let last = texts.indices.last(where: overlaps) else { continue }
            for index in first...last {
                let localStart = max(match.lowerBound - starts[index], 0)
                let localEnd = min(match.upperBound - starts[index], texts[index].utf16.count)
                // 空区间只在「整段都空」时出现（例如夹在命中中间的零长 run），跳过以免产生空改动
                guard localStart < localEnd else { continue }
                editsByText[index, default: []].append((localStart..<localEnd, index == first ? replaceWith : ""))
            }
        }

        var edits: [Edit] = []
        for (index, changes) in editsByText {
            let mutable = NSMutableString(string: texts[index])
            for change in changes.sorted(by: { $0.range.lowerBound > $1.range.lowerBound }) {
                mutable.replaceCharacters(
                    in: NSRange(location: change.range.lowerBound,
                                length: change.range.upperBound - change.range.lowerBound),
                    with: change.replacement)
            }
            edits.append(Edit(textIndex: index, newText: mutable as String))
        }
        return edits.sorted { $0.textIndex < $1.textIndex }
    }

    /// 返回命中在拼接字符串中的位置，单位为 **UTF-16 码元**，互不重叠
    static func matchRanges(in text: String, find: String, options: ReplaceOptions) -> [Range<Int>] {
        guard !find.isEmpty, !text.isEmpty else { return [] }
        let haystack = text as NSString
        var compareOptions: NSString.CompareOptions = [.literal]
        if !options.caseSensitive { compareOptions.insert(.caseInsensitive) }

        var ranges: [Range<Int>] = []
        var location = 0
        while location < haystack.length {
            let searchRange = NSRange(location: location, length: haystack.length - location)
            let found = haystack.range(of: find, options: compareOptions, range: searchRange)
            guard found.location != NSNotFound else { break }
            if !options.wholeWord || isWholeWordMatch(haystack, found) {
                ranges.append(found.location..<(found.location + found.length))
            }
            location = found.location + max(found.length, 1)   // 至少前进 1，避免零长命中死循环
        }
        return ranges
    }

    /// 前后紧邻的码元是否都不是词字符。只检查边界那一个码元，不做任何索引运算。
    private static func isWholeWordMatch(_ haystack: NSString, _ found: NSRange) -> Bool {
        if found.location > 0 {
            let before = NSRange(location: found.location - 1, length: 1)
            if haystack.rangeOfCharacter(from: wordCharacters, range: before).location != NSNotFound {
                return false
            }
        }
        let afterStart = found.location + found.length
        if afterStart < haystack.length {
            let after = NSRange(location: afterStart, length: 1)
            if haystack.rangeOfCharacter(from: wordCharacters, range: after).location != NSNotFound {
                return false
            }
        }
        return true
    }
}
```

**Step 3: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ParagraphMatcherTests 2>&1 | tail -25
```

Expected: `** TEST SUCCEEDED **`，25 个测试全部通过（20 原有 + 5 新增，原有的全部不得改动）。

**Step 4: 运行全量测试并提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test 2>&1 | tail -10
git add DocxReplace/Core/ParagraphMatcher.swift DocxReplaceTests/ParagraphMatcherTests.swift
git commit -m "fix: ParagraphMatcher 偏移改用 UTF-16 —— 修跨 run 字素簇改错文字与全字匹配崩溃"
```

Expected: 全量 75 个测试通过。

---

## Task 7c: 全字匹配按「组合字符序列」判断（Task 7b 复核结论）

**Files:**
- Modify: `DocxReplace/Core/ParagraphMatcher.swift`
- Modify: `DocxReplaceTests/ParagraphMatcherTests.swift`

背景：Task 7b 把偏移改成 UTF-16 后，`isWholeWordMatch` 只检查**单个 UTF-16 码元**。非 BMP 字符（数学字母 `𝒜`、CJK 扩展 B 的 `𠀀`）在 UTF-16 里是代理对，单独一个码元是孤立代理项，不属于 `CharacterSet.letters`，于是被误判为非词字符、当成词边界：

```swift
ParagraphMatcher.replace(in: ["𝒜cat"], find: "cat", replaceWith: "X",
                         options: ReplaceOptions(caseSensitive: true, wholeWord: true))
// 现在返回 [Edit(0, "𝒜X")]，正确答案是 []（"cat" 在词 "𝒜cat" 内部）
```

CJK 扩展 B 区字符（`𠀀` 等）在中文文档里是可能出现的，必须修。改法：用 `rangeOfComposedCharacterSequence(at:)` 取该位置所在的**完整字符**，判断它的**第一个标量**是否为词字符。

**Step 1: 追加失败测试到 `ParagraphMatcherTests.swift`**

```swift
    func testWholeWordRejectsMatchAfterNonBMPLetter() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["𝒜cat"], find: "cat", options: opts), 0)
        XCTAssertTrue(ParagraphMatcher.replace(in: ["𝒜cat"], find: "cat", replaceWith: "X",
                                               options: opts).isEmpty)
        // CJK 扩展 B 区字符同理
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["𠀀cat"], find: "cat", options: opts), 0)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["cat𝒜"], find: "cat", options: opts), 0)
    }

    func testWholeWordAcceptsMatchBesideNonWordEmoji() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["👍cat"], find: "cat", options: opts), 1)
    }

    func testWholeWordTreatsComposedLetterAsWordCharacter() {
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["e\u{0301}cat"], find: "cat", options: opts), 0)
    }

    func testWholeWordTreatsDecimalDigitAsWordCharacter() {
        // 明确的取舍：十进制数字(Nd)算词字符；上标/罗马数字/分数(No/Nl，如 ①Ⅷ½)不算
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["1cat"], find: "cat", options: opts), 0)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["①cat"], find: "cat", options: opts), 1)
    }
```

**Step 2: 改 `DocxReplace/Core/ParagraphMatcher.swift`**

把词字符集合与整词判断替换为：

```swift
    /// 词字符集合：Unicode 字母（L*，含中日韩及扩展区）与十进制数字（Nd）。
    /// 取舍：上标/罗马数字/分数（①Ⅷ½ 等 No/Nl 类）**不算**词字符。
    private static let wordScalars = CharacterSet.letters.union(.decimalDigits)

    /// 判断该 UTF-16 码元位置所在的**完整字符**是否为词字符。
    /// 必须按组合字符序列判断，不能只看单个码元：非 BMP 字符（𝒜、𠀀）是代理对，
    /// 孤立代理项不属于字母集，会被误判成词边界，从而把词内命中当成整词命中。
    private static func isWordCharacter(_ haystack: NSString, at index: Int) -> Bool {
        guard index >= 0, index < haystack.length else { return false }
        let sequence = haystack.rangeOfComposedCharacterSequence(at: index)
        guard let first = haystack.substring(with: sequence).unicodeScalars.first else { return false }
        return wordScalars.contains(first)
    }

    private static func isWholeWordMatch(_ haystack: NSString, _ found: NSRange) -> Bool {
        if isWordCharacter(haystack, at: found.location - 1) { return false }
        if isWordCharacter(haystack, at: found.location + found.length) { return false }
        return true
    }
```

（原来的 `wordCharacters` 常量与逐码元写法一并删除；越界由 `isWordCharacter` 内的 guard 处理。）

**Step 3: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，全量 79 个测试通过（75 + 4 新增）。原有的 25 个 ParagraphMatcher 测试（含国旗 emoji 的 `[2..<4]`）必须继续通过。

**Step 4: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ParagraphMatcher.swift DocxReplaceTests/ParagraphMatcherTests.swift
git commit -m "fix: 全字匹配按组合字符序列判断，修非 BMP 字母旁的误命中"
```

---

## Task 7d: 词字符改用 Unicode 通用类别判断（Task 7c 复核结论）

**Files:**
- Modify: `DocxReplace/Core/ParagraphMatcher.swift`
- Modify: `DocxReplaceTests/ParagraphMatcherTests.swift`

背景：复核用独立 oracle（44 520 组对照）确认非 BMP 那类已彻底修好，但暴露出 `CharacterSet.letters` 这个 API 本身不可靠，两个方向都会错：

- **多含**：`CharacterSet.letters` 实际是 L* ∪ M*，把组合符号也算作字母。于是文本开头的孤立组合符会被当成词字符，`"\u{0301}cat"` 查 `cat` 全字匹配会漏掉应该命中的一处（孤儿组合符在真实文档里很少见，影响小）。
- **漏掉**：本机实测有 6 227 个真实字母标量不在 `CharacterSet.letters` 里，包括西夏文 U+17000–U+187FF、西夏文补遗 U+18D00–U+18D1E、Todhri U+105C0–U+105F3。这些是**错误替换**：`"𗀀cat"` 查 `cat` 会被当成整词命中并真的改掉。

改法：不再依赖 `CharacterSet`，直接看标量自己的 Unicode 通用类别 = L* ∪ Nd。

**Step 1: 追加失败测试到 `ParagraphMatcherTests.swift`**

```swift
    func testWholeWordIgnoresOrphanCombiningMark() {
        // 孤立的组合符 / 变体选择符属于 M*，不是词字符
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["\u{0301}cat"], find: "cat", options: opts), 1)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["\u{FE0F}cat"], find: "cat", options: opts), 1)
    }

    func testWholeWordRecognizesLettersMissingFromCharacterSetLetters() {
        // CharacterSet.letters 在本机缺少部分真实字母（西夏文、Todhri），
        // 不修的话会被当成词边界，产生错误替换
        let opts = ReplaceOptions(caseSensitive: true, wholeWord: true)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["\u{17000}cat"], find: "cat", options: opts), 0)
        XCTAssertEqual(ParagraphMatcher.countMatches(in: ["\u{105C0}cat"], find: "cat", options: opts), 0)
        XCTAssertTrue(ParagraphMatcher.replace(in: ["\u{17000}cat"], find: "cat", replaceWith: "X",
                                               options: opts).isEmpty)
    }
```

**Step 2: 改 `DocxReplace/Core/ParagraphMatcher.swift`**

删掉 `wordScalars` 常量，改为按通用类别判断：

```swift
    /// 词字符 = Unicode 通用类别 L*（字母，含中日韩、扩展区、西夏文等）∪ Nd（十进制数字）。
    ///
    /// 不用 `CharacterSet.letters`：它实测是 L* ∪ M*（多含组合符号），
    /// 且在本机缺少 6 227 个真实字母标量（西夏文 U+17000 起、Todhri U+105C0 起等），
    /// 漏掉字母会把词内命中误判成整词命中，从而改错文字。
    private static func isWordScalar(_ scalar: UnicodeScalar) -> Bool {
        switch scalar.properties.generalCategory {
        case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter,
             .decimalNumber:
            return true
        default:
            return false
        }
    }

    /// 判断该 UTF-16 码元位置所在的**完整字符**是否为词字符。
    /// 必须按组合字符序列判断，不能只看单个码元：非 BMP 字符（𝒜、𗀀）是代理对，
    /// 孤立代理项会被误判成词边界。
    private static func isWordCharacter(_ haystack: NSString, at index: Int) -> Bool {
        guard index >= 0, index < haystack.length else { return false }
        let sequence = haystack.rangeOfComposedCharacterSequence(at: index)
        guard let first = haystack.substring(with: sequence).unicodeScalars.first else { return false }
        return isWordScalar(first)
    }
```

**Step 3: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，全量 81 个测试通过（79 + 2 新增）。既有的 29 个 ParagraphMatcher 测试必须继续通过，尤其是 `testWholeWordTreatsDecimalDigitAsWordCharacter`（①不算、1 算）与 `testWholeWordWithFlagEmojiDoesNotCrash`。

**Step 4: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ParagraphMatcher.swift DocxReplaceTests/ParagraphMatcherTests.swift
git commit -m "fix: 词字符改按 Unicode 通用类别判断，修 CharacterSet.letters 的多含与缺漏"
```

**这是 ParagraphMatcher 的最后一轮加固**：剩余的已知偏差只有「组合符紧跟在字母之后时 oracle 用标量、实现用字符簇」这一语义差异，属设计取舍（`e\u{0301}cat` 不命中是刻意的）。

---

## Task 9: 段落与分段结构分析

**Files:**
- Create: `DocxReplace/Core/DocxXmlAnalyzer.swift`
- Test: `DocxReplaceTests/DocxXmlAnalyzerTests.swift`

- [ ] **Step 1: 写失败测试 `DocxReplaceTests/DocxXmlAnalyzerTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class DocxXmlAnalyzerTests: XCTestCase {
    private func analyze(_ xml: String) throws -> DocxXmlAnalyzer.PartAnalysis {
        // XMLDocument 不接受未声明的命名空间前缀（报 "Namespace prefix w ... is not defined"），
        // 所以测试片段必须包一层声明了 xmlns:w 的根元素，否则所有用例都会在解析阶段失败
        let wrapped = "<w:doc xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + xml + "</w:doc>"
        return try DocxXmlAnalyzer.analyze([UInt8](wrapped.utf8))
    }

    func testSingleParagraph() throws {
        let xml = "<w:body><w:p><w:r><w:t>甲</w:t></w:r><w:r><w:t>乙</w:t></w:r></w:p></w:body>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0, 1]])
        XCTAssertEqual(result.texts, ["甲", "乙"])
    }

    func testTwoParagraphsStaySeparate() throws {
        let xml = "<w:body><w:p><w:r><w:t>甲</w:t></w:r></w:p><w:p><w:r><w:t>乙</w:t></w:r></w:p></w:body>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
    }

    func testLineBreakSplitsSegment() throws {
        let xml = "<w:p><w:r><w:t>AB</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>CD</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
    }

    func testTabSplitsSegment() throws {
        let xml = "<w:p><w:r><w:t>AB</w:t><w:tab/><w:t>CD</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
    }

    func testNestedParagraphInTextBoxIsSeparate() throws {
        let xml = """
        <w:p><w:r><w:t>外层</w:t></w:r><w:r><w:drawing><w:txbxContent>
        <w:p><w:r><w:t>框内</w:t></w:r></w:p>
        </w:txbxContent></w:drawing></w:r></w:p>
        """
        let result = try analyze(xml)
        XCTAssertEqual(result.segments, [[0], [1]])
        XCTAssertEqual(result.texts, ["外层", "框内"])
    }

    func testDelTextIsIgnored() throws {
        let xml = "<w:p><w:del><w:r><w:delText>删除的</w:delText></w:r></w:del><w:r><w:t>保留</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.texts, ["保留"])
    }

    func testInstrTextIsIgnored() throws {
        let xml = "<w:p><w:r><w:instrText>PAGE</w:instrText></w:r><w:r><w:t>1</w:t></w:r></w:p>"
        let result = try analyze(xml)
        XCTAssertEqual(result.texts, ["1"])
    }

    func testCommentDoesNotBreakAnalysis() {
        // 注释里的假 w:t 在字节扫描与 DOM 解析中都被忽略，两边数量应一致
        let xml = "<w:p><w:r><w:t>真</w:t><!-- <w:t>假</w:t> --></w:r></w:p>"
        let result = try? analyze(xml)
        XCTAssertEqual(result?.texts, ["真"])
    }

    func testMalformedXMLErrors() {
        XCTAssertThrowsError(try analyze("<w:p><w:r><w:t>未闭合"))
    }

    /// 最关键的假设：字节扫描顺序与 DOM 遍历顺序逐位对应。
    /// 用带注释、delText、文本框嵌套段落的夹具钉死它。
    func testTextsMatchRawScanOrder() throws {
        let xml = """
        <w:p><w:r><w:t>一</w:t></w:r><!-- <w:t>注释</w:t> --><w:r><w:t>二</w:t></w:r></w:p>
        <w:p><w:del><w:r><w:delText>已删</w:delText></w:r></w:del><w:r><w:t>三</w:t></w:r></w:p>
        <w:p><w:r><w:t>四</w:t></w:r><w:r><w:drawing><w:txbxContent>
        <w:p><w:r><w:t>五</w:t></w:r></w:p>
        </w:txbxContent></w:drawing></w:r></w:p>
        """
        let wrapped = "<w:doc xmlns:w=\"http://schemas.openxmlformats.org/wordprocessingml/2006/main\">"
            + xml + "</w:doc>"
        let bytes = [UInt8](wrapped.utf8)
        let analysis = try DocxXmlAnalyzer.analyze(bytes)
        XCTAssertEqual(analysis.texts, XmlTextLocator.findTextNodes(in: bytes).map(\.text))
        XCTAssertEqual(analysis.texts, ["一", "二", "三", "四", "五"])
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/DocxXmlAnalyzerTests 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'DocxXmlAnalyzer' in scope`。

- [ ] **Step 3: 写 `DocxReplace/Core/DocxXmlAnalyzer.swift`**

```swift
import Foundation

enum DocxXmlError: Error, Equatable {
    case parseFailed(String)
    case nodeCountMismatch(dom: Int, raw: Int)

    var message: String {
        switch self {
        case .parseFailed(let detail): return "XML 解析失败：\(detail)"
        case .nodeCountMismatch(let dom, let raw): return "文档结构异常（DOM \(dom) / 原始 \(raw)）"
        }
    }
}

/// 用 XMLDocument 解析出段落结构，解决两件事：
/// 1. 哪些 w:t 属于同一个段落（决定能否跨 run 匹配）
/// 2. 段落内的换行/制表符把文字切成多个片段（匹配不跨片段）
enum DocxXmlAnalyzer {
    struct PartAnalysis: Equatable {
        /// 每个片段包含的 w:t 全局序号
        var segments: [[Int]]
        /// 每个 w:t 的文字（下标即全局序号）
        var texts: [String]
    }

    static func analyze(_ xml: [UInt8]) throws -> PartAnalysis {
        let document: XMLDocument
        do {
            document = try XMLDocument(data: Data(xml), options: [])
        } catch {
            throw DocxXmlError.parseFailed(String(describing: error))
        }

        var textNodes: [XMLNode] = []
        var indexByNode: [ObjectIdentifier: Int] = [:]
        func collect(_ node: XMLNode) {
            if node.kind == .element, node.name == "w:t" {
                indexByNode[ObjectIdentifier(node)] = textNodes.count
                textNodes.append(node)
            }
            for child in node.children ?? [] {
                collect(child)
            }
        }
        if let root = document.rootElement() {
            collect(root)
        }

        let rawNodes = XmlTextLocator.findTextNodes(in: xml)
        guard rawNodes.count == textNodes.count else {
            throw DocxXmlError.nodeCountMismatch(dom: textNodes.count, raw: rawNodes.count)
        }

        var segments: [[Int]] = []
        func walkParagraph(_ paragraph: XMLNode) {
            var current: [Int] = []
            func visit(_ node: XMLNode) {
                guard node.kind == .element else { return }
                if node.name == "w:p", node !== paragraph { return }   // 嵌套段落（文本框）单独处理
                if node.name == "w:t" {
                    if let index = indexByNode[ObjectIdentifier(node)] {
                        current.append(index)
                    }
                    return
                }
                if node.name == "w:br" || node.name == "w:tab" || node.name == "w:cr" {
                    if !current.isEmpty {
                        segments.append(current)
                        current = []
                    }
                    return
                }
                for child in node.children ?? [] {
                    visit(child)
                }
            }
            visit(paragraph)
            if !current.isEmpty {
                segments.append(current)
            }
        }

        func collectParagraphs(_ node: XMLNode) {
            if node.kind == .element, node.name == "w:p" {
                walkParagraph(node)
                // 注意：这里不能 return。文本框会产生嵌套在 run 里的 w:p，
                // 必须继续下钻把它当成独立段落处理（walkParagraph 内部会跳过嵌套子树，
                // 所以不会重复计数）。写成 return 的话文本框里的文字永远进不了 segments。
            }
            for child in node.children ?? [] {
                collectParagraphs(child)
            }
        }
        if let root = document.rootElement() {
            collectParagraphs(root)
        }

        return PartAnalysis(segments: segments, texts: rawNodes.map(\.text))
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/DocxXmlAnalyzerTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，9 个测试全部通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/DocxXmlAnalyzer.swift DocxReplaceTests/DocxXmlAnalyzerTests.swift
git commit -m "feat: 解析段落与分段结构，支持文本框嵌套段落与换行分片"
```

---

## Task 10: `.docx` 替换主流程

**Files:**
- Modify: `DocxReplace/Core/ZipWriter.swift`（见 Step 0）
- Create: `DocxReplace/Core/DocxTextReplacer.swift`
- Create: `DocxReplaceTests/DocxFixture.swift`
- Test: `DocxReplaceTests/DocxTextReplacerTests.swift`

- [ ] **Step 0: 先修掉 Task 4 审查遗留的三处自洽性问题**

这三处都是「我们写出的归档会被我们自己的读取器拒绝」，对真实 Word 文档不可达，但会让 Task 10 的「写出后回读校验」路径出现难以解释的失败，先修掉。

1. `ZipWriter.build` 里的条目数上限：`entries.count <= Int(UInt16.max)` 允许写出 65535 条，
   而 EOCD 的 `0xFFFF` 正是 zip64 哨兵，读取器会抛 `zip64Unsupported`。改成严格小于：

```swift
        guard entries.count < Int(UInt16.max) else { throw ZipError.archiveTooLarge }
```

2. `makeEntry` 与读取器的 `inflateLimit` 不对称：`contents.count > max(64 MiB, 256 × deflated.count)`
   时读回来会被判 `implausibleSize`。让它退回 stored：

```swift
        if let deflated = ZipCompression.deflate(contents), deflated.count < contents.count, !contents.isEmpty,
           contents.count <= max(64 * 1024 * 1024, deflated.count * 256) {
            return ZipOutputEntry(name: name, dosTime: dosTime, dosDate: dosDate, method: 8,
                                  crc32: crc, uncompressedSize: UInt32(contents.count),
                                  externalAttributes: externalAttributes, compressedData: deflated)
        }
```

3. 补两个测试到 `ZipArchiveTests.swift`：
   - `testBuildRejectsExactlyUInt16MaxEntries`：65535 条应抛 `archiveTooLarge`
   - `testMakeEntryRoundTripsThroughReader`：对空内容、不可压缩内容、高压缩比内容三种输入，
     走 `makeEntry → build → ZipArchive.contents` 回读，断言与原文一致

**另外两处 Task 9 审查提出的静默失败，一并堵掉**（都在 `DocxXmlAnalyzer.swift`）：

4. `analyze` 目前校验了 `w:t` 总数，但没校验**每个序号都被分配到了某个分段**。
   若某个 `w:t` 不在任何 `w:p` 内（Word 不会产出，但第三方工具可能有），它会留在 `texts` 里
   却不在 `segments` 中，于是被静默跳过、既不报错也不处理。加一段覆盖校验：

```swift
        let assigned = segments.reduce(0) { $0 + $1.count }
        guard assigned == textNodes.count else {
            throw DocxXmlError.nodeCountMismatch(dom: textNodes.count, raw: assigned)
        }
```

5. `indexByNode[ObjectIdentifier(node)]` 查不到时是静默 `return`（同属静默遗漏）。改为响亮：

```swift
                if node.name == "w:t" {
                    if let index = indexByNode[ObjectIdentifier(node)] {
                        current.append(index)
                    } else {
                        assertionFailure("w:t 节点未在序号表中，枚举逻辑出现分歧")
                    }
                    return
                }
```

6. 给 `PartAnalysis.segments` 补一句注释，说明**分段顺序不等于全局序号顺序**
   （父段落的分段先于其文本框内嵌套段落的分段），Task 10 按序号取用、不依赖顺序：

```swift
        /// 每个片段包含的 w:t 全局序号。
        /// 注意：顺序不保证按序号升序 —— 父段落的分段会先于其文本框内嵌套段落的分段输出。
        var segments: [[Int]]
```

7. 再补两个测试到 `DocxXmlAnalyzerTests.swift`：
   - `testOrphanTextOutsideParagraphFailsLoudly`：把 `<w:t>游离</w:t>` 放在 `<w:p>` 之外，断言抛错
   - `testThrowsOnMalformedNestedStructure`：`<w:p><w:r><w:t>甲</w:t></w:r><w:p>`（未闭合）应抛错

- [ ] **Step 1: 写夹具生成器 `DocxReplaceTests/DocxFixture.swift`**

```swift
import Foundation
@testable import DocxReplace

/// 用自研 ZIP 层拼出结构合法的 .docx，用于测试
enum DocxFixture {
    static func docx(bodyXML: String, extraParts: [(String, String)] = []) throws -> Data {
        var parts: [(String, String)] = [
            ("[Content_Types].xml", contentTypes(extraParts: extraParts.map(\.0))),
            ("_rels/.rels", rootRels),
            ("word/document.xml", documentXML(bodyXML: bodyXML)),
        ]
        parts.append(contentsOf: extraParts)
        let entries = parts.map {
            ZipWriter.makeEntry(name: $0.0, contents: Data($0.1.utf8), date: Date(timeIntervalSince1970: 0))
        }
        return try ZipWriter.build(entries)
    }

    static func paragraph(_ runs: [String]) -> String {
        "<w:p>" + runs.map { "<w:r><w:t>\($0)</w:t></w:r>" }.joined() + "</w:p>"
    }

    /// 把 XML 中所有 w:t 元素内容清空，用于「除文字外结构完全一致」的比对
    static func structuralSignature(_ xml: String) throws -> String {
        let regex = try NSRegularExpression(pattern: "<w:t(?:\\s[^>]*)?(?:/>|>[^<]*</w:t>)")
        let range = NSRange(xml.startIndex..<xml.endIndex, in: xml)
        return regex.stringByReplacingMatches(in: xml, range: range, withTemplate: "<w:t/>")
    }

    private static func contentTypes(extraParts: [String]) -> String {
        var overrides = """
        <Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>
        """
        for name in extraParts {
            let type: String
            if name.contains("header") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.header+xml"
            } else if name.contains("footer") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.footer+xml"
            } else if name.contains("footnotes") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.footnotes+xml"
            } else if name.contains("endnotes") {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.endnotes+xml"
            } else {
                type = "application/vnd.openxmlformats-officedocument.wordprocessingml.comments+xml"
            }
            overrides += "\n<Override PartName=\"/\(name)\" ContentType=\"\(type)\"/>"
        }
        return """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">
        <Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>
        <Default Extension="xml" ContentType="application/xml"/>
        \(overrides)
        </Types>
        """
    }

    private static let rootRels = """
    <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
    <Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">
    <Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>
    </Relationships>
    """

    static func documentXML(bodyXML: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body>
        \(bodyXML)
        <w:sectPr/></w:body></w:document>
        """
    }

    static func partXML(prefix: String, bodyXML: String) -> String {
        """
        <?xml version="1.0" encoding="UTF-8" standalone="yes"?>
        <w:\(prefix) xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main">
        \(bodyXML)
        </w:\(prefix)>
        """
    }
}
```

- [ ] **Step 2: 写失败测试 `DocxReplaceTests/DocxTextReplacerTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class DocxTextReplacerTests: XCTestCase {
    private let options = ReplaceOptions()

    private func documentText(_ data: Data) throws -> String {
        let archive = try ZipArchive(data: data)
        let entry = try XCTUnwrap(archive.entry(named: "word/document.xml"))
        return String(decoding: try archive.contents(of: entry), as: UTF8.self)
    }

    func testCountsMatchesAcrossSplitRuns() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["北", "京", "公司"]))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 1)
    }

    func testReplaceKeepsStructureIdentical() throws {
        let data = try DocxFixture.docx(bodyXML: """
        <w:p><w:pPr><w:jc w:val="center"/></w:pPr>\
        <w:r><w:rPr><w:b/></w:rPr><w:t>北</w:t></w:r>\
        <w:r><w:t>京公司</w:t></w:r></w:p>
        """)
        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "北京公司",
                                                        replaceWith: "上海集团", options: options)
        XCTAssertEqual(count, 1)
        let before = try DocxFixture.structuralSignature(documentText(data))
        let after = try DocxFixture.structuralSignature(documentText(out))
        XCTAssertEqual(before, after, "除 w:t 文字外，XML 结构必须完全一致")
        XCTAssertTrue(try documentText(out).contains("上海集团"))
    }

    func testReplacementInheritsFirstRunFormatting() throws {
        let data = try DocxFixture.docx(bodyXML: """
        <w:p><w:r><w:rPr><w:b/></w:rPr><w:t>北</w:t></w:r><w:r><w:t>京</w:t></w:r></w:p>
        """)
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "北京", replaceWith: "上海",
                                                    options: options)
        let xml = try documentText(out)
        XCTAssertTrue(xml.contains("<w:rPr><w:b/></w:rPr><w:t>上海</w:t>"),
                      "替换文字应落在第一个命中的 run 内并继承其格式")
    }

    func testReplacesInHeaderFooterAndTextbox() throws {
        let header = DocxFixture.partXML(prefix: "hdr", bodyXML: DocxFixture.paragraph(["旧名"]))
        let footer = DocxFixture.partXML(prefix: "ftr", bodyXML: DocxFixture.paragraph(["旧名"]))
        let body = """
        <w:p><w:r><w:t>旧名</w:t></w:r></w:p>
        <w:p><w:r><w:drawing><w:txbxContent><w:p><w:r><w:t>旧名</w:t></w:r></w:p></w:txbxContent></w:drawing></w:r></w:p>
        """
        let data = try DocxFixture.docx(bodyXML: body, extraParts: [
            ("word/header1.xml", header),
            ("word/footer1.xml", footer),
        ])
        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                        options: options)
        XCTAssertEqual(count, 4, "正文 2 处 + 页眉 1 处 + 页脚 1 处")
        let archive = try ZipArchive(data: out)
        for name in ["word/document.xml", "word/header1.xml", "word/footer1.xml"] {
            let entry = try XCTUnwrap(archive.entry(named: name))
            let xml = String(decoding: try archive.contents(of: entry), as: UTF8.self)
            XCTAssertFalse(xml.contains("旧名"), "\(name) 应已替换")
            XCTAssertTrue(xml.contains("新名"), "\(name) 应含新文字")
        }
    }

    func testDoesNotMatchAcrossParagraphs() throws {
        let data = try DocxFixture.docx(bodyXML:
            DocxFixture.paragraph(["北京"]) + DocxFixture.paragraph(["公司"]))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 0)
    }

    func testDoesNotMatchAcrossLineBreak() throws {
        let data = try DocxFixture.docx(bodyXML:
            "<w:p><w:r><w:t>北京</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>公司</w:t></w:r></w:p>")
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 0)
    }

    func testNoMatchLeavesDataUntouched() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["内容"]))
        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "不存在", replaceWith: "x",
                                                        options: options)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(out, data, "没有命中时不应重写文件")
    }

    func testEntitiesSurviveReplacement() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["a &amp; b"]))
        // find 用 "b"：未被命中的 &amp; 应原样保留，而替换进去的 <c> 应被转义
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "b", replaceWith: "<c>",
                                                    options: options)
        XCTAssertTrue(try documentText(out).contains("a &amp; &lt;c&gt;"))
    }

    func testSpacesAtEdgesGetPreserveSpace() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["X Y"]))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "X", replaceWith: " X ",
                                                    options: options)
        XCTAssertTrue(try documentText(out).contains("xml:space=\"preserve\""))
    }

    func testUntouchedEntriesAreByteIdentical() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["旧名"]))
        let before = try ZipArchive(data: data)
        let rawBefore = try before.rawData(of: try XCTUnwrap(before.entry(named: "_rels/.rels")))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                    options: options)
        let after = try ZipArchive(data: out)
        let rawAfter = try after.rawData(of: try XCTUnwrap(after.entry(named: "_rels/.rels")))
        XCTAssertEqual(rawBefore, rawAfter)
    }

    /// 替换输出的归档必须能被外部工具接受 —— 这是 Task 10 的真实产物形态
    func testRebuiltDocxIsAcceptedBySystemUnzip() throws {
        let data = try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["旧名"]))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                    options: options)
        let url = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("rebuilt-\(UUID().uuidString).zip")
        try out.write(to: url)
        defer { try? FileManager.default.removeItem(at: url) }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/unzip")
        process.arguments = ["-t", url.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        try process.run()
        process.waitUntilExit()
        let output = String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        XCTAssertEqual(process.terminationStatus, 0, "替换产物应通过系统 unzip 校验：\(output)")

        // 逐个条目回读，确认没有部件丢失或损坏
        let archive = try ZipArchive(data: out)
        XCTAssertEqual(archive.entries.count, try ZipArchive(data: data).entries.count)
        for entry in archive.entries {
            XCTAssertNoThrow(try archive.contents(of: entry), "条目应可读：\(entry.name)")
        }
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/DocxTextReplacerTests 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'DocxTextReplacer' in scope`。

- [ ] **Step 4: 写 `DocxReplace/Core/DocxTextReplacer.swift`**

```swift
import Foundation

/// .docx 替换引擎。只读分析 + 原始字节改写，未命中的部件原样直拷。
enum DocxTextReplacer {
    static func targetPartNames(in archive: ZipArchive) -> [String] {
        archive.entries.map(\.name).filter { name in
            if name == "word/document.xml" { return true }
            if name == "word/footnotes.xml" || name == "word/endnotes.xml" || name == "word/comments.xml" {
                return true
            }
            guard name.hasPrefix("word/"), !name.dropFirst(5).contains("/") else { return false }
            let file = String(name.dropFirst(5))
            if (file.hasPrefix("header") || file.hasPrefix("footer")), file.hasSuffix(".xml") {
                return true
            }
            return false
        }
    }

    static func countMatches(docxData: Data, find: String, options: ReplaceOptions) throws -> Int {
        guard !find.isEmpty else { return 0 }
        let archive = try ZipArchive(data: docxData)
        var total = 0
        for name in targetPartNames(in: archive) {
            guard let entry = archive.entry(named: name) else { continue }
            let xml = [UInt8](try archive.contents(of: entry))
            let analysis = try DocxXmlAnalyzer.analyze(xml)
            for segment in analysis.segments {
                total += ParagraphMatcher.countMatches(in: segment.map { analysis.texts[$0] },
                                                       find: find, options: options)
            }
        }
        return total
    }

    /// 返回新数据与实际替换处数；没有命中时原样返回输入数据
    static func replace(docxData: Data, find: String, replaceWith: String,
                        options: ReplaceOptions) throws -> (data: Data, replacedCount: Int) {
        guard !find.isEmpty else { return (docxData, 0) }
        let archive = try ZipArchive(data: docxData)
        let targets = Set(targetPartNames(in: archive))

        var partEdits: [String: (xml: [UInt8], edits: [Int: String], count: Int)] = [:]
        for name in targets {
            guard let entry = archive.entry(named: name) else { continue }
            let xml = [UInt8](try archive.contents(of: entry))
            let analysis = try DocxXmlAnalyzer.analyze(xml)
            var edits: [Int: String] = [:]
            var count = 0
            for segment in analysis.segments {
                let texts = segment.map { analysis.texts[$0] }
                count += ParagraphMatcher.countMatches(in: texts, find: find, options: options)
                for edit in ParagraphMatcher.replace(in: texts, find: find, replaceWith: replaceWith,
                                                     options: options) {
                    edits[segment[edit.textIndex]] = edit.newText
                }
            }
            if count > 0 {
                partEdits[name] = (xml, edits, count)
            }
        }
        guard !partEdits.isEmpty else { return (docxData, 0) }

        var outputs: [ZipOutputEntry] = []
        var total = 0
        for entry in archive.entries {
            if let changed = partEdits[entry.name] {
                let rebuilt = XmlTextLocator.rebuild(xml: changed.xml, edits: changed.edits)
                // 序号必须全部命中：rebuild 会静默丢弃越界序号，宁可整份文件报错，
                // 也不能出现「只改了一部分却按全部成功上报」
                guard rebuilt.applied == changed.edits.count else {
                    throw DocxXmlError.nodeCountMismatch(dom: rebuilt.applied, raw: changed.edits.count)
                }
                let newXML = rebuilt.xml
                // 最后一道防线：改写后的 XML 必须仍能被完整解析。
                // 宁可整份文件报错跳过，也不能写出 Word 打不开的文档。
                _ = try XMLDocument(data: Data(newXML), options: [])
                outputs.append(ZipWriter.makeEntry(name: entry.name, contents: Data(newXML),
                                                   date: Date(),
                                                   externalAttributes: entry.externalAttributes))
                total += changed.count
            } else {
                outputs.append(ZipWriter.copyEntry(entry, raw: try archive.rawData(of: entry)))
            }
        }
        return (try ZipWriter.build(outputs), total)
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/DocxTextReplacerTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`，11 个测试全部通过。

- [ ] **Step 6: 运行全量测试并提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test 2>&1 | tail -10
git add DocxReplace/Core DocxReplaceTests
git commit -m "feat: .docx 替换主流程，覆盖页眉页脚文本框，结构保持不变"
```

Expected: 全量 106 个测试通过（91 + Step 0 的 4 个 + 本任务的 11 个）。

---

## Task 11: 真实文档端到端测试

**Files:**
- Test: `DocxReplaceTests/EndToEndTests.swift`

- [ ] **Step 1: 写 `DocxReplaceTests/EndToEndTests.swift`**

```swift
import XCTest
@testable import DocxReplace

/// 用系统 textutil 生成的真实 docx 做端到端验证，
/// 并用 textutil 反向读取验证输出文件仍然是 Word 能打开的合法文档。
final class EndToEndTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("EndToEndTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func makeDocx(html: String) throws -> Data {
        let htmlURL = tempDir.appendingPathComponent("in-\(UUID().uuidString).html")
        let docxURL = tempDir.appendingPathComponent("out-\(UUID().uuidString).docx")
        // 必须显式声明 charset：textutil 的 HTML 导入在中文系统下会按 GBK 解释，
        // 不加这行会导致 docx 里的中文变成乱码
        let htmlWithCharset = html.contains("charset")
            ? html
            : html.replacingOccurrences(of: "<html>", with: "<html><head><meta charset=\"utf-8\"></head>")
        try htmlWithCharset.write(to: htmlURL, atomically: true, encoding: .utf8)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "docx", "-output", docxURL.path, htmlURL.path]
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0)
        return try Data(contentsOf: docxURL)
    }

    private func plainText(of data: Data) throws -> String {
        let docxURL = tempDir.appendingPathComponent("verify-\(UUID().uuidString).docx")
        try data.write(to: docxURL)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/textutil")
        process.arguments = ["-convert", "txt", "-stdout", docxURL.path]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = Pipe()
        try process.run()
        process.waitUntilExit()
        XCTAssertEqual(process.terminationStatus, 0, "输出文件应是系统可解析的合法 docx")
        return String(decoding: pipe.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
    }

    func testReplacesTextInRealDocx() throws {
        let data = try makeDocx(html: "<html><body><p>北京某某科技有限公司</p><p>其他内容</p></body></html>")
        let options = ReplaceOptions()
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京某某科技",
                                                         options: options), 1)

        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "北京某某科技",
                                                        replaceWith: "上海新兴", options: options)
        XCTAssertEqual(count, 1)
        let text = try plainText(of: out)
        XCTAssertTrue(text.contains("上海新兴有限公司"), "实际文本：\(text)")
        XCTAssertFalse(text.contains("北京某某科技"))
    }

    func testStructuralSignatureUnchangedOnRealDocx() throws {
        let data = try makeDocx(html: "<html><body><p>待替换文字 测试</p></body></html>")
        let archiveBefore = try ZipArchive(data: data)
        let xmlBefore = String(decoding:
            try archiveBefore.contents(of: try XCTUnwrap(archiveBefore.entry(named: "word/document.xml"))),
            as: UTF8.self)

        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "待替换", replaceWith: "已修改",
                                                    options: ReplaceOptions())
        let archiveAfter = try ZipArchive(data: out)
        let xmlAfter = String(decoding:
            try archiveAfter.contents(of: try XCTUnwrap(archiveAfter.entry(named: "word/document.xml"))),
            as: UTF8.self)

        XCTAssertEqual(try DocxFixture.structuralSignature(xmlBefore),
                       try DocxFixture.structuralSignature(xmlAfter))
    }

    func testAllNonTargetPartsAreByteIdentical() throws {
        let data = try makeDocx(html: "<html><body><p>旧名 公司</p></body></html>")
        let before = try ZipArchive(data: data)
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                    options: ReplaceOptions())
        let after = try ZipArchive(data: out)
        for entry in before.entries where entry.name != "word/document.xml" {
            guard let afterEntry = after.entry(named: entry.name) else {
                XCTFail("条目丢失：\(entry.name)"); continue
            }
            XCTAssertEqual(try before.rawData(of: entry), try after.rawData(of: afterEntry),
                           "未改动条目应字节级一致：\(entry.name)")
        }
    }
}
```

- [ ] **Step 2: 运行测试**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/EndToEndTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`，3 个测试通过。

- [ ] **Step 3: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplaceTests/EndToEndTests.swift
git commit -m "test: 真实 docx 端到端替换与字节级一致性验证"
```

---

## Task 12: 文件扫描与备份

**Files:**
- Create: `DocxReplace/Core/FileScanner.swift`
- Create: `DocxReplace/Core/BackupManager.swift`
- Test: `DocxReplaceTests/FileScannerTests.swift`
- Test: `DocxReplaceTests/BackupManagerTests.swift`

- [ ] **Step 1: 写失败测试 `DocxReplaceTests/FileScannerTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class FileScannerTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("FileScannerTests-\(UUID().uuidString)")
        let fm = FileManager.default
        try fm.createDirectory(at: root.appendingPathComponent("子目录"), withIntermediateDirectories: true)
        try fm.createDirectory(at: root.appendingPathComponent(".hidden"), withIntermediateDirectories: true)
        for path in ["A.docx", "子目录/B.docx", "旧.doc", "子目录/旧.doc", "说明.txt", "忽略.md", "~$锁文件.docx"] {
            try Data("x".utf8).write(to: root.appendingPathComponent(path))
        }
        try Data("x".utf8).write(to: root.appendingPathComponent(".hidden/C.docx"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testFindsOnlyWordFilesRecursively() {
        let items = FileScanner.scan(folder: root)
        // 不比较顺序：排序用了本地化比较，顺序随系统语言变化
        XCTAssertEqual(Set(items.map(\.relativePath)),
                       Set(["A.docx", "子目录/B.docx", "子目录/旧.doc", "旧.doc"]))
    }

    func testClassifiesKinds() {
        let items = FileScanner.scan(folder: root)
        XCTAssertEqual(items.first { $0.relativePath == "A.docx" }?.kind, .docx)
        XCTAssertEqual(items.first { $0.relativePath == "旧.doc" }?.kind, .legacyDoc)
    }

    func testSkipsHiddenAndLockFiles() {
        let paths = FileScanner.scan(folder: root).map(\.relativePath)
        XCTAssertFalse(paths.contains { $0.contains(".hidden") })
        XCTAssertFalse(paths.contains { $0.contains("~$") })
    }
}
```

- [ ] **Step 2: 写失败测试 `DocxReplaceTests/BackupManagerTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class BackupManagerTests: XCTestCase {
    private var root: URL!
    private var source: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("BackupTests-\(UUID().uuidString)")
        source = root.appendingPathComponent("源文件夹")
        try FileManager.default.createDirectory(at: source.appendingPathComponent("子目录"),
                                                withIntermediateDirectories: true)
        try Data("原始内容".utf8).write(to: source.appendingPathComponent("子目录/文件.docx"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testBackupPreservesRelativePathAndContent() throws {
        let runDir = try BackupManager.makeRunDirectory(root: root.appendingPathComponent("备份"),
                                                        sourceFolder: source,
                                                        date: Date(timeIntervalSince1970: 0))
        try BackupManager.backup(fileURL: source.appendingPathComponent("子目录/文件.docx"),
                                 sourceFolder: source, runDirectory: runDir)
        let restored = runDir.appendingPathComponent("子目录/文件.docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: restored.path))
        XCTAssertEqual(try Data(contentsOf: restored), Data("原始内容".utf8))
    }

    func testRunDirectoryIncludesSourceFolderName() throws {
        let runDir = try BackupManager.makeRunDirectory(root: root.appendingPathComponent("备份"),
                                                        sourceFolder: source,
                                                        date: Date(timeIntervalSince1970: 0))
        XCTAssertEqual(runDir.lastPathComponent, "源文件夹")
        XCTAssertTrue(runDir.path.contains("DocxReplace备份_"))
    }

    func testBackupOverwritesExistingCopy() throws {
        let runDir = try BackupManager.makeRunDirectory(root: root.appendingPathComponent("备份"),
                                                        sourceFolder: source, date: Date())
        let file = source.appendingPathComponent("子目录/文件.docx")
        try BackupManager.backup(fileURL: file, sourceFolder: source, runDirectory: runDir)
        try Data("改过了".utf8).write(to: file)
        try BackupManager.backup(fileURL: file, sourceFolder: source, runDirectory: runDir)
        let restored = runDir.appendingPathComponent("子目录/文件.docx")
        XCTAssertEqual(try Data(contentsOf: restored), Data("改过了".utf8))
    }
}
```

- [ ] **Step 3: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/FileScannerTests -only-testing:DocxReplaceTests/BackupManagerTests 2>&1 | tail -20
```

Expected: 编译失败，找不到 `FileScanner` / `BackupManager`。

- [ ] **Step 4: 写 `DocxReplace/Core/FileScanner.swift`**

```swift
import Foundation

enum FileScanner {
    static func scan(folder: URL) -> [ScanItem] {
        let fm = FileManager.default
        guard let enumerator = fm.enumerator(at: folder,
                                             includingPropertiesForKeys: [.isRegularFileKey],
                                             options: [.skipsHiddenFiles, .skipsPackageDescendants]) else {
            return []
        }
        let basePath = folder.standardizedFileURL.path
        var items: [ScanItem] = []
        for case let url as URL in enumerator {
            let name = url.lastPathComponent
            if name.hasPrefix("~$") { continue }
            let kind: FileKind
            switch url.pathExtension.lowercased() {
            case "docx": kind = .docx
            case "doc": kind = .legacyDoc
            default: continue
            }
            let path = url.standardizedFileURL.path
            let relative = path.hasPrefix(basePath + "/") ? String(path.dropFirst(basePath.count + 1)) : name
            items.append(ScanItem(url: url, relativePath: relative, kind: kind))
        }
        return items.sorted { $0.relativePath.localizedStandardCompare($1.relativePath) == .orderedAscending }
    }
}
```

- [ ] **Step 5: 写 `DocxReplace/Core/BackupManager.swift`**

```swift
import Foundation

enum BackupManager {
    /// 优先 App 所在文件夹；不可写或位于 DerivedData（Xcode 直接运行）时退回 ~/Documents
    static func defaultRoot() -> URL {
        let appFolder = Bundle.main.bundleURL.deletingLastPathComponent()
        if appFolder.path.contains("/DerivedData/")
            || !FileManager.default.isWritableFile(atPath: appFolder.path) {
            let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
                ?? FileManager.default.homeDirectoryForCurrentUser
            return docs.appendingPathComponent("DocxReplace备份", isDirectory: true)
        }
        return appFolder
    }

    static func makeRunDirectory(root: URL, sourceFolder: URL, date: Date) throws -> URL {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd_HH-mm-ss"
        let run = root
            .appendingPathComponent("DocxReplace备份_\(formatter.string(from: date))", isDirectory: true)
            .appendingPathComponent(sourceFolder.lastPathComponent, isDirectory: true)
        try FileManager.default.createDirectory(at: run, withIntermediateDirectories: true)
        return run
    }

    static func backup(fileURL: URL, sourceFolder: URL, runDirectory: URL) throws {
        let base = sourceFolder.standardizedFileURL.path
        let path = fileURL.standardizedFileURL.path
        let relative = path.hasPrefix(base + "/") ? String(path.dropFirst(base.count + 1)) : fileURL.lastPathComponent
        let destination = runDirectory.appendingPathComponent(relative)
        let fm = FileManager.default
        try fm.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
        if fm.fileExists(atPath: destination.path) {
            try fm.removeItem(at: destination)
        }
        try fm.copyItem(at: fileURL, to: destination)
    }
}
```

- [ ] **Step 6: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/FileScannerTests -only-testing:DocxReplaceTests/BackupManagerTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，6 个测试全部通过。

- [ ] **Step 7: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/FileScanner.swift DocxReplace/Core/BackupManager.swift DocxReplaceTests/FileScannerTests.swift DocxReplaceTests/BackupManagerTests.swift
git commit -m "feat: 递归扫描与备份管理"
```

---

## Task 13: 扫描/替换编排

**Files:**
- Create: `DocxReplace/Core/ReplaceCoordinator.swift`
- Test: `DocxReplaceTests/ReplaceCoordinatorTests.swift`

- [ ] **Step 1: 写失败测试 `DocxReplaceTests/ReplaceCoordinatorTests.swift`**

```swift
import XCTest
@testable import DocxReplace

final class ReplaceCoordinatorTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = URL(fileURLWithPath: NSTemporaryDirectory())
            .appendingPathComponent("CoordinatorTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("子目录"),
                                                withIntermediateDirectories: true)
        let fm = FileManager.default
        try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["北京", "公司"]))
            .write(to: root.appendingPathComponent("A.docx"))
        try DocxFixture.docx(bodyXML: DocxFixture.paragraph(["无关内容"]))
            .write(to: root.appendingPathComponent("子目录/B.docx"))
        try Data("legacy".utf8).write(to: root.appendingPathComponent("旧.doc"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testScanReportsMatchesAndSkipsLegacyDoc() async {
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        XCTAssertEqual(results.count, 3)
        let matched = results.filter { $0.matchCount > 0 }
        XCTAssertEqual(matched.map(\.relativePath), ["A.docx"])
        XCTAssertEqual(matched.first?.matchCount, 1)

        let legacy = results.first { $0.relativePath == "旧.doc" }
        if case .unsupported(let reason)? = legacy?.outcome {
            XCTAssertTrue(reason.contains("docx"))
        } else {
            XCTFail("过期 .doc 应标记为不支持")
        }

        let noMatch = results.first { $0.relativePath == "子目录/B.docx" }
        XCTAssertEqual(noMatch?.outcome, .noMatch)
    }

    func testScanProgressReachesTotal() async {
        // 并发扫描时进度回调来自多个线程，只断言「见过的最大值」
        final class MaxTracker: @unchecked Sendable {
            private let lock = NSLock()
            private var value = 0
            func record(_ v: Int) { lock.lock(); value = max(value, v); lock.unlock() }
            var maxSeen: Int { lock.lock(); defer { lock.unlock() }; return value }
        }
        let tracker = MaxTracker()
        _ = await ReplaceCoordinator.scan(folder: root, find: "北京公司", options: ReplaceOptions()) { progress in
            tracker.record(progress.completed)
        }
        XCTAssertEqual(tracker.maxSeen, 3)
    }

    func testReplaceWritesBackupAndModifiesFile() async throws {
        let backupRoot = root.appendingPathComponent("备份")
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        let items = results.filter { $0.matchCount > 0 }.map(\.item)

        let report = await ReplaceCoordinator.replace(items: items, sourceFolder: root,
                                                      find: "北京公司", replaceWith: "上海集团",
                                                      options: ReplaceOptions(), backupEnabled: true,
                                                      backupRoot: backupRoot) { _ in }
        XCTAssertEqual(report.modifiedFiles, 1)
        XCTAssertEqual(report.replacedCount, 1)
        XCTAssertTrue(report.failed.isEmpty)

        let data = try Data(contentsOf: root.appendingPathComponent("A.docx"))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "上海集团",
                                                         options: ReplaceOptions()), 1)

        let backupDir = try XCTUnwrap(report.backupDirectory)
        let backedUp = backupDir.appendingPathComponent("A.docx")
        XCTAssertTrue(FileManager.default.fileExists(atPath: backedUp.path))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: Data(contentsOf: backedUp),
                                                         find: "北京公司", options: ReplaceOptions()), 1)
    }

    func testReplaceWithoutBackupDoesNotCreateDirectory() async throws {
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        let items = results.filter { $0.matchCount > 0 }.map(\.item)
        let report = await ReplaceCoordinator.replace(items: items, sourceFolder: root,
                                                      find: "北京公司", replaceWith: "上海集团",
                                                      options: ReplaceOptions(), backupEnabled: false,
                                                      backupRoot: root.appendingPathComponent("备份")) { _ in }
        XCTAssertNil(report.backupDirectory)
        XCTAssertEqual(report.modifiedFiles, 1)
    }

    func testCorruptFileIsReportedNotFatal() async throws {
        try Data("这不是 zip".utf8).write(to: root.appendingPathComponent("坏.docx"))
        let results = await ReplaceCoordinator.scan(folder: root, find: "北京公司",
                                                    options: ReplaceOptions()) { _ in }
        let broken = results.first { $0.relativePath == "坏.docx" }
        if case .failed(let reason)? = broken?.outcome {
            XCTAssertFalse(reason.isEmpty)
        } else {
            XCTFail("损坏文件应标记为失败")
        }

        let items = results.filter { $0.matchCount > 0 }.map(\.item)
        let report = await ReplaceCoordinator.replace(items: items, sourceFolder: root,
                                                      find: "北京公司", replaceWith: "上海集团",
                                                      options: ReplaceOptions(), backupEnabled: true,
                                                      backupRoot: root.appendingPathComponent("备份")) { _ in }
        XCTAssertEqual(report.modifiedFiles, 1, "坏文件不应影响其他文件")
    }
}
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ReplaceCoordinatorTests 2>&1 | tail -20
```

Expected: 编译失败，`cannot find 'ReplaceCoordinator' in scope`。

- [ ] **Step 3: 写 `DocxReplace/Core/ReplaceCoordinator.swift`**

```swift
import Foundation

struct ScanProgress: Equatable {
    var completed: Int
    var total: Int
}

struct ReplaceProgress: Equatable {
    var completed: Int
    var total: Int
    var currentPath: String
}

enum ReplaceCoordinator {
    /// 并行扫描（并发上限为 CPU 核数），返回按路径排序的结果
    static func scan(folder: URL, find: String, options: ReplaceOptions,
                     onProgress: @escaping (ScanProgress) -> Void) async -> [FileScanResult] {
        let items = FileScanner.scan(folder: folder)
        let total = items.count
        guard total > 0 else {
            onProgress(ScanProgress(completed: 0, total: 0))
            return []
        }

        var collected: [FileScanResult?] = Array(repeating: nil, count: total)
        var completed = 0
        await withTaskGroup(of: (Int, FileScanResult).self) { group in
            let limit = max(2, ProcessInfo.processInfo.activeProcessorCount)
            var next = 0
            while next < min(limit, total) {
                let index = next
                group.addTask { (index, analyze(items[index], find: find, options: options)) }
                next += 1
            }
            while let (index, result) = await group.next() {
                collected[index] = result
                completed += 1
                onProgress(ScanProgress(completed: completed, total: total))
                if next < total {
                    let pending = next
                    group.addTask { (pending, analyze(items[pending], find: find, options: options)) }
                    next += 1
                }
            }
        }
        return collected.compactMap { $0 }
    }

    /// 串行替换；仅处理传入的条目。备份失败则跳过该文件
    static func replace(items: [ScanItem], sourceFolder: URL, find: String, replaceWith: String,
                        options: ReplaceOptions, backupEnabled: Bool, backupRoot: URL,
                        onProgress: @escaping (ReplaceProgress) -> Void) async -> ReplaceReport {
        var report = ReplaceReport()
        guard !items.isEmpty else { return report }

        var runDirectory: URL?
        if backupEnabled {
            do {
                runDirectory = try BackupManager.makeRunDirectory(root: backupRoot,
                                                                  sourceFolder: sourceFolder,
                                                                  date: Date())
                report.backupDirectory = runDirectory
            } catch {
                report.failed.append(ReportedFile(path: sourceFolder.lastPathComponent,
                                                  reason: "无法创建备份目录，已中止：\(error.localizedDescription)"))
                return report
            }
        }

        let total = items.count
        for (index, item) in items.enumerated() {
            if Task.isCancelled {
                report.cancelled = true
                break
            }
            onProgress(ReplaceProgress(completed: index, total: total, currentPath: item.relativePath))
            do {
                let data = try Data(contentsOf: item.url)
                let (newData, count) = try DocxTextReplacer.replace(docxData: data, find: find,
                                                                    replaceWith: replaceWith,
                                                                    options: options)
                guard count > 0 else { continue }
                if let runDirectory {
                    do {
                        try BackupManager.backup(fileURL: item.url, sourceFolder: sourceFolder,
                                                 runDirectory: runDirectory)
                    } catch {
                        report.failed.append(ReportedFile(path: item.relativePath,
                                                          reason: "备份失败，已跳过：\(error.localizedDescription)"))
                        continue
                    }
                }
                try newData.write(to: item.url, options: [.atomic])
                report.modifiedFiles += 1
                report.replacedCount += count
            } catch {
                report.failed.append(ReportedFile(path: item.relativePath, reason: describe(error)))
            }
        }
        onProgress(ReplaceProgress(completed: total, total: total, currentPath: ""))
        return report
    }

    private static func analyze(_ item: ScanItem, find: String, options: ReplaceOptions) -> FileScanResult {
        switch item.kind {
        case .legacyDoc:
            return FileScanResult(item: item, outcome: .unsupported("旧版 .doc 需先转为 .docx"))
        case .docx:
            do {
                let data = try Data(contentsOf: item.url)
                let count = try DocxTextReplacer.countMatches(docxData: data, find: find, options: options)
                return FileScanResult(item: item, outcome: count > 0 ? .matched(count) : .noMatch)
            } catch {
                return FileScanResult(item: item, outcome: .failed(describe(error)))
            }
        }
    }

    static func describe(_ error: Error) -> String {
        if let zip = error as? ZipError { return zip.message }
        if let xml = error as? DocxXmlError { return xml.message }
        return error.localizedDescription
    }
}
```

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ReplaceCoordinatorTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，5 个测试全部通过。

- [ ] **Step 5: 跑全部测试**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 6: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ReplaceCoordinator.swift DocxReplaceTests/ReplaceCoordinatorTests.swift
git commit -m "feat: 扫描与替换编排，含进度回调、备份与错误隔离"
```

---

## Task 14: SwiftUI 界面

**Files:**
- Create: `DocxReplace/AppViewModel.swift`
- Modify: `DocxReplace/ContentView.swift`

- [ ] **Step 1: 写 `DocxReplace/AppViewModel.swift`**

```swift
import AppKit
import Foundation

enum Phase: Equatable {
    case idle
    case scanning
    case scanned
    case replacing
    case finished
}

@MainActor
final class AppViewModel: ObservableObject {
    @Published var folderURL: URL?
    @Published var findText = ""
    @Published var replaceText = ""
    @Published var caseSensitive = false
    @Published var wholeWord = false
    @Published var backupEnabled = true
    @Published var phase: Phase = .idle
    @Published var results: [FileScanResult] = []
    @Published var statusText = "选择文件夹并输入查找内容"
    @Published var progress: Double = 0
    @Published var currentFile = ""
    @Published var backupDirectory: URL?
    @Published var alertMessage: String?
    @Published var showReplaceConfirmation = false

    private var runningTask: Task<Void, Never>?

    var options: ReplaceOptions {
        ReplaceOptions(caseSensitive: caseSensitive, wholeWord: wholeWord)
    }

    var matchedItems: [ScanItem] {
        results.compactMap { result in
            if case .matched = result.outcome { return result.item }
            return nil
        }
    }

    var totalMatches: Int {
        results.reduce(0) { $0 + $1.matchCount }
    }

    var validationMessage: String? {
        if folderURL == nil { return "请先选择文件夹" }
        if findText.isEmpty { return "请输入要查找的内容" }
        if findText.contains("\n") || findText.contains("\r") { return "查找内容不能包含换行符" }
        if replaceText.contains("\n") || replaceText.contains("\r") { return "替换内容不能包含换行符" }
        if Self.hasIllegalControlCharacter(findText) { return "查找内容包含无法写入文档的控制字符" }
        if Self.hasIllegalControlCharacter(replaceText) { return "替换内容包含无法写入文档的控制字符" }
        return nil
    }

    /// XML 1.0 不允许 C0 控制字符（\t 除外）与 U+FFFE/U+FFFF。
    /// 它们无法被转义成合法 XML，粘贴进来的话会让整份文件写出后无法解析。
    private static func hasIllegalControlCharacter(_ text: String) -> Bool {
        text.unicodeScalars.contains {
            ($0.value < 0x20 && $0 != "\t") || $0.value == 0xFFFE || $0.value == 0xFFFF
        }
    }

    var isBusy: Bool { phase == .scanning || phase == .replacing }
    var canScan: Bool { validationMessage == nil && !isBusy }
    var canReplace: Bool { validationMessage == nil && !isBusy && !matchedItems.isEmpty }

    func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "选择"
        panel.message = "选择要处理的文件夹"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        folderURL = url
        results = []
        phase = .idle
        statusText = "已选择：\(url.path)"
    }

    func scan() {
        guard let folder = folderURL, validationMessage == nil else { return }
        let find = findText
        let options = self.options
        phase = .scanning
        progress = 0
        currentFile = ""
        statusText = "正在扫描…"
        runningTask = Task { [weak self] in
            let results = await ReplaceCoordinator.scan(folder: folder, find: find, options: options) { p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p.total == 0 ? 1 : Double(p.completed) / Double(p.total)
                    self.statusText = "正在扫描 \(p.completed)/\(p.total)…"
                }
            }
            guard let self, !Task.isCancelled else { return }
            self.results = results
            self.phase = .scanned
            let matched = self.matchedItems.count
            self.progress = 1
            if results.isEmpty {
                self.statusText = "文件夹中没有 .docx 或 .doc 文件"
            } else if matched == 0 {
                self.statusText = "没有找到匹配内容"
            } else {
                self.statusText = "\(matched) 个文件命中，共 \(self.totalMatches) 处"
            }
        }
    }

    func requestReplace() {
        guard canReplace else { return }
        showReplaceConfirmation = true
    }

    func confirmReplace() {
        guard let folder = folderURL else { return }
        let find = findText
        let replaceWith = replaceText
        let options = self.options
        let items = matchedItems
        let backup = backupEnabled
        let backupRoot = BackupManager.defaultRoot()

        phase = .replacing
        progress = 0
        statusText = "正在替换…"
        runningTask = Task { [weak self] in
            let report = await ReplaceCoordinator.replace(items: items, sourceFolder: folder,
                                                          find: find, replaceWith: replaceWith,
                                                          options: options, backupEnabled: backup,
                                                          backupRoot: backupRoot) { p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p.total == 0 ? 1 : Double(p.completed) / Double(p.total)
                    self.currentFile = p.currentPath
                    self.statusText = "正在处理 \(p.completed)/\(p.total)"
                }
            }
            guard let self else { return }
            self.backupDirectory = report.backupDirectory
            self.phase = .finished
            self.progress = 1
            self.currentFile = ""
            if report.modifiedFiles == 0, let firstFailure = report.failed.first {
                // 典型情形：备份目录建不了或全部文件失败，必须显式告知
                self.alertMessage = firstFailure.reason
                self.statusText = "未修改任何文件"
            } else {
                var summary = report.cancelled ? "已取消。" : ""
                summary += "完成：修改 \(report.modifiedFiles) 个文件，共替换 \(report.replacedCount) 处"
                if !report.failed.isEmpty { summary += "；\(report.failed.count) 个文件失败" }
                self.statusText = summary
            }
            self.rescanAfterReplace()
        }
    }

    func cancel() {
        runningTask?.cancel()
    }

    private func rescanAfterReplace() {
        guard let folder = folderURL else { return }
        let find = findText
        let options = self.options
        runningTask = Task { [weak self] in
            let results = await ReplaceCoordinator.scan(folder: folder, find: find, options: options) { _ in }
            guard let self else { return }
            self.results = results
            self.phase = .finished
        }
    }

    func openBackupFolder() {
        guard let url = backupDirectory else { return }
        NSWorkspace.shared.open(url)
    }

    func revealFolder() {
        guard let url = folderURL else { return }
        NSWorkspace.shared.open(url)
    }
}
```

- [ ] **Step 2: 替换 `DocxReplace/ContentView.swift`**

```swift
import SwiftUI

struct ContentView: View {
    @StateObject private var model = AppViewModel()

    var body: some View {
        VStack(spacing: 0) {
            form
            Divider()
            resultList
            Divider()
            statusBar
        }
        .alert("确认替换", isPresented: $model.showReplaceConfirmation) {
            Button("取消", role: .cancel) {}
            Button("开始替换") { model.confirmReplace() }
        } message: {
            Text("将修改 \(model.matchedItems.count) 个文件，共 \(model.totalMatches) 处。是否继续？")
        }
        .alert("出错了", isPresented: Binding(get: { model.alertMessage != nil },
                                             set: { if !$0 { model.alertMessage = nil } })) {
            Button("好", role: .cancel) {}
        } message: {
            Text(model.alertMessage ?? "")
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("文件夹").frame(width: 56, alignment: .trailing)
                Text(model.folderURL?.path ?? "未选择")
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundStyle(model.folderURL == nil ? .secondary : .primary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Button("选择…") { model.chooseFolder() }
            }
            HStack {
                Text("查找").frame(width: 56, alignment: .trailing)
                TextField("要查找的文字", text: $model.findText)
            }
            HStack {
                Text("替换为").frame(width: 56, alignment: .trailing)
                TextField("替换成什么（可留空表示删除）", text: $model.replaceText)
            }
            HStack(spacing: 16) {
                Spacer().frame(width: 56)
                Toggle("区分大小写", isOn: $model.caseSensitive)
                Toggle("全字匹配", isOn: $model.wholeWord)
                Toggle("替换前备份", isOn: $model.backupEnabled)
            }
            HStack(spacing: 12) {
                Spacer().frame(width: 56)
                Button("扫描") { model.scan() }
                    .disabled(!model.canScan)
                Button("全部替换") { model.requestReplace() }
                    .disabled(!model.canReplace)
                if model.isBusy {
                    Button("取消") { model.cancel() }
                }
                if let message = model.validationMessage, !model.isBusy {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
    }

    private var resultList: some View {
        List(model.results) { result in
            HStack(spacing: 8) {
                Image(systemName: icon(for: result.outcome))
                    .foregroundStyle(color(for: result.outcome))
                Text(result.relativePath)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Spacer()
                Text(detail(for: result.outcome))
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            .opacity(isDimmed(result.outcome) ? 0.55 : 1)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .overlay {
            if model.results.isEmpty {
                Text(model.isBusy ? "处理中…" : "扫描结果会显示在这里")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var statusBar: some View {
        VStack(spacing: 6) {
            if model.isBusy {
                ProgressView(value: model.progress)
                    .progressViewStyle(.linear)
            }
            HStack {
                Text(model.statusText).font(.callout).lineLimit(2)
                Spacer()
                if model.backupDirectory != nil {
                    Button("打开备份文件夹") { model.openBackupFolder() }
                }
                if model.folderURL != nil {
                    Button("在访达中显示") { model.revealFolder() }
                }
            }
        }
        .padding(10)
    }

    private func icon(for outcome: FileOutcome) -> String {
        switch outcome {
        case .matched: return "doc.text.fill"
        case .noMatch: return "doc.text"
        case .unsupported: return "exclamationmark.triangle"
        case .failed: return "xmark.octagon"
        }
    }

    private func color(for outcome: FileOutcome) -> Color {
        switch outcome {
        case .matched: return .accentColor
        case .noMatch: return .secondary
        case .unsupported: return .orange
        case .failed: return .red
        }
    }

    private func isDimmed(_ outcome: FileOutcome) -> Bool {
        if case .noMatch = outcome { return true }
        return false
    }

    private func detail(for outcome: FileOutcome) -> String {
        switch outcome {
        case .matched(let count): return "\(count) 处"
        case .noMatch: return "0 处"
        case .unsupported(let reason): return reason
        case .failed(let reason): return reason
        }
    }
}
```

- [ ] **Step 3: 构建并确认编译通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' build 2>&1 | tail -20
```

Expected: `** BUILD SUCCEEDED **`。

- [ ] **Step 4: 准备一个手工测试文件夹**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
mkdir -p /tmp/docx-manual-test/子目录
printf '<html><head><meta charset="utf-8"></head><body><p>北京某某科技有限公司</p><p>联系人：张三</p></body></html>' > /tmp/docx-manual-test/a.html
printf '<html><head><meta charset="utf-8"></head><body><p>本合同由北京某某科技有限公司签署</p></body></html>' > /tmp/docx-manual-test/b.html
/usr/bin/textutil -convert docx -output /tmp/docx-manual-test/合同A.docx /tmp/docx-manual-test/a.html
/usr/bin/textutil -convert docx -output /tmp/docx-manual-test/子目录/合同B.docx /tmp/docx-manual-test/b.html
/usr/bin/textutil -convert txt -stdout /tmp/docx-manual-test/合同A.docx
```

Expected: 最后一条命令输出包含「北京某某科技有限公司」。

- [ ] **Step 5: 启动 App 做手工验证**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' -showBuildSettings 2>/dev/null | grep -m1 "BUILT_PRODUCTS_DIR" | sed 's/.*= //'
```

用上一步得到的目录，运行 `open "<目录>/DocxReplace.app"`。

按以下顺序操作并确认：

1. 选择 `/tmp/docx-manual-test`，查找填「北京某某科技」，替换为「上海新兴」→ 点「扫描」
   - 期望：列表显示 `合同A.docx 1 处`、`子目录/合同B.docx 1 处`，状态栏「2 个文件命中，共 2 处」
2. 点「全部替换」→ 确认弹窗显示「将修改 2 个文件，共 2 处」→ 点「开始替换」
   - 期望：状态栏显示完成信息，列表刷新为 0 处
3. 点「打开备份文件夹」
   - 期望：访达打开备份目录，里面有 `合同A.docx` 与 `子目录/合同B.docx`，且内容仍是旧文字
4. 用 Word 打开 `/tmp/docx-manual-test/合同A.docx`
   - 期望：显示「上海新兴有限公司」，格式（字体、段落）与原来一致

```bash
/usr/bin/textutil -convert txt -stdout /tmp/docx-manual-test/合同A.docx
```

Expected: 输出含「上海新兴有限公司」，不含「北京某某科技」。

- [ ] **Step 6: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/AppViewModel.swift DocxReplace/ContentView.swift
git commit -m "feat: SwiftUI 界面，完成扫描-确认-替换-报告全流程"
```

---

## Task 15: 收尾验证

**Files:**
- 无新增文件

- [ ] **Step 1: 跑全部测试**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test 2>&1 | tail -5
```

Expected: `** TEST SUCCEEDED **`。

- [ ] **Step 2: 边界场景手工验证**

用一个含以下内容的文件夹测试并逐条确认：

1. 子文件夹嵌套两层 → 能被扫描到
2. 一个 `.doc` 文件 → 显示橙色提示「旧版 .doc 需先转为 .docx」
3. 一个改名的纯文本文件 `假的.docx` → 标记为红色「不是有效的 .docx 文件」
4. 查找不存在的词 → 状态栏「没有找到匹配内容」，「全部替换」按钮不可点
5. 查找内容里粘贴换行 → 出现「查找内容不能包含换行符」，按钮不可点
6. 备份开关关闭后再替换 → 「打开备份文件夹」按钮不出现
7. 粘贴含控制字符的内容（如 U+000B）→ 出现「包含无法写入文档的控制字符」，按钮不可点
8. 含图形/文本框的文档（Word 用 `mc:AlternateContent` 同时保存现代与兼容两套表示）→
   两套表示都会被替换，**命中计数可能大于肉眼可见的处数**，这是预期行为（保证两套表示一致），
   用 Word 打开确认显示结果正确即可

- [ ] **Step 3: 用真实 Word 文档验证格式**

请用户在 Microsoft Word 中打开一份真实的、带格式（字体、颜色、表格、页眉）的 `.docx`，复制一份到测试文件夹，执行替换后用 Word 打开对照检查。

- [ ] **Step 4: 最终提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git status --short
git add -A
git commit -m "chore: 收尾验证" --allow-empty
```

---

## 自检记录

**规格覆盖对照**

| 规格条目 | 实现任务 |
|---|---|
| 递归扫描文件夹 | Task 12 |
| 仅处理 .docx，.doc 提示转换 | Task 12、Task 13 |
| 区分大小写 / 全字匹配开关 | Task 7 |
| 正文、表格、页眉、页脚、文本框、脚注、尾注、批注 | Task 10（`targetPartNames`） |
| 先扫描预览再替换 | Task 13、Task 14 |
| 原地修改 + 自动备份 | Task 12、Task 13 |
| 备份到 App 所在文件夹，不可写时退回 ~/Documents | Task 12（`defaultRoot`） |
| 格式不变（XML 字节级） | Task 5、Task 6、Task 10、Task 11 |
| 跨 run 匹配 | Task 7 |
| 不跨段落 | Task 9、Task 10 |
| 不跨换行/制表符 | Task 9 |
| 不动域代码（instrText） | Task 9 |
| 不处理修订删除文字（delText） | Task 9 |
| 替换继承首个命中 run 的格式 | Task 7、Task 10 |
| 查找/替换词禁含换行 | Task 14（`validationMessage`） |
| 损坏/加密文档报告并跳过 | Task 3、Task 13 |
| 备份失败跳过该文件 | Task 13 |
| 原子写入 | Task 13（`.atomic`） |
| 进度与取消 | Task 13、Task 14 |
| 报告与打开备份文件夹 | Task 13、Task 14 |

**已知取舍**

- 手工编写的 `project.pbxproj` 是本计划最大的工程风险，Task 1 Step 9 给出了回退方案。
- `mc:Fallback` 中重复出现的文本会被计为两次命中（Word 对同一内容同时保存现代与兼容两种表示时），替换结果一致，仅计数偏大。属罕见情况。
- 写入使用 `.atomic`，会替换 inode，可能丢失 Finder 标签等扩展属性。
