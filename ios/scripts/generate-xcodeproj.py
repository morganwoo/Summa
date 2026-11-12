#!/usr/bin/env python3
"""Regenerates Summa.xcodeproj. The project uses file-system-synchronized groups
(Xcode 16+), so adding or removing source files never requires rerunning this."""
import hashlib, os

def uid(name):
    return hashlib.md5(("summa:" + name).encode()).hexdigest()[:24].upper()

TEAM = ""
BUNDLE = "app.summa.Summa"

def settings(d, indent=4):
    pad = "\t" * indent
    out = []
    for k in sorted(d):
        v = d[k]
        if isinstance(v, list):
            out.append(f"{pad}{k} = (\n" + "".join(f"{pad}\t\"{x}\",\n" for x in v) + f"{pad});")
        else:
            out.append(f'{pad}{k} = "{v}";' if not str(v).replace("_", "").replace(".", "").isalnum() or v == "" else f"{pad}{k} = {v};")
    return "\n".join(out)

project_common = {
    "ALWAYS_SEARCH_USER_PATHS": "NO", "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "GCC_C_LANGUAGE_STANDARD": "gnu17", "IPHONEOS_DEPLOYMENT_TARGET": "17.0",
    "SDKROOT": "iphoneos", "SWIFT_VERSION": "5.0", "LOCALIZATION_PREFERS_STRING_CATALOGS": "YES",
    "ASSETCATALOG_COMPILER_GENERATE_SWIFT_ASSET_SYMBOL_EXTENSIONS": "YES", "TARGETED_DEVICE_FAMILY": "1",
    "MARKETING_VERSION": "1.0", "CURRENT_PROJECT_VERSION": "1", "DEVELOPMENT_TEAM": TEAM, "CODE_SIGN_STYLE": "Automatic",
    # Empty = draft plans on device. Set to e.g. http://localhost:8787 to use the plan API in ../server.
    "SUMMA_API_BASE_URL": "",
}
project_debug = dict(project_common, DEBUG_INFORMATION_FORMAT="dwarf", ENABLE_TESTABILITY="YES", GCC_OPTIMIZATION_LEVEL="0",
                     ONLY_ACTIVE_ARCH="YES", SWIFT_ACTIVE_COMPILATION_CONDITIONS="DEBUG", SWIFT_OPTIMIZATION_LEVEL="-Onone",
                     GCC_PREPROCESSOR_DEFINITIONS=["DEBUG=1", "$(inherited)"])
project_release = dict(project_common, DEBUG_INFORMATION_FORMAT="dwarf-with-dsym", SWIFT_COMPILATION_MODE="wholemodule",
                       VALIDATE_PRODUCT="YES")

app = {
    "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon", "ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME": "AccentColor",
    "CODE_SIGN_ENTITLEMENTS": "Config/Summa.entitlements", "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/Summa-Info.plist", "INFOPLIST_KEY_UIApplicationSceneManifest_Generation": "YES",
    "INFOPLIST_KEY_UILaunchScreen_Generation": "YES",
    "INFOPLIST_KEY_UISupportedInterfaceOrientations": "UIInterfaceOrientationPortrait",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE, "PRODUCT_NAME": "$(TARGET_NAME)", "SWIFT_EMIT_LOC_STRINGS": "YES",
}
widget = {
    "CODE_SIGN_ENTITLEMENTS": "Config/SummaWidget.entitlements", "GENERATE_INFOPLIST_FILE": "YES",
    "INFOPLIST_FILE": "Config/SummaWidget-Info.plist", "INFOPLIST_KEY_CFBundleDisplayName": "Summa",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/Frameworks", "@executable_path/../../Frameworks"],
    "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ".Widget", "PRODUCT_NAME": "$(TARGET_NAME)", "SKIP_INSTALL": "YES",
    "SWIFT_EMIT_LOC_STRINGS": "YES",
}
uitests = {
    "GENERATE_INFOPLIST_FILE": "YES", "PRODUCT_BUNDLE_IDENTIFIER": BUNDLE + ".UITests", "PRODUCT_NAME": "$(TARGET_NAME)",
    "TEST_TARGET_NAME": "Summa",
}

