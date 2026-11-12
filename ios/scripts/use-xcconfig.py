#!/usr/bin/env python3
"""Points the Summa project at Config/Summa.xcconfig (which includes the git-ignored Secrets.xcconfig).
Idempotent. Edits project.pbxproj in place so any signing or team settings already chosen in Xcode are kept."""
import os, re, sys

FILE_ID = "5A77C0F1E2D3B4A5968778C1"
path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Summa.xcodeproj", "project.pbxproj")
text = open(path).read()
if FILE_ID in text:
    print("already configured")
    sys.exit(0)

ref = f'\t\t{FILE_ID} /* Summa.xcconfig */ = {{isa = PBXFileReference; lastKnownFileType = text.xcconfig; path = Summa.xcconfig; sourceTree = "<group>"; }};\n'
text = text.replace("/* End PBXFileReference section */", ref + "/* End PBXFileReference section */", 1)

child = re.search(r"\n(\t+)[0-9A-F]{24} /\* Summa-Info\.plist \*/,\n", text)
assert child, "Config group not found"
text = text[:child.start() + 1] + f"{child.group(1)}{FILE_ID} /* Summa.xcconfig */,\n" + text[child.start() + 1:]

def patch(block):
    body = block.group(0)
    if "SUMMA_API_BASE_URL" not in body:
        return body
    body = re.sub(r"\n\t+(SUMMA_API_BASE_URL|SUPABASE_URL|SUPABASE_ANON_KEY) = [^\n]*;", "", body)
    return body.replace("isa = XCBuildConfiguration;", f"isa = XCBuildConfiguration;\n\t\t\tbaseConfigurationReference = {FILE_ID} /* Summa.xcconfig */;", 1)

text, count = re.subn(r"[0-9A-F]{24} /\* (?:Debug|Release) \*/ = \{\n\t+isa = XCBuildConfiguration;.*?\n\t\t\};", patch, text, flags=re.S)
assert text.count("baseConfigurationReference") == 2, "expected two project-level configurations"

with open(path, "r+") as handle:  # in place: the file may live on a volume where replacing files is not allowed
    handle.seek(0)
    handle.write(text)
    handle.truncate()
print("project now uses Config/Summa.xcconfig")
