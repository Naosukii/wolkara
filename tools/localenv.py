"""Read builder-specific settings from the ignored local.env (KEY=value lines).

The process environment wins over local.env; both win over the defaults. Keep
signing teams, device identifiers and bundle identifiers out of committed files.
"""
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DEFAULTS = {'TOLKARA_BUNDLE_ID': 'local.tolkara.app', 'TOLKARA_KEYCHAIN_GROUP': 'local.tolkara.authorization'}


def load():
    values = dict(DEFAULTS)
    path = ROOT / 'local.env'
    file_values = {}
    if path.is_file():
        for line in path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith('#') or '=' not in line: continue
            key, value = line.split('=', 1)
            file_values[key.strip().removeprefix('export ').strip()] = value.strip().strip('"\'')
    values.update(file_values)
    for k, v in os.environ.items():
        if k in values or k in ('DEVICE', 'SIMULATOR', 'DEVELOPMENT_TEAM', 'CURSEFORGE_API_KEY'):
            if k == 'CURSEFORGE_API_KEY' and k in file_values and not v.startswith('$'):
                continue
            values[k] = v
    return values


def bundle_id():
    return load()['TOLKARA_BUNDLE_ID']
