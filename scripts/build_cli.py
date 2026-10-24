#!/usr/bin/env python3
"""Build the macOS universal terminal helper for this app's identifier family."""
from pathlib import Path
import argparse
import os
import plistlib
import subprocess
import tempfile

ROOT=Path(__file__).resolve().parents[1]


def go_join(arguments):
    # Go's quoted.Split accepts whole quoted words, without shell escapes.
    result=[]
    for value in arguments:
        if not any(c in value for c in " \t\n\r\"'"): result.append(value)
        elif "'" not in value: result.append("'"+value+"'")
        elif '"' not in value: result.append('"'+value+'"')
        else: raise ValueError('Go linker paths cannot contain both quote characters')
    return ' '.join(result)


def build(bundle_base):
    output=ROOT/'.build/clash-cli';output.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=output,prefix='build-') as folder:
        work=Path(folder)
        info=plistlib.loads((ROOT/'cli/Info.plist.in').read_bytes())
        info.update(CFBundleIdentifier=bundle_base+'.clash-cli',CFBundleVersion='1.0.0',CFBundleShortVersionString='1.0.0')
        plist=work/'Info.plist';plist.write_bytes(plistlib.dumps(info))
        binaries=[]
        for arch,carch in [('arm64','arm64'),('amd64','x86_64')]:
            binary=work/arch
            env=dict(os.environ,GOOS='darwin',GOARCH=arch,CGO_ENABLED='1',CC='clang -arch '+carch,
                     CGO_CFLAGS='-mmacosx-version-min=13.0',CGO_LDFLAGS='-mmacosx-version-min=13.0')
            external=go_join(['-mmacosx-version-min=13.0','-sectcreate','__TEXT','__info_plist',str(plist)])
            flags=go_join(['-s','-w','-X','main.cliVersion=1.0.0','-linkmode=external','-extldflags',external])
            subprocess.run(['go','build','-mod=readonly','-trimpath','-buildvcs=false','-ldflags',flags,'-o',str(binary),'.'],cwd=ROOT/'cli',env=env,check=True)
            binaries.append(str(binary))
        subprocess.run(['lipo','-create','-output',str(output/'clash-cli'),*binaries],check=True)
    subprocess.run([str(output/'clash-cli'),'help'],stdout=subprocess.DEVNULL,check=True)
    subprocess.run([str(output/'clash-cli'),'skill'],stdout=subprocess.DEVNULL,check=True)


if __name__=='__main__':
    parser=argparse.ArgumentParser();parser.add_argument('--bundle-base',required=True)
    build(parser.parse_args().bundle_base)
