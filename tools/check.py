"""Compile sources and exercise the loader against an isolated game fixture."""
from pathlib import Path
import argparse
import hashlib
import json
import os
import subprocess
import sys
import urllib.request
from build import ROOT, build, text

sys.stdout.reconfigure(encoding='utf-8', errors='replace')

def literal(value):
    if value is None:
        return 'nil'
    if isinstance(value, bool):
        return str(value).lower()
    if isinstance(value, (int, float)):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, list):
        return '{'+','.join(literal(item) for item in value)+'}'
    return '{'+','.join('['+literal(key)+']='+literal(item) for key,item in value.items())+'}'

def long_string(value):
    marker = '='
    while ']'+marker+']' in value:
        marker += '='
    return '['+marker+'[\n'+value+']'+marker+']'

def run(command):
    result = subprocess.run([str(arg) for arg in command], cwd=ROOT, capture_output=True, timeout=45)
    output = result.stdout.decode('utf-8', 'replace') + result.stderr.decode('utf-8', 'replace')
    if result.returncode:
        raise SystemExit(output)
    print(output.strip())

def check(luau_dir, remote=False):
    build(check=True)
    extension = '.exe' if os.name == 'nt' else ''
    runtime = luau_dir/('luau'+extension)
    compiler = luau_dir/('luau-compile'+extension)
    if not runtime.is_file() or not compiler.is_file():
        raise SystemExit('Install the pinned toolchain: python tools/fetch_luau.py')
    inputs = [ROOT/'loader.luau', *sorted((ROOT/'src').rglob('*.luau')), *sorted((ROOT/'tests').rglob('*.luau')),
              *sorted((ROOT/'vendor').rglob('*.luau'))]
    run([compiler, '--null', *[p.relative_to(ROOT) for p in inputs]])
    out = ROOT/'.tools/tests'
    out.mkdir(parents=True, exist_ok=True)
    core = text(ROOT/'src/games/slova/core.luau')
    suite = ('local Core=(function()\n'+core+'\nend)()\nlocal result=(function()\n'+text(ROOT/'tests/core.luau')+
             '\nend)()\nfor _,r in ipairs(result.tests) do if not r.passed then print("FAIL",r.name,r.error) end end\n'
             'print("CORE",result.passed,result.failed)\nassert(result.failed==0)\n')
    core_path = out/'core.luau'
    core_path.write_text(suite, encoding='utf-8')
    run([runtime, core_path.relative_to(ROOT)])
    manifest_text = text(ROOT/'manifest.json')
    manifest = json.loads(manifest_text)
    loader = text(ROOT/'loader.luau')
    entry = manifest['games'][0]
    contents = {'manifest.json': manifest_text}
    artifacts = [entry['script'], *entry['assets'].values()]
    for info in artifacts:
        contents[info['path']] = text(ROOT/info['path'])
    if remote:
        base = 'https://raw.githubusercontent.com/SyneXl/SynHub/refs/heads/main/'
        for name, expected in [('loader.luau', loader), *contents.items()]:
            request = urllib.request.Request(base+name, headers={'Cache-Control': 'no-cache'})
            with urllib.request.urlopen(request, timeout=30) as response:
                actual = response.read().decode('utf-8')
            if actual != expected:
                raise SystemExit('Remote content differs: '+name)
            if name == 'loader.luau':
                loader = actual
            else:
                contents[name] = actual
        print('GitHub loader, manifest and all release assets match')
    for info in artifacts:
        data = contents[info['path']].encode('utf-8')
        assert len(data) == info['bytes'] and hashlib.sha256(data).hexdigest() == info['sha256'], info['path']
    interface = entry['assets']['interface']
    stub = 'return getgenv().__mockLibrary\n--'
    contents[interface['path']] = stub+' '*(interface['bytes']-len(stub))
    http = '{'+','.join('['+literal(name)+']='+long_string(value) for name,value in contents.items())+'}'
    fixture = ('local loaderSource='+long_string(loader)+'\nlocal http='+http+'\n'
               'local function newMock()\nlocal mock=(function()\n'+text(ROOT/'tests/mock.luau')+'\nend)()\n'
               'mock.manifest='+literal(manifest)+'\nmock.manifestText='+long_string(manifest_text)+'\n'
               'mock.http=table.clone(http)\nfunction mock:load() return assert(self.env.loadstring(loaderSource,"LoaderUnderTest"))() end\n'
               'return mock\nend\n'+text(ROOT/'tests/integration.luau'))
    integration_path = out/'integration.luau'
    integration_path.write_text(fixture, encoding='utf-8')
    run([runtime, integration_path.relative_to(ROOT)])

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--luau-dir', type=Path, default=ROOT/'.tools/luau')
    parser.add_argument('--remote', action='store_true')
    args = parser.parse_args()
    check(args.luau_dir.resolve(), args.remote)
