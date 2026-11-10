import {test} from 'node:test';
import assert from 'node:assert/strict';
import {PlaybackClock} from '../clock.mjs';
test('clock interpolates native position, clamps duration and seeks backwards',()=>{
 let now=0;const c=new PlaybackClock(()=>now);
 c.receive(1,{positionMs:2000,durationMs:4000,playing:true,visible:true});
 now=200;assert.equal(c.seconds,2.2);now=3000;assert.equal(c.seconds,2.25);
 c.receive(2,{positionMs:3900,durationMs:4000,playing:true,visible:true});
 now=3200;assert.equal(c.seconds,4);
 c.receive(3,{positionMs:1000,durationMs:4000,playing:false,visible:true});
 now=7000;assert.equal(c.seconds,1);assert.equal(c.paused,true);
});
test('stale packets cannot undo a seek and hidden views do not advance',()=>{
 let now=0;const c=new PlaybackClock(()=>now);
 c.receive(5,{positionMs:3000,durationMs:10000,playing:true,visible:false});
 assert.equal(c.receive(4,{positionMs:0}),false);now=9000;
 assert.equal(c.seconds,3);assert.equal(c.paused,true);
});