targets = [
    dict(name="Summa", folder="Summa", product="Summa.app", ptype="com.apple.product-type.application",
         ftype="wrapper.application", settings=app, core=True),
    dict(name="SummaWidgetExtension", folder="SummaWidget", product="SummaWidgetExtension.appex",
         ptype="com.apple.product-type.app-extension", ftype="wrapper.app-extension", settings=widget, core=True),
    dict(name="SummaUITests", folder="SummaUITests", product="SummaUITests.xctest",
         ptype="com.apple.product-type.bundle.ui-testing", ftype="wrapper.cfbundle", settings=uitests, core=False),
]
config_files = ["Summa-Info.plist", "SummaWidget-Info.plist", "Summa.entitlements", "SummaWidget.entitlements"]

o = []
w = o.append
w("// !$*UTF8*$!\n{\n\tarchiveVersion = 1;\n\tclasses = {\n\t};\n\tobjectVersion = 77;\n\tobjects = {\n")

w("/* Begin PBXBuildFile section */")
for t in targets:
    if t["core"]:
        w(f"\t\t{uid('bf-core-'+t['name'])} /* SummaCore in Frameworks */ = {{isa = PBXBuildFile; productRef = {uid('dep-core-'+t['name'])} /* SummaCore */; }};")
w(f"\t\t{uid('bf-embed')} /* SummaWidgetExtension.appex in Embed Foundation Extensions */ = {{isa = PBXBuildFile; fileRef = {uid('prod-SummaWidgetExtension')} /* SummaWidgetExtension.appex */; settings = {{ATTRIBUTES = (RemoveHeadersOnCopy, ); }}; }};")
w("/* End PBXBuildFile section */\n")

w("/* Begin PBXContainerItemProxy section */")
for key, target in (("widget", "SummaWidgetExtension"), ("uitest", "Summa")):
    w(f"\t\t{uid('proxy-'+key)} /* PBXContainerItemProxy */ = {{\n\t\t\tisa = PBXContainerItemProxy;\n\t\t\tcontainerPortal = {uid('project')} /* Project object */;\n\t\t\tproxyType = 1;\n\t\t\tremoteGlobalIDString = {uid('target-'+target)};\n\t\t\tremoteInfo = {target};\n\t\t}};")
w("/* End PBXContainerItemProxy section */\n")

w("/* Begin PBXCopyFilesBuildPhase section */")
w(f"\t\t{uid('embed-phase')} /* Embed Foundation Extensions */ = {{\n\t\t\tisa = PBXCopyFilesBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tdstPath = \"\";\n\t\t\tdstSubfolderSpec = 13;\n\t\t\tfiles = (\n\t\t\t\t{uid('bf-embed')} /* SummaWidgetExtension.appex in Embed Foundation Extensions */,\n\t\t\t);\n\t\t\tname = \"Embed Foundation Extensions\";\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXCopyFilesBuildPhase section */\n")

w("/* Begin PBXFileReference section */")
for t in targets:
    w(f"\t\t{uid('prod-'+t['name'])} /* {t['product']} */ = {{isa = PBXFileReference; explicitFileType = {t['ftype']}; includeInIndex = 0; path = {t['product']}; sourceTree = BUILT_PRODUCTS_DIR; }};")
for f in config_files:
    kind = "text.plist.entitlements" if f.endswith(".entitlements") else "text.plist.xml"
    w(f"\t\t{uid('cfg-'+f)} /* {f} */ = {{isa = PBXFileReference; lastKnownFileType = {kind}; path = \"{f}\"; sourceTree = \"<group>\"; }};")
w("/* End PBXFileReference section */\n")

