// Native audio remains the authority. Interpolate only while visible and playing.
export class PlaybackClock {
  constructor(now = () => performance.now()) { this.now=now; this.sequence=-1; this.packet=null; this.at=0; }
  receive(sequence, packet) {
    if (!Number.isSafeInteger(sequence) || sequence <= this.sequence) return false;
    this.sequence=sequence;
    if(packet) { this.packet=packet; this.at=this.now(); }
    return true;
  }
  get seconds() {
    const p=this.packet;
    if(!p) return 0;
    const elapsed=p.playing && p.visible ? Math.min(250,Math.max(0,this.now()-this.at)) : 0;
    return Math.max(0, Math.min(p.durationMs>0?p.durationMs:Infinity,p.positionMs+elapsed))/1000;
  }
  get paused() {const p=this.packet; return !p || !p.playing || !p.visible || p.reduced;}
}
