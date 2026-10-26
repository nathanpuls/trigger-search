"""Local audit: compare macro actions/timings with the original Dell ZIP.
The ZIP and browser profile are never copied into the repository.
"""
import zipfile,sys,re,hashlib,json
from pathlib import Path
root=Path(__file__).resolve().parents[1]
records=json.loads((root/'automations/advancedmd/provenance.json').read_text())
with zipfile.ZipFile(sys.argv[1]) as archive:
 for item in records:
  raw=archive.read('AutoHotkey/'+item['source'])
  assert hashlib.sha256(raw).hexdigest()==item['source_sha256'], 'Different Dell baseline'
  src=raw.decode('utf-8-sig').replace('\r\n','\n')
  src=re.sub(r'/\*.*?\*/','',src,flags=re.S)
  dst=(root/item['destination']).read_text().split('PerformWorkflow() {',1)[1]
  def actions(s):
   return [re.sub(r'^Safe','',x.strip()) for x in s.splitlines()
           if re.match(r'^\s*(?:Safe)?(?:SendEvent|SendText|Send|Sleep)\s',x)]
  assert actions(src)==actions(dst), item['source']+' actions/timings changed'
  print(item['source']+': Dell actions and timings preserved')
