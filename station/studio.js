/* Shared offline producer + silent codecs for the existing Forge Hub interface. */
((root) => {
  'use strict';
  function required(value, name, limit) {
    if (typeof value !== 'string' || !value.trim() || value.length > limit) throw Error(`${name} needs 1–${limit} characters.`);
    return value.trim();
  }
  function makePlan(input, formats) {
    const show = input.show || 'mars_news', spec = formats[show];
    if (!spec) throw Error('Choose a station format.');
    const mode = input.mode || 'simulation';
    if (!['simulation', 'sourced'].includes(mode)) throw Error('Choose simulation or sourced mode.');
    const topic = required(input.topic, 'Topic', 240), host = required(input.host || 'Luma', 'Host', 60);
    const guest = required(input.guest || 'Guest', 'Guest', 60);
    if (host === guest) throw Error('Host and guest need different names.');
    const minutes = input.minutes === undefined ? spec.minutes : input.minutes;
    if (!Number.isInteger(minutes) || minutes < 1 || minutes > 120) throw Error('Choose 1–120 whole minutes.');
    const sources = input.sources || [];
    if (mode === 'sourced' && !sources.length) throw Error('Add source notes before making factual news.');
    if (!Array.isArray(sources) || sources.length > 12) throw Error('Use at most 12 source notes.');
    const ids = new Set();
    for (const source of sources) {
      if (!source || !/^[a-zA-Z0-9_-]{1,40}$/.test(source.id) || ids.has(source.id)) throw Error('Source IDs must be unique.');
      required(source.title, 'Source title', 200); required(source.notes, 'Source notes', 2500); ids.add(source.id);
    }
    const direction = input.direction || '';
    if (typeof direction !== 'string' || direction.length > 4000) throw Error('Creative direction is limited to 4000 characters.');
    const total = minutes * 60, weight = spec.beats.reduce((sum, beat) => sum + beat[2], 0);
    const seconds = spec.beats.map(beat => Math.floor(total * beat[2] / weight));
    const order = spec.beats.map((beat, i) => ({i, remainder: total * beat[2] % weight})).sort((a,b) => b.remainder-a.remainder || a.i-b.i);
    for (let n = 0, left = total-seconds.reduce((a,b)=>a+b,0); n < left; n++) seconds[order[n].i]++;
    let start = 0;
    const beats = spec.beats.map((beat, i) => {
      const value = {id:beat[0], title:beat[1], start_seconds:start, target_seconds:seconds[i], direction:beat[3]};
      start += seconds[i]; return value;
    });
    return {station:'Luma Forge Solar', show, title:spec.title, purpose:spec.purpose, topic, direction:direction.trim(), host, guest,
      mode, map_context:input.map_context || {}, sources, target_seconds:total, beats,
      duration_note:'Planned running order; text cues are not a measured full-duration performance.',
      label:mode === 'simulation' ? 'FICTIONAL SIMULATION' : 'SOURCE-BASED DRAFT — REVIEW REQUIRED', audio:false};
  }
  function morse(text, alphabet) {
    required(text, 'Signal', 160);
    if (!/^[\x00-\x7F]+$/.test(text)) throw Error('Morse uses A–Z, digits, and standard punctuation.');
    const words = text.toUpperCase().trim().split(/\s+/), pulses = [];
    const code = words.map((word,wi) => {
      if(wi) pulses.push({on:false,units:7});
      return [...word].map((ch,ci) => {
        if (!alphabet[ch]) throw Error(`Unsupported Morse character: ${ch}`);
        if(ci) pulses.push({on:false,units:3});
        [...alphabet[ch]].forEach((s,si)=>{if(si)pulses.push({on:false,units:1});pulses.push({on:true,units:s==='.'?1:3});});
        return alphabet[ch];
      }).join(' ');
    }).join(' / ');
    return {format:'morse',text:words.join(' '),code,pulses,audio:false};
  }
  function words(text, width) {
    required(text, 'Signal', 160);
    if (width !== 8 && width !== 16) throw Error('Choose 8 or 16 bits.');
    let values;
    if(width===8) values=Array.from(new TextEncoder().encode(text));
    else {values=[];for(let i=0;i<text.length;i++)values.push(text.charCodeAt(i));}
    return {format:`u${width}`,width,encoding:width===8?'utf-8':'utf-16-be',values,
      hex:values.map(v=>v.toString(16).padStart(width/4,'0')).join(''),audio:false};
  }
  function localURL(value) {
    let u;try{u=new URL(value);}catch{return false;}
    if(!['ws:','wss:'].includes(u.protocol)||u.username||u.password||u.search||u.hash)return false;
    const host=u.hostname.replace(/^\[|\]$/g,'').toLowerCase();
    if(['localhost','127.0.0.1','::1'].includes(host))return true;
    if(u.protocol!=='wss:')return false;
    if(/^(fc|fd)[0-9a-f:]+$/i.test(host)&&host.includes(':'))return true;
    const n=host.split('.');
    return n.length===4&&n.every(v=>/^\d+$/.test(v)&&+v<=255)&&(+n[0]===10||(+n[0]===192&&+n[1]===168)||(+n[0]===172&&+n[1]>=16&&+n[1]<=31));
  }
  const api={makePlan,morse,words,localURL};
  if(typeof module!=='undefined'&&module.exports)module.exports=api;
  root.ForgeStationCore=api;
})(typeof globalThis!=='undefined'?globalThis:this);
