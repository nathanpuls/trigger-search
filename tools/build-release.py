"""Create the hash manifest for the small, explicit Windows release bundle."""
from pathlib import Path
import hashlib,json,sys
ROOT=Path(__file__).resolve().parents[1]
FILES=['windows/autocomplete.ahk','windows/refresh-all.ps1',
       'automations/advancedmd/follow-up-office.ahk',
       'automations/advancedmd/follow-up-tele.ahk',
       'automations/advancedmd/intake-office.ahk']
manifest={'schema':1,'files':[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in FILES]}
content=json.dumps(manifest,indent=2)+'\n'
path=ROOT/'windows/release-manifest.json'
if '--check' in sys.argv:
    assert path.read_text()==content, 'Run python tools/build-release.py after changing bundle files.'
    assert (ROOT/'autocomplete.ahk').read_bytes()==(ROOT/'windows/autocomplete.ahk').read_bytes(), 'Compatibility bridge differs'
    print('Manifest and compatibility bridge verified')
else:path.write_text(content)
