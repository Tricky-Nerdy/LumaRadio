const assert=require('node:assert/strict');
const fs=require('node:fs');
const cp=require('node:child_process');
const path=require('node:path');
const {makePlan,morse,words,localURL}=require('../station/studio.js');
const formats=JSON.parse(fs.readFileSync(path.join(__dirname,'../station/formats.json')));
let checks=0;
for(const show of Object.keys(formats))for(const minutes of [1,5,20,60,120]){
 const js=makePlan({show,topic:'Mars transit',minutes},formats);
 const py=JSON.parse(cp.execFileSync('python3',['-c',`import json; from station.programming import make_plan; print(json.dumps(make_plan(json.loads(input()))))`],{input:JSON.stringify({show,topic:'Mars transit',minutes})}));
 assert.deepEqual(js,py);checks++;
}
const alphabet=JSON.parse(cp.execFileSync('python3',['-c','import json;from station.signals import MORSE;print(json.dumps(MORSE))']));
assert.equal(morse('SOS A',alphabet).pulses.reduce((n,p)=>n+p.units,0),39);checks++;
assert.deepEqual(words('🌍',16).values,[0xd83c,0xdf0d]);checks++;
assert.equal(words('Café',8).hex,Buffer.from('Café').toString('hex'));checks++;
for(const url of ['ws://192.168.1.2:8765','wss://example.com','wss://8.8.8.8','ws://localhost.evil.example']){assert.equal(localURL(url),false);checks++;}
for(const url of ['ws://127.0.0.1:8765','wss://192.168.1.2:8765']){assert.equal(localURL(url),true);checks++;}
console.log(`STATION_WEB_CORE: ${checks} parity and codec checks passed`);
