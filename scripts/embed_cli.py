#!/usr/bin/env python3
"""Copy and, for signed builds, sign the terminal helper inside the Mac app."""
from pathlib import Path
import os
import shutil
import subprocess

ROOT=Path(__file__).resolve().parents[1]
source=ROOT/'.build/clash-cli/clash-cli'
if not source.is_file(): raise SystemExit('Run python3 scripts/configure.py to build clash-cli first.')
destination=Path(os.environ['TARGET_BUILD_DIR'])/os.environ['CONTENTS_FOLDER_PATH']/'Helpers/clash-cli'
destination.parent.mkdir(parents=True,exist_ok=True)
shutil.copy2(source,destination)
identifier=os.environ['PRODUCT_BUNDLE_IDENTIFIER']+'.clash-cli'
if ('<string>'+identifier+'</string>').encode() not in source.read_bytes():
    raise SystemExit('Helper identifier differs; run configure.py with the app bundle base.')
if os.environ.get('CODE_SIGNING_ALLOWED','YES')!='NO':
    identity=os.environ.get('EXPANDED_CODE_SIGN_IDENTITY','')
    if not identity or identity=='-': raise SystemExit('Choose your own signing identity for the app and helper.')
    subprocess.run(['codesign','--force','--sign',identity,'--options','runtime','--entitlements',
                    str(ROOT/'cli/clash-cli.entitlements'),'--identifier',identifier,'--timestamp=none',str(destination)],check=True)
