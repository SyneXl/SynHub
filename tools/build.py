"""Build deterministic, immutable release files from the source modules."""
from pathlib import Path
import argparse
import hashlib
import json
import re

ROOT = Path(__file__).resolve().parents[1]
IMPORT = re.compile(r'\brequire\("([a-zA-Z0-9_/-]+)"\)')

def text(path):
    return path.read_text(encoding='utf-8').replace('\r\n', '\n')

def collect(entry):
    modules = {}
    visiting = set()
    def visit(name):
        if name in visiting:
            raise ValueError(f'Cyclic module dependency: {name}')
        if name in modules:
            return
        if '..' in name or name.startswith('/'):
            raise ValueError(f'Invalid module path: {name}')
        path = ROOT/'src'/(name+'.luau')
        source = text(path)
        visiting.add(name)
        for dependency in IMPORT.findall(source):
            visit(dependency)
        visiting.remove(name)
        modules[name] = source
    visit(entry)
    return modules

def bundle(entry):
    lines = ['-- By SyneX', 'local modules, cache, loading = {}, {}, {}']
    for name, source in collect(entry).items():
        lines += [f'modules["{name}"] = function(require)', source, 'end']
    lines += [
        'local function import(name)',
        '    if cache[name] ~= nil then return cache[name] end',
        '    assert(not loading[name], "Cyclic module: " .. name)',
        '    local factory = assert(modules[name], "Unknown module: " .. name)',
        '    loading[name] = true',
        '    local result = factory(import)',
        '    loading[name] = nil',
        '    cache[name] = result',
        '    return result',
        'end',
        f'return import("{entry}")', '',
    ]
    return '\n'.join(lines).encode('utf-8')

def artifacts():
    config = json.loads(text(ROOT/'games.json'))
    files = {}
    games = []
    places = set()
    def artifact(data, directory, extension):
        digest = hashlib.sha256(data).hexdigest()
        path = f'{directory}/{digest}.{extension}'
        files[path] = data
        return {'path': path, 'bytes': len(data), 'sha256': digest}
    for game_id, game in sorted(config.items()):
        if not re.fullmatch(r'[a-z][a-z0-9-]*', game_id):
            raise ValueError(f'Invalid game id: {game_id}')
        for place in game['placeIds']:
            if type(place) is not int or place <= 0 or place in places:
                raise ValueError(f'Invalid or duplicate place id: {place}')
            places.add(place)
        assets = {}
        for name, path in sorted(game['assets'].items()):
            source = ROOT/path
            assets[name] = artifact(text(source).encode('utf-8'), 'assets/'+name, source.suffix[1:])
        games.append({'id': game_id, 'name': game['name'], 'version': game['version'],
                      'placeIds': game['placeIds'], 'script': artifact(bundle(game['entry']), 'releases/'+game_id, 'luau'),
                      'assets': assets})
    manifest = {'schema': 1, 'games': games}
    files['manifest.json'] = (json.dumps(manifest, ensure_ascii=False, indent=2)+'\n').encode('utf-8')
    return files

def build(check=False):
    files = artifacts()
    differences = []
    for name, expected in files.items():
        path = ROOT/name
        actual = path.read_bytes() if path.exists() else None
        if actual == expected:
            continue
        if check:
            differences.append(name)
            continue
        if name != 'manifest.json' and actual is not None:
            raise ValueError(f'Immutable artifact has been modified: {name}')
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(expected)
    if differences:
        raise SystemExit('Run tools/build.py and commit the generated files:\n'+'\n'.join(differences))
    print(f'{len(files)} release files verified' if check else f'{len(files)} release files built')

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--check', action='store_true')
    build(parser.parse_args().check)
