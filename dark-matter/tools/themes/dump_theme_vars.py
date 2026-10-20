# Dump the previewer's resolved --dm-* theme variables for all 10 themes (Chromium). Input for make_class_textures.py.
import json
from playwright.sync_api import sync_playwright
URL='file:///workspace/addon-previewer/index.html#dark-matter'
out={}
with sync_playwright() as p:
  b=p.chromium.launch(); pg=b.new_page(viewport={'width':1400,'height':900}); pg.goto(URL); pg.wait_for_timeout(800)
  pg.click('#dm-mmbtn'); pg.wait_for_timeout(200)
  for t in ['wow','warrior','paladin','hunter','rogue','priest','shaman','mage','warlock','druid']:
    pg.evaluate("t=>DarkMatterPreview.setTheme(t)",t); pg.wait_for_timeout(100)
    out[t]=pg.evaluate("""()=>{var s=document.querySelector('#dm-stage'),cs=getComputedStyle(s),o={};
      for(var i=0;i<s.style.length;i++){var k=s.style[i];if(k.startsWith('--dm-'))o[k]=cs.getPropertyValue(k).trim()}return o}""")
json.dump(out,open('/workspace/wow-addons/dark-matter/tools/themes/theme_vars.json','w'),indent=0)
print({k:len(v) for k,v in out.items()})
