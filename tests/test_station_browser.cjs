/* Real browser checks of the offline bundle and existing receiver integration. */
const assert=require('node:assert/strict');
const fs=require('node:fs');
const path=require('node:path');
const cp=require('node:child_process');
const {chromium}=require('playwright');
const root=path.resolve(__dirname,'..');
process.env.TMPDIR=path.join(root,'build/tmp');
fs.mkdirSync(process.env.TMPDIR,{recursive:true});
(async()=>{
 cp.execFileSync('python3',['tools/build_station_web.py'],{cwd:root});
 const server=cp.spawn('python3',['telemetry/server.py'],{cwd:root,env:{...process.env,LUMA_HOST:'127.0.0.1',LUMA_PORT:'0',LUMA_STATION_PAIRING_KEY:'browser-test-pairing-key-only',LUMA_STATION_LLM_URL:''}});
 let serverErrors='';server.stderr.on('data',d=>serverErrors+=d);
 let browser;
 try{
  const port=await new Promise((resolve,reject)=>{let out='';const timer=setTimeout(()=>reject(Error('Receiver startup timed out: '+serverErrors)),10000);server.stdout.on('data',d=>{out+=d;const match=out.match(/127\.0\.0\.1:(\d+)/);if(match){clearTimeout(timer);resolve(+match[1]);}});server.on('exit',code=>{clearTimeout(timer);reject(Error('Receiver exited '+code+': '+serverErrors));});});
  browser=await chromium.launch({headless:true,args:['--no-sandbox']});
  const page=await browser.newPage({viewport:{width:1100,height:920},deviceScaleFactor:1});
  const errors=[];page.on('pageerror',e=>errors.push(e.message));
  await page.goto('http://127.0.0.1:'+port);
  assert.match(await page.locator('#program-state').innerText(),/PROMPT READY/);
  assert.equal(await page.locator('#beats article').count(),4);
  await page.selectOption('#show','talk_hour');await page.click('#outline');
  assert.equal(await page.locator('#minutes').inputValue(),'60');assert.equal(await page.locator('#beats article').count(),6);
  await page.fill('#topic','A coherent Mars garden discussion');await page.click('#save-template');await page.fill('#topic','Changed');await page.click('#load-template');assert.equal(await page.locator('#topic').inputValue(),'A coherent Mars garden discussion');
  await page.selectOption('#show','interview');await page.click('#outline');assert.equal(await page.locator('#guest-field').isVisible(),true);
  await page.selectOption('#mode','sourced');await page.click('#outline');assert.match(await page.locator('#notice').innerText(),/Source title/);
  await page.selectOption('#mode','simulation');
  await page.click('[data-tab=solar]');await page.getByRole('button',{name:'Jupiter',exact:true}).click();assert.equal(await page.locator('#selected-body').innerText(),'Jupiter');
  await page.click('[data-tab=signals]');await page.fill('#signal-text','🌍');await page.selectOption('#signal-format','u16');await page.click('#preview-signal');assert.match(await page.locator('#signal-output').innerText(),/d83cdf0d/);
  await page.locator('#pairing summary').click();await page.fill('#pair-key','browser-test-pairing-key-only');await page.click('#connect');await page.waitForFunction(()=>ForgeStudio.isPaired());
  assert.equal(await page.locator('#pair-key').inputValue(),'');
  await page.click('#send-signal');await page.waitForFunction(()=>document.getElementById('receipt-state').textContent==='No peer delivery');
  await page.click('[data-tab=station]');await page.click('#generate');await page.waitForFunction(()=>document.getElementById('program-state').textContent.startsWith('PROMPT READY'));
  assert.equal(await page.locator('#result-label').innerText(),'FICTIONAL SIMULATION');
  await page.click('#disconnect');assert.equal(await page.locator('#generate').isDisabled(),true);
  await page.evaluate(()=>ForgeStudio.view('station'));await page.locator('#pairing').evaluate(e=>e.open=false);
  fs.mkdirSync(path.join(root,'build/ui'),{recursive:true});await page.screenshot({path:path.join(root,'build/ui/forge-station-desktop.png'),fullPage:true});
  await page.setViewportSize({width:390,height:844});await page.screenshot({path:path.join(root,'build/ui/forge-station-phone.png'),fullPage:true});
  assert.equal(await page.evaluate(()=>document.documentElement.scrollWidth<=innerWidth),true,'No horizontal overflow on phone');
  assert.deepEqual(errors,[]);
  console.log('STATION_BROWSER: offline formats, templates, source guard, solar selection, silent Unicode, real pairing/generation/ACK, responsive layout passed');
 }finally{if(browser)await browser.close();server.kill();}
})().catch(e=>{console.error(e);process.exitCode=1;});
