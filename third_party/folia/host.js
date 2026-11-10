// DuckMusic adapter, 2026-11-10. Rendering is Folia (AGPL-3.0); playback remains native.
import {LumierePixiRuntime, compileLumiereProgram, DEFAULT_LUMIERE_TUNING,
  HanabiPixiRuntime, compileHanabiProgram, DEFAULT_HANABI_TUNING,
  NebbiaRuntime, DEFAULT_NEBBIA_TUNING} from './entry.ts';
import {PlaybackClock} from './clock.mjs';

const clock = new PlaybackClock();
const host = document.querySelector('#stage');
const send = (type, detail='') => window.DuckMusicFolia?.postMessage(JSON.stringify({type,detail}));
const time = {get:()=>clock.seconds};
const silent = {get:()=>0};
let fft = Array(32).fill(0);
const band=(from,to)=>({get:()=>fft.slice(from,to).reduce((a,b)=>a+b,0)/(to-from)});
const bands = {bass:band(0,5),lowMid:band(5,11),mid:band(11,18),vocal:band(18,25),treble:band(25,32)};
const power=band(0,32);
let renderer=null, content=null, applied=null, busy=false, pending=false, dead=false;
let abort=null;
let playbackKey='';
let renderedTime=-1;
const theme = {
  name:'DuckMusic', description:'', fontStyle:'sans', fontWeight:500,
  animationIntensity:'normal', backgroundColor:'#11101c', primaryColor:'#f1b8a6',
  secondaryColor:'#b7b8d8', textColor:'#ffffff', wordColors:[], lyricsIcons:[],
};
const mistTuning=c=>({...DEFAULT_NEBBIA_TUNING,rain:'off',rainHit:0,rainBig:0,bump:0,
  dew:0,glass:'rain',behind:'night',strokeWidth:Math.max(.04,Math.min(.14,(c.fontWeight??700)/700*.09))});
function playback(force=false) {
  if (!renderer) return;
  const paused=clock.paused || document.hidden;
  const reduced=clock.packet?.reduced ?? false;
  const key=`${paused}:${reduced}`;
  const redraw=force || key!==playbackKey || clock.seconds!==renderedTime;
  if(content.skin==='mist') {
    if(force || key!==playbackKey) renderer.setPlayback(paused,reduced);
    if(paused && clock.packet?.visible && redraw) renderer.requestFrame();
  } else {
    if(force || key!==playbackKey) {renderer.setPaused(paused);renderer.setStaticMode(reduced);}
    if(paused && clock.packet?.visible && redraw) renderer.renderOnce();
  }
  playbackKey=key;renderedTime=clock.seconds;
}
function song(c) {
  const lines=c.lines.map(l=>({...l,
    words:l.words.length?l.words:[{text:l.fullText,startTime:l.startTime,endTime:l.endTime}],
  }));
  const details={seed:c.songKey,theme:{...theme,lyricFontScale:c.fontScale ?? 1,
    fontWeight:c.fontWeight ?? 700},lines,title:c.title,artist:c.artist};
  if(c.skin==='mist') return details;
  const compile=c.skin==='light'?compileLumiereProgram:compileHanabiProgram;
  return {...details,program:compile(lines,c.songKey,{}, {duration:Math.max(1,c.durationMs/1000)})};
}
async function apply() {
  const c=content;
  if(!c || dead) return;
  const input=song(c);
  if(!renderer) {
    abort=new AbortController();
    if(c.skin==='mist') {
      const tuning=mistTuning(c);
      renderer=new NebbiaRuntime({host,seeThrough:false,scene:'night',glass:'rain',
        currentTime:time,vocal:bands.vocal,onFirstFrame:()=>send('ready'),
        onFailed:()=>send('failed','WebGL context lost'),onRestored:()=>send('failed','WebGL context restored')},
        input.theme,tuning,1);
      renderer.setSong(input);renderer.setFontScale(c.fontScale ?? 1);
    } else {
      const common={host,song:input,currentTime:time,paused:true,staticMode:false,
        showText:true,renderScale:1,antialias:false,signal:abort.signal,
        metadata:{title:c.title,artist:c.artist,album:''}};
      renderer=c.skin==='light'
        ? await LumierePixiRuntime.create({...common,audioPower:power,audioBands:bands,
            tuning:{...DEFAULT_LUMIERE_TUNING,overlayFrame:false,renderQuality:'balanced'}})
        : await HanabiPixiRuntime.create({...common,
            tuning:{...DEFAULT_HANABI_TUNING,overlayFrame:false,renderQuality:'balanced'}});
      if(dead) {renderer.destroy();renderer=null;return;}
      renderer.renderOnce();send('ready');
    }
    host.querySelector('canvas')?.addEventListener('webglcontextlost',()=>send('failed','WebGL context lost'),{once:true});
  } else if(c!==applied) {
    if(c.skin==='mist') {renderer.setTheme(input.theme);renderer.setTuning(mistTuning(c));renderer.setSong(input);renderer.setFontScale(c.fontScale ?? 1);}
    else {await renderer.swapSong(input);renderer.setSongMetadata({title:c.title,artist:c.artist,album:''});}
  }
  applied=c;playback(true);
}
async function update() {
  if(busy) {pending=true;return;}
  busy=true;
  try {do {pending=false;await apply();}while(pending&&!dead);}
  catch(error) {send('failed',String(error).slice(0,240));}
  finally {busy=false;}
}
window.DuckFolia={
  receive(packet) {
    if(dead || !clock.receive(packet.sequence,packet.clock)) return;
    if(Array.isArray(packet.bands) && packet.bands.length===32) fft=packet.bands.map(n=>Number.isFinite(n)?Math.max(0,Math.min(1,n)):0);
    if(packet.content) {content=packet.content;void update();}
    playback();
  },
  dispose() {dead=true;abort?.abort();renderer?.destroy();renderer=null;},
};
document.addEventListener('visibilitychange',()=>playback(true));
window.addEventListener('pagehide',()=>window.DuckFolia.dispose());
window.addEventListener('error',e=>send('failed',e.message));
window.addEventListener('unhandledrejection',e=>send('failed',String(e.reason)));
send('loaded');
