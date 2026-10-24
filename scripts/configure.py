#!/usr/bin/env python3
"""Choose your identifier family, then generate the three-platform Xcode project."""
from pathlib import Path
import argparse
import re
import subprocess
import yaml

ROOT=Path(__file__).resolve().parents[1]

def main():
    parser=argparse.ArgumentParser();parser.add_argument('--bundle-base');parser.add_argument('--team');args=parser.parse_args()
    path=ROOT/'apple/ClashClient/project.yml'
    project=yaml.safe_load(path.read_text());base=project['settings']['base']
    old=base['CLASH_BUNDLE_BASE'];new=args.bundle_base or old
    if not re.fullmatch(r'[A-Za-z0-9]+(?:[.-][A-Za-z0-9]+)+',new):raise ValueError('Invalid bundle base')
    if args.team is not None:
        if not re.fullmatch(r'[A-Z0-9]{10}|',args.team):raise ValueError('Invalid team identifier')
        base['CLASH_DEVELOPMENT_TEAM']=args.team
    base['CLASH_BUNDLE_BASE']=new;project['options']['bundleIdPrefix']=new
    # Generated identifier files contain constants only, shared by all targets.
    identifiers=['apple/ClashClient/Shared/ClashAppIdentifiers.swift',
                 'apple/ClashClientKit/Sources/ClashClientKit/ClashClientKitIdentifiers.swift']
    for relative in identifiers:
        p=ROOT/relative;p.write_text(p.read_text().replace(old,new))
    path.write_text(yaml.safe_dump(project,sort_keys=False,allow_unicode=True))
    subprocess.run(['xcodegen','generate','--spec',str(path)],cwd=ROOT,check=True)
    from build_cli import build
    build(new)

if __name__=='__main__':main()
