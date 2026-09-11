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

（Task 13 会替换成真正的界面，这里只要能编译。）

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

    /// raw DEFLATE 解压。expectedSize 来自 ZIP 中央目录
    static func inflate(_ data: Data, expectedSize: Int) -> Data? {
        guard !data.isEmpty else { return expectedSize == 0 ? Data() : nil }
        guard expectedSize > 0 else { return nil }
        var capacity = expectedSize
        for _ in 0..<5 {
            var output = Data(count: capacity)
            let written = output.withUnsafeMutableBytes { dst -> Int in
                guard let dstBase = dst.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                return data.withUnsafeBytes { src -> Int in
                    guard let srcBase = src.bindMemory(to: UInt8.self).baseAddress else { return 0 }
                    return compression_decode_buffer(dstBase, capacity, srcBase, data.count, nil, COMPRESSION_ZLIB)
                }
            }
            if written > 0 {
                if written < capacity || written == expectedSize {
                    output.removeSubrange(written...)
                    return output
                }
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

Expected: `** TEST SUCCEEDED **`，5 个测试全部通过。

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
    static func makeRealDocx(text: String, into directory: URL) throws -> URL {
        let htmlURL = directory.appendingPathComponent("source.html")
        let docxURL = directory.appendingPathComponent("source.docx")
        try "<html><body><p>\(text)</p></body></html>".write(to: htmlURL, atomically: true, encoding: .utf8)
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
        let archive = try ZipArchive(data: ZipWriter.build([entry]))
        XCTAssertEqual(try archive.contents(of: try XCTUnwrap(archive.entry(named: "a.txt"))), payload)
    }

    func testDeflatedEntryRoundTrip() throws {
        let payload = Data(String(repeating: "hello world 你好 ", count: 200).utf8)
        let compressed = try XCTUnwrap(ZipCompression.deflate(payload))
        let entry = ZipOutputEntry(name: "dir/b.txt", dosTime: 0, dosDate: 0, method: 8,
                                   crc32: ZipCRC32.checksum(payload),
                                   uncompressedSize: UInt32(payload.count),
                                   externalAttributes: 0, compressedData: compressed)
        let archive = try ZipArchive(data: ZipWriter.build([entry]))
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
        let archive = try ZipArchive(data: ZipWriter.build([entry]))
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

## Task 4: ZIP 写出的完整性

**Files:**
- Modify: `DocxReplace/Core/ZipWriter.swift`
- Modify: `DocxReplaceTests/ZipArchiveTests.swift`

- [ ] **Step 1: 追加失败测试到 `DocxReplaceTests/ZipArchiveTests.swift`**

在 `ZipArchiveTests` 类中追加：

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
        let rebuilt = try ZipArchive(data: ZipWriter.build(outputs))
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
```

- [ ] **Step 2: 运行测试确认失败**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipArchiveTests 2>&1 | tail -20
```

Expected: 编译失败，`type 'ZipWriter' has no member 'makeEntry'` / `'copyEntry'`。

- [ ] **Step 3: 在 `DocxReplace/Core/ZipWriter.swift` 的 `ZipWriter` 内追加**

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

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ZipArchiveTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，9 个测试全部通过（其中 `testSystemUnzipAcceptsOurArchive` 证明我们产出的 ZIP 能被系统工具独立校验）。

- [ ] **Step 5: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/ZipWriter.swift DocxReplaceTests/ZipArchiveTests.swift
git commit -m "feat: ZIP 写出支持自动压缩选择与原样拷贝，通过系统 unzip 校验"
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

- [ ] **Step 4: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/XmlTextLocatorTests 2>&1 | tail -20
```

Expected: `** TEST SUCCEEDED **`，19 个测试全部通过。

- [ ] **Step 5: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/XmlTextLocator.swift DocxReplaceTests/XmlTextLocatorTests.swift
git commit -m "feat: w:t 文字改写，含 xml:space 补写与实体转义"
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
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "aBETA c".replacingOccurrences(of: " ", with: ""))])
    }

    func testReplaceWithEmptyStringDeletes() {
        let edits = ParagraphMatcher.replace(in: ["aXbXc"], find: "X", replaceWith: "", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "abc")])
    }

    func testReplaceMultipleMatchesInOneRun() {
        let edits = ParagraphMatcher.replace(in: ["old-old"], find: "old", replaceWith: "new", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "new-new")])
    }

    func testReplaceMultipleMatchesAcrossSameRuns() {
        let edits = ParagraphMatcher.replace(in: ["ab", "ab"], find: "ba", replaceWith: "X", options: options)
        XCTAssertEqual(edits, [ParagraphMatcher.Edit(textIndex: 0, newText: "aX")])
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

注意 `testReplaceWithLongerText` 的期望值写成 `"aBETAc"`，直接写字符串字面量即可，不要用 `replacingOccurrences`。

- [ ] **Step 2: 运行测试**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/ParagraphMatcherTests 2>&1 | tail -30
```

Expected: 全部通过（`** TEST SUCCEEDED **`）。若 `testReplaceMultipleMatchesAcrossSameRuns` 失败，检查 `matchRanges` 是否把 `"abab"` 中位置 1 的 `"ba"` 也算进去了——正确答案是只有 1 处（从 0 开始第 1 处命中后，搜索从命中末尾继续，剩下 `"ab"` 不含 `"ba"`）。

- [ ] **Step 3: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplaceTests/ParagraphMatcherTests.swift
git commit -m "test: 覆盖替换区间计算的各种情形"
```

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
        try DocxXmlAnalyzer.analyze([UInt8](xml.utf8))
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
                return
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
- Create: `DocxReplace/Core/DocxTextReplacer.swift`
- Create: `DocxReplaceTests/DocxFixture.swift`
- Test: `DocxReplaceTests/DocxTextReplacerTests.swift`

- [ ] **Step 1: 写夹具生成器 `DocxReplaceTests/DocxFixture.swift`**

```swift
import Foundation
@testable import DocxReplace

/// 用自研 ZIP 层拼出结构合法的 .docx，用于测试
enum DocxFixture {
    static func docx(bodyXML: String, extraParts: [(String, String)] = []) -> Data {
        var parts: [(String, String)] = [
            ("[Content_Types].xml", contentTypes(extraParts: extraParts.map(\.0))),
            ("_rels/.rels", rootRels),
            ("word/document.xml", documentXML(bodyXML: bodyXML)),
        ]
        parts.append(contentsOf: extraParts)
        let entries = parts.map {
            ZipWriter.makeEntry(name: $0.0, contents: Data($0.1.utf8), date: Date(timeIntervalSince1970: 0))
        }
        return ZipWriter.build(entries)
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
        let data = DocxFixture.docx(bodyXML: DocxFixture.paragraph(["北", "京", "公司"]))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 1)
    }

    func testReplaceKeepsStructureIdentical() throws {
        let data = DocxFixture.docx(bodyXML: """
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
        XCTAssertTrue(documentText(out).contains("上海集团"))
    }

    func testReplacementInheritsFirstRunFormatting() throws {
        let data = DocxFixture.docx(bodyXML: """
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
        let data = DocxFixture.docx(bodyXML: body, extraParts: [
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
        let data = DocxFixture.docx(bodyXML:
            DocxFixture.paragraph(["北京"]) + DocxFixture.paragraph(["公司"]))
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 0)
    }

    func testDoesNotMatchAcrossLineBreak() throws {
        let data = DocxFixture.docx(bodyXML:
            "<w:p><w:r><w:t>北京</w:t></w:r><w:r><w:br/></w:r><w:r><w:t>公司</w:t></w:r></w:p>")
        XCTAssertEqual(try DocxTextReplacer.countMatches(docxData: data, find: "北京公司", options: options), 0)
    }

    func testNoMatchLeavesDataUntouched() throws {
        let data = DocxFixture.docx(bodyXML: DocxFixture.paragraph(["内容"]))
        let (out, count) = try DocxTextReplacer.replace(docxData: data, find: "不存在", replaceWith: "x",
                                                        options: options)
        XCTAssertEqual(count, 0)
        XCTAssertEqual(out, data, "没有命中时不应重写文件")
    }

    func testEntitiesSurviveReplacement() throws {
        let data = DocxFixture.docx(bodyXML: DocxFixture.paragraph(["a &amp; b"]))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "& b", replaceWith: "<c>",
                                                    options: options)
        XCTAssertTrue(try documentText(out).contains("a &amp; &lt;c&gt;"))
    }

    func testSpacesAtEdgesGetPreserveSpace() throws {
        let data = DocxFixture.docx(bodyXML: DocxFixture.paragraph(["X Y"]))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "X", replaceWith: " X ",
                                                    options: options)
        XCTAssertTrue(try documentText(out).contains("xml:space=\"preserve\""))
    }

    func testUntouchedEntriesAreByteIdentical() throws {
        let data = DocxFixture.docx(bodyXML: DocxFixture.paragraph(["旧名"]))
        let before = try ZipArchive(data: data)
        let rawBefore = try before.rawData(of: try XCTUnwrap(before.entry(named: "_rels/.rels")))
        let (out, _) = try DocxTextReplacer.replace(docxData: data, find: "旧名", replaceWith: "新名",
                                                    options: options)
        let after = try ZipArchive(data: out)
        let rawAfter = try after.rawData(of: try XCTUnwrap(after.entry(named: "_rels/.rels")))
        XCTAssertEqual(rawBefore, rawAfter)
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

        var partEdits: [String: (edits: [Int: String], count: Int)] = [:]
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
                partEdits[name] = (edits, count)
            }
        }
        guard !partEdits.isEmpty else { return (docxData, 0) }

        var outputs: [ZipOutputEntry] = []
        var total = 0
        for entry in archive.entries {
            if let changed = partEdits[entry.name] {
                let xml = [UInt8](try archive.contents(of: entry))
                let newXML = XmlTextLocator.rebuild(xml: xml, edits: changed.edits)
                outputs.append(ZipWriter.makeEntry(name: entry.name, contents: Data(newXML),
                                                   date: Date(),
                                                   externalAttributes: entry.externalAttributes))
                total += changed.count
            } else {
                outputs.append(ZipWriter.copyEntry(entry, raw: try archive.rawData(of: entry)))
            }
        }
        return (ZipWriter.build(outputs), total)
    }
}
```

- [ ] **Step 5: 运行测试确认通过**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
xcodebuild -project DocxReplace.xcodeproj -scheme DocxReplace -destination 'platform=macOS' test -only-testing:DocxReplaceTests/DocxTextReplacerTests 2>&1 | tail -30
```

Expected: `** TEST SUCCEEDED **`，10 个测试全部通过。

- [ ] **Step 6: 提交**

```bash
cd /Users/LB/Documents/AIProjects/DocxRepleace
git add DocxReplace/Core/DocxTextReplacer.swift DocxReplaceTests/DocxFixture.swift DocxReplaceTests/DocxTextReplacerTests.swift
git commit -m "feat: .docx 替换主流程，覆盖页眉页脚文本框，结构保持不变"
```

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
        try html.write(to: htmlURL, atomically: true, encoding: .utf8)
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
        return nil
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
printf '<html><body><p>北京某某科技有限公司</p><p>联系人：张三</p></body></html>' > /tmp/docx-manual-test/a.html
printf '<html><body><p>本合同由北京某某科技有限公司签署</p></body></html>' > /tmp/docx-manual-test/b.html
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
