#!/usr/bin/env python3
"""生成 VideoToLive.xcodeproj/project.pbxproj"""
import os

OUT = os.path.expanduser("~/workspace/videotolive/VideoToLive.xcodeproj/project.pbxproj")

# (文件名, 相对工程根的路径, fileType)
SOURCES = [
    ("VideoToLiveApp.swift",  "VideoToLive/VideoToLiveApp.swift",  "sourcecode.swift"),
    ("ContentView.swift",     "VideoToLive/ContentView.swift",     "sourcecode.swift"),
    ("LivePhotoConverter.swift", "VideoToLive/LivePhotoConverter.swift", "sourcecode.swift"),
]
# 系统框架靠模块自动链接，无需显式加入
FRAMEWORKS = []

_id_counter = 0x1000
def nid():
    global _id_counter
    _id_counter += 1
    return "%024X" % _id_counter

# 固定关键 ID（顺序与 scheme 的 BlueprintIdentifier 对应：TARGET = ...001002）
PBXPROJECT = nid(); TARGET = nid(); PROJ_CFG_LIST = nid(); TGT_CFG_LIST = nid()
DBG_PROJ = nid(); REL_PROJ = nid(); DBG_TGT = nid(); REL_TGT = nid()
SRC_PHASE = nid(); FW_PHASE = nid(); RES_PHASE = nid()
MAIN_GROUP = nid(); PROD_GROUP = nid(); APP_GROUP = nid()
APP_REF = nid()

file_refs = {}   # path -> id
build_files = {} # path -> id

# 预分配所有文件引用 ID (必须在 BuildFile 之前, 因为 BuildFile 要引用它们)
for name, path, _ in SOURCES:
    file_refs[path] = nid()
PLIST_REF = nid()
FW_IDS = {}
for name, _ in FRAMEWORKS:
    FW_IDS[name] = name.replace('.', '_').upper()

objs = []
def add(line=""):
    objs.append(line)

def section(name):
    add("")
    add(f"/* Begin {name} section */")

def endsection(name):
    add(f"/* End {name} section */")

# ---------- PBXBuildFile ----------
section("PBXBuildFile")
for name, path, _ in SOURCES:
    bid = nid(); build_files[path] = bid
    add(f"\t\t{bid} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]}; }};")
for name, _ in FRAMEWORKS:
    bid = nid(); build_files[name] = bid
    add(f"\t\t{bid} /* {name} in Frameworks */ = {{isa = PBXBuildFile; fileRef = {FW_IDS[name]}; settings = {{ATTRIBUTES = (Required, ); }}; }};")
endsection("PBXBuildFile")

# ---------- PBXFileReference ----------
section("PBXFileReference")
for name, path, ftype in SOURCES:
    fid = file_refs[path]
    add(f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = {name}; path = {path}; sourceTree = SOURCE_ROOT; }};")
add(f"\t\t{PLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = VideoToLive/Info.plist; sourceTree = SOURCE_ROOT; }};")
for name, ftype in FRAMEWORKS:
    fid = FW_IDS[name]
    add(f"\t\t{fid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ftype}; name = {name}; path = System/Library/Frameworks/{name}; sourceTree = SDKROOT; }};")
add(f"\t\t{APP_REF} /* VideoToLive.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = VideoToLive.app; sourceTree = BUILT_PRODUCTS_DIR; }};")
endsection("PBXFileReference")