w("/* Begin PBXFileSystemSynchronizedRootGroup section */")
for t in targets:
    w(f"\t\t{uid('sync-'+t['folder'])} /* {t['folder']} */ = {{\n\t\t\tisa = PBXFileSystemSynchronizedRootGroup;\n\t\t\tpath = {t['folder']};\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
w("/* End PBXFileSystemSynchronizedRootGroup section */\n")

w("/* Begin PBXFrameworksBuildPhase section */")
for t in targets:
    files = f"\n\t\t\t\t{uid('bf-core-'+t['name'])} /* SummaCore in Frameworks */,\n\t\t\t" if t["core"] else "\n\t\t\t"
    w(f"\t\t{uid('fw-'+t['name'])} /* Frameworks */ = {{\n\t\t\tisa = PBXFrameworksBuildPhase;\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = ({files});\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
w("/* End PBXFrameworksBuildPhase section */\n")

w("/* Begin PBXGroup section */")
children = "".join(f"\t\t\t\t{uid('sync-'+t['folder'])} /* {t['folder']} */,\n" for t in targets)
w(f"\t\t{uid('group-main')} = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n{children}\t\t\t\t{uid('group-config')} /* Config */,\n\t\t\t\t{uid('group-products')} /* Products */,\n\t\t\t);\n\t\t\tsourceTree = \"<group>\";\n\t\t}};")
w(f"\t\t{uid('group-config')} /* Config */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "".join(f"\t\t\t\t{uid('cfg-'+f)} /* {f} */,\n" for f in config_files) + "\t\t\t);\n\t\t\tpath = Config;\n\t\t\tsourceTree = \"<group>\";\n\t\t};")
w(f"\t\t{uid('group-products')} /* Products */ = {{\n\t\t\tisa = PBXGroup;\n\t\t\tchildren = (\n" + "".join(f"\t\t\t\t{uid('prod-'+t['name'])} /* {t['product']} */,\n" for t in targets) + "\t\t\t);\n\t\t\tname = Products;\n\t\t\tsourceTree = \"<group>\";\n\t\t};")
w("/* End PBXGroup section */\n")

w("/* Begin PBXNativeTarget section */")
for t in targets:
    n = t["name"]
    phases = [f"{uid('src-'+n)} /* Sources */", f"{uid('fw-'+n)} /* Frameworks */", f"{uid('res-'+n)} /* Resources */"]
    deps = []
    if n == "Summa":
        phases.append(f"{uid('embed-phase')} /* Embed Foundation Extensions */")
        deps.append(f"{uid('tdep-widget')} /* PBXTargetDependency */")
    if n == "SummaUITests":
        deps.append(f"{uid('tdep-uitest')} /* PBXTargetDependency */")
    pk = f"\n\t\t\t\t{uid('dep-core-'+n)} /* SummaCore */,\n\t\t\t" if t["core"] else "\n\t\t\t"
    w(f"\t\t{uid('target-'+n)} /* {n} */ = {{\n\t\t\tisa = PBXNativeTarget;\n\t\t\tbuildConfigurationList = {uid('cl-'+n)} /* Build configuration list for PBXNativeTarget \"{n}\" */;\n\t\t\tbuildPhases = (\n"
      + "".join(f"\t\t\t\t{p},\n" for p in phases) + "\t\t\t);\n\t\t\tbuildRules = (\n\t\t\t);\n\t\t\tdependencies = (\n"
      + "".join(f"\t\t\t\t{d},\n" for d in deps) + f"\t\t\t);\n\t\t\tfileSystemSynchronizedGroups = (\n\t\t\t\t{uid('sync-'+t['folder'])} /* {t['folder']} */,\n\t\t\t);\n\t\t\tname = {n};\n\t\t\tpackageProductDependencies = ({pk});\n\t\t\tproductName = {n};\n\t\t\tproductReference = {uid('prod-'+n)} /* {t['product']} */;\n\t\t\tproductType = \"{t['ptype']}\";\n\t\t}};")
w("/* End PBXNativeTarget section */\n")

w("/* Begin PBXProject section */")
attrs = "".join(f"\t\t\t\t\t{uid('target-'+t['name'])} = {{\n\t\t\t\t\t\tCreatedOnToolsVersion = 16.0;\n" + (f"\t\t\t\t\t\tTestTargetID = {uid('target-Summa')};\n" if t['name']=='SummaUITests' else "") + "\t\t\t\t\t};\n" for t in targets)
w(f"\t\t{uid('project')} /* Project object */ = {{\n\t\t\tisa = PBXProject;\n\t\t\tattributes = {{\n\t\t\t\tBuildIndependentTargetsInParallel = 1;\n\t\t\t\tLastSwiftUpdateCheck = 1600;\n\t\t\t\tLastUpgradeCheck = 1600;\n\t\t\t\tTargetAttributes = {{\n{attrs}\t\t\t\t}};\n\t\t\t}};\n\t\t\tbuildConfigurationList = {uid('cl-project')} /* Build configuration list for PBXProject \"Summa\" */;\n\t\t\tdevelopmentRegion = en;\n\t\t\thasScannedForEncodings = 0;\n\t\t\tknownRegions = (\n\t\t\t\ten,\n\t\t\t\tBase,\n\t\t\t);\n\t\t\tmainGroup = {uid('group-main')};\n\t\t\tminimizedProjectReferenceProxies = 1;\n\t\t\tpackageReferences = (\n\t\t\t\t{uid('pkg-core')} /* XCLocalSwiftPackageReference \"SummaCore\" */,\n\t\t\t);\n\t\t\tpreferredProjectObjectVersion = 77;\n\t\t\tproductRefGroup = {uid('group-products')} /* Products */;\n\t\t\tprojectDirPath = \"\";\n\t\t\tprojectRoot = \"\";\n\t\t\ttargets = (\n"
  + "".join(f"\t\t\t\t{uid('target-'+t['name'])} /* {t['name']} */,\n" for t in targets) + "\t\t\t);\n\t\t};")
w("/* End PBXProject section */\n")

for section, key in (("PBXResourcesBuildPhase", "res"), ("PBXSourcesBuildPhase", "src")):
    w(f"/* Begin {section} section */")
    for t in targets:
        w(f"\t\t{uid(key+'-'+t['name'])} /* {'Resources' if key=='res' else 'Sources'} */ = {{\n\t\t\tisa = {section};\n\t\t\tbuildActionMask = 2147483647;\n\t\t\tfiles = (\n\t\t\t);\n\t\t\trunOnlyForDeploymentPostprocessing = 0;\n\t\t}};")
    w(f"/* End {section} section */\n")

w("/* Begin PBXTargetDependency section */")
for key, target in (("widget", "SummaWidgetExtension"), ("uitest", "Summa")):
    w(f"\t\t{uid('tdep-'+key)} /* PBXTargetDependency */ = {{\n\t\t\tisa = PBXTargetDependency;\n\t\t\ttarget = {uid('target-'+target)} /* {target} */;\n\t\t\ttargetProxy = {uid('proxy-'+key)} /* PBXContainerItemProxy */;\n\t\t}};")
w("/* End PBXTargetDependency section */\n")

w("/* Begin XCBuildConfiguration section */")
def config(name, key, d):
    w(f"\t\t{uid('cfg-'+key+'-'+name)} /* {name} */ = {{\n\t\t\tisa = XCBuildConfiguration;\n\t\t\tbuildSettings = {{\n{settings(d)}\n\t\t\t}};\n\t\t\tname = {name};\n\t\t}};")
config("Debug", "project", project_debug); config("Release", "project", project_release)
for t in targets:
    config("Debug", t["name"], t["settings"]); config("Release", t["name"], t["settings"])
w("/* End XCBuildConfiguration section */\n")

w("/* Begin XCConfigurationList section */")
for key, label in [("project", 'PBXProject "Summa"')] + [(t["name"], f'PBXNativeTarget "{t["name"]}"') for t in targets]:
    w(f"\t\t{uid('cl-'+key)} /* Build configuration list for {label} */ = {{\n\t\t\tisa = XCConfigurationList;\n\t\t\tbuildConfigurations = (\n\t\t\t\t{uid('cfg-'+key+'-Debug')} /* Debug */,\n\t\t\t\t{uid('cfg-'+key+'-Release')} /* Release */,\n\t\t\t);\n\t\t\tdefaultConfigurationIsVisible = 0;\n\t\t\tdefaultConfigurationName = Release;\n\t\t}};")
w("/* End XCConfigurationList section */\n")

w("/* Begin XCLocalSwiftPackageReference section */")
w(f"\t\t{uid('pkg-core')} /* XCLocalSwiftPackageReference \"SummaCore\" */ = {{\n\t\t\tisa = XCLocalSwiftPackageReference;\n\t\t\trelativePath = SummaCore;\n\t\t}};")
w("/* End XCLocalSwiftPackageReference section */\n")

w("/* Begin XCSwiftPackageProductDependency section */")
for t in targets:
    if t["core"]:
        w(f"\t\t{uid('dep-core-'+t['name'])} /* SummaCore */ = {{\n\t\t\tisa = XCSwiftPackageProductDependency;\n\t\t\tproductName = SummaCore;\n\t\t}};")
w("/* End XCSwiftPackageProductDependency section */")
w(f"\t}};\n\trootObject = {uid('project')} /* Project object */;\n}}")

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Summa.xcodeproj")
os.makedirs(os.path.join(root, "xcshareddata", "xcschemes"), exist_ok=True)
open(os.path.join(root, "project.pbxproj"), "w").write("\n".join(o) + "\n")

def ref(name, product, container="container:Summa.xcodeproj", blueprint=None):
    return (f'<BuildableReference BuildableIdentifier = "primary" BlueprintIdentifier = "{blueprint or uid("target-"+name)}" '
            f'BuildableName = "{product}" BlueprintName = "{name}" ReferencedContainer = "{container}"></BuildableReference>')
scheme = f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion = "1600" version = "1.7">
   <BuildAction parallelizeBuildables = "YES" buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry buildForTesting = "YES" buildForRunning = "YES" buildForProfiling = "YES" buildForArchiving = "YES" buildForAnalyzing = "YES">
            {ref("Summa", "Summa.app")}
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv = "YES">
      <Testables>
         <TestableReference skipped = "NO">
            {ref("SummaCoreTests", "SummaCoreTests", "container:SummaCore", "SummaCoreTests")}
         </TestableReference>
         <TestableReference skipped = "NO">
            {ref("SummaUITests", "SummaUITests.xctest")}
         </TestableReference>
      </Testables>
   </TestAction>
   <LaunchAction buildConfiguration = "Debug" selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle = "0" useCustomWorkingDirectory = "NO" ignoresPersistentStateOnLaunch = "NO" debugDocumentVersioning = "YES" debugServiceExtension = "internal" allowLocationSimulation = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref("Summa", "Summa.app")}
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction buildConfiguration = "Release" shouldUseLaunchSchemeArgsEnv = "YES" savedToolIdentifier = "" useCustomWorkingDirectory = "NO" debugDocumentVersioning = "YES">
      <BuildableProductRunnable runnableDebuggingMode = "0">
         {ref("Summa", "Summa.app")}
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction buildConfiguration = "Debug"></AnalyzeAction>
   <ArchiveAction buildConfiguration = "Release" revealArchiveInOrganizer = "YES"></ArchiveAction>
</Scheme>
'''
open(os.path.join(root, "xcshareddata", "xcschemes", "Summa.xcscheme"), "w").write(scheme)
print("wrote", os.path.normpath(root))
