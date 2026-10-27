"""Create the hash manifest for the small, explicit Windows release bundle."""
from pathlib import Path
import hashlib,json,sys,re
ROOT=Path(__file__).resolve().parents[1]
FILES=['windows/autocomplete.ahk','windows/refresh-all.ps1',
       'automations/advancedmd/follow-up-office.ahk',
       'automations/advancedmd/follow-up-tele.ahk',
       'automations/advancedmd/intake-office.ahk', 'automations/dell/helpers.ahk']
manifest={'schema':1,'files':[{'path':p,'sha256':hashlib.sha256((ROOT/p).read_bytes()).hexdigest()} for p in FILES]}
content=json.dumps(manifest,indent=2)+'\n'
path=ROOT/'windows/release-manifest.json'
if '--check' in sys.argv:
    assert path.read_text(encoding="utf-8")==content, 'Run python tools/build-release.py after changing bundle files.'
    assert (ROOT/'autocomplete.ahk').read_bytes()==(ROOT/'windows/autocomplete.ahk').read_bytes(), 'Compatibility bridge differs'
    catalog=json.loads((ROOT/'automations/catalog.json').read_text(encoding="utf-8"))
    ids=[row[3] for row in catalog[1:]]
    registry=(ROOT/'windows/autocomplete.ahk').read_text(encoding="utf-8").split('global AutomationRegistry := Map(',1)[1].split('global AiEngine',1)[0]
    declared=re.findall(r'^    "([^"]+)", \{File:', registry, re.M)
    assert len(ids)==len(set(ids)) and set(ids)==set(declared), 'Catalog/dispatch mismatch'
    assert any('of' in [x.strip() for x in row[1].split(',')] and row[3]=='advancedmd.follow-up-office' for row in catalog[1:])
    marker_start='; BEGIN SHARED CHROME FOCUS'
    marker_end='; END SHARED CHROME FOCUS'
    launcher=(ROOT/'windows/autocomplete.ahk').read_text(encoding="utf-8")
    standalone=(ROOT/'windows/standalone/focus-general-chrome.ahk').read_text(encoding="utf-8")
    assert launcher.split(marker_start,1)[1].split(marker_end,1)[0] == standalone.split(marker_start,1)[1].split(marker_end,1)[0], 'Standalone Chrome implementation differs'
    print(f'Manifest, compatibility bridge, and all {len(ids)} catalog dispatch entries verified')
else:path.write_text(content)