# ---------- PBXFrameworksBuildPhase ----------
section("PBXFrameworksBuildPhase")
add(f"\t\t{FW_PHASE} /* Frameworks */ = {{")
add("\t\t\tisa = PBXFrameworksBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for name, _ in FRAMEWORKS:
    add(f"\t\t\t\t{build_files[name]} /* {name} in Frameworks */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
endsection("PBXFrameworksBuildPhase")

# ---------- PBXGroup ----------
section("PBXGroup")
add(f"\t\t{MAIN_GROUP} = {{")
add("\t\t\tisa = PBXGroup;")
add("\t\t\tchildren = (")
add(f"\t\t\t\t{APP_GROUP} /* VideoToLive */,")
add(f"\t\t\t\t{PROD_GROUP} /* Products */,")
add("\t\t\t);")
add('\t\t\tsourceTree = "<group>";')
add("\t\t};")
add(f"\t\t{PROD_GROUP} /* Products */ = {{")
add("\t\t\tisa = PBXGroup;")
add("\t\t\tchildren = (")
add(f"\t\t\t\t{APP_REF} /* VideoToLive.app */,")
add("\t\t\t);")
add('\t\t\tname = Products;')
add('\t\t\tsourceTree = "<group>";')
add("\t\t};")
add(f"\t\t{APP_GROUP} /* VideoToLive */ = {{")
add("\t\t\tisa = PBXGroup;")
add("\t\t\tchildren = (")
for name, path, _ in SOURCES:
    add(f"\t\t\t\t{file_refs[path]} /* {name} */,")
add(f"\t\t\t\t{PLIST_REF} /* Info.plist */,")
add("\t\t\t);")
add('\t\t\tpath = VideoToLive;')
add('\t\t\tsourceTree = "<group>";')
add("\t\t};")
endsection("PBXGroup")

# ---------- PBXNativeTarget ----------
section("PBXNativeTarget")
add(f"\t\t{TARGET} /* VideoToLive */ = {{")
add("\t\t\tisa = PBXNativeTarget;")
add("\t\t\tbuildConfigurationList = " + TGT_CFG_LIST + " /* Build configuration list for PBXNativeTarget \"VideoToLive\" */;")
add("\t\t\tbuildPhases = (")
add(f"\t\t\t\t{SRC_PHASE} /* Sources */,")
add(f"\t\t\t\t{FW_PHASE} /* Frameworks */,")
add(f"\t\t\t\t{RES_PHASE} /* Resources */,")
add("\t\t\t);")
add("\t\t\tbuildRules = (")
add("\t\t\t);")
add("\t\t\tdependencies = (")
add("\t\t\t);")
add('\t\t\tname = VideoToLive;')
add("\t\t\tproductName = VideoToLive;")
add(f"\t\t\tproductReference = {APP_REF} /* VideoToLive.app */;")
add('\t\t\tproductType = "com.apple.product-type.application";')
add("\t\t};")
endsection("PBXNativeTarget")

# ---------- PBXProject ----------
section("PBXProject")
add(f"\t\t{PBXPROJECT} /* Project object */ = {{")
add("\t\t\tisa = PBXProject;")
add("\t\t\tbuildConfigurationList = " + PROJ_CFG_LIST + " /* Build configuration list for PBXProject \"VideoToLive\" */;")
add("\t\t\tcompatibilityVersion = \"Xcode 14.0\";")
add('\t\t\tdevelopmentRegion = en;')
add("\t\t\thasScannedForEncodings = 0;")
add("\t\t\tknownRegions = (")
add("\t\t\t\ten,")
add("\t\t\t);")
add(f"\t\t\tmainGroup = {MAIN_GROUP};")
add(f"\t\t\tproductRefGroup = {PROD_GROUP} /* Products */;")
add('\t\t\tprojectDirPath = "";')
add('\t\t\tprojectRoot = "";')
add("\t\t\ttargets = (")
add(f"\t\t\t\t{TARGET} /* VideoToLive */,")
add("\t\t\t);")
add("\t\t};")
endsection("PBXProject")

# ---------- PBXResourcesBuildPhase ----------
section("PBXResourcesBuildPhase")
add(f"\t\t{RES_PHASE} /* Resources */ = {{")
add("\t\t\tisa = PBXResourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
endsection("PBXResourcesBuildPhase")

# ---------- PBXSourcesBuildPhase ----------
section("PBXSourcesBuildPhase")
add(f"\t\t{SRC_PHASE} /* Sources */ = {{")
add("\t\t\tisa = PBXSourcesBuildPhase;")
add("\t\t\tbuildActionMask = 2147483647;")
add("\t\t\tfiles = (")
for name, path, _ in SOURCES:
    add(f"\t\t\t\t{build_files[path]} /* {name} in Sources */,")
add("\t\t\t);")
add("\t\t\trunOnlyForDeploymentPostprocessing = 0;")
add("\t\t};")
endsection("PBXSourcesBuildPhase")

# ---------- XCBuildConfiguration ----------
def build_settings(target, debug):
    s = []
    s.append("\t\t\t\tALWAYS_SEARCH_USER_PATHS = NO;")
    s.append("\t\t\t\tCLANG_ANALYZER_NONNULL = YES;")
    s.append("\t\t\t\tCLANG_CXX_LANGUAGE_STANDARD = \"gnu++20\";")
    s.append("\t\t\t\tCLANG_ENABLE_MODULES = YES;")
    s.append("\t\t\t\tCURRENT_PROJECT_VERSION = 1;")
    if target:
        s.append("\t\t\t\tINFOPLIST_FILE = VideoToLive/Info.plist;")
        s.append("\t\t\t\tLD_RUNPATH_SEARCH_PATHS = (\"$(inherited)\", \"@executable_path/Frameworks\");")
        s.append("\t\t\t\tPRODUCT_BUNDLE_IDENTIFIER = com.zhy8416503.videotolive;")
        s.append("\t\t\t\tPRODUCT_NAME = \"$(TARGET_NAME)\";")
        s.append('\t\t\t\tCODE_SIGN_STYLE = Automatic;')
    s.append("\t\t\t\tIPHONEOS_DEPLOYMENT_TARGET = 17.0;")
    s.append("\t\t\t\tMARKETING_VERSION = 1.0;")
    s.append('\t\t\t\tSDKROOT = iphoneos;')
    s.append("\t\t\t\tSWIFT_VERSION = 5.0;")
    s.append("\t\t\t\tTARGETED_DEVICE_FAMILY = 1;")
    if debug:
        s.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = dwarf;")
        s.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = 0;")
        s.append("\t\t\t\tSWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;")
        s.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-Onone\";")
    else:
        s.append("\t\t\t\tDEBUG_INFORMATION_FORMAT = \"dwarf-with-dsym\";")
        s.append("\t\t\t\tGCC_OPTIMIZATION_LEVEL = s;")
        s.append("\t\t\t\tSWIFT_OPTIMIZATION_LEVEL = \"-O\";")
        s.append("\t\t\t\tSWIFT_COMPILATION_MODE = wholemodule;")
    return "\n".join(s)

section("XCBuildConfiguration")
for cid, name, is_target, is_debug in [
    (DBG_PROJ, "Debug", False, True), (REL_PROJ, "Release", False, False),
    (DBG_TGT, "Debug", True, True), (REL_TGT, "Release", True, False),
]:
    scope = "PBXNativeTarget \"VideoToLive\"" if is_target else "PBXProject \"VideoToLive\""
    add(f"\t\t{cid} /* {name} */ = {{")
    add("\t\t\tisa = XCBuildConfiguration;")
    add("\t\t\tbuildSettings = {")
    add(build_settings(is_target, is_debug))
    add("\t\t\t};")
    add(f"\t\t\tname = {name};")
    add("\t\t};")
endsection("XCBuildConfiguration")

# ---------- XCConfigurationList ----------
section("XCConfigurationList")
add(f"\t\t{PROJ_CFG_LIST} /* Build configuration list for PBXProject \"VideoToLive\" */ = {{")
add("\t\t\tisa = XCConfigurationList;")
add("\t\t\tbuildConfigurations = (")
add(f"\t\t\t\t{DBG_PROJ} /* Debug */,")
add(f"\t\t\t\t{REL_PROJ} /* Release */,")
add("\t\t\t);")
add("\t\t\tdefaultConfigurationIsVisible = 0;")
add("\t\t\tdefaultConfigurationName = Release;")
add("\t\t};")
add(f"\t\t{TGT_CFG_LIST} /* Build configuration list for PBXNativeTarget \"VideoToLive\" */ = {{")
add("\t\t\tisa = XCConfigurationList;")
add("\t\t\tbuildConfigurations = (")
add(f"\t\t\t\t{DBG_TGT} /* Debug */,")
add(f"\t\t\t\t{REL_TGT} /* Release */,")
add("\t\t\t);")
add("\t\t\tdefaultConfigurationIsVisible = 0;")
add("\t\t\tdefaultConfigurationName = Release;")
add("\t\t};")
endsection("XCConfigurationList")

header = """// !$*UTF8*$!
{
\tarchiveVersion = 1;
\tclasses = {
\t};
\tobjectVersion = 56;
\tobjects = {
"""
footer = """\t};
\trootObject = %s /* Project object */;
}
""" % PBXPROJECT

os.makedirs(os.path.dirname(OUT), exist_ok=True)
with open(OUT, "w", encoding="utf-8") as f:
    f.write(header)
    f.write("\n".join(objs))
    f.write("\n")
    f.write(footer)
print("wrote", OUT)
