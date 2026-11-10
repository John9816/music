import {test} from 'node:test';
import assert from 'node:assert/strict';
import {build} from 'esbuild';

// Exercise the actual stroke collector, including its transformed pixel width.
const compiled=await build({stdin:{contents:`
 export {drawChar} from './src/components/visualizer/nebbia/nebbiaInk';
 export {NebbiaSegments} from './src/components/visualizer/nebbia/nebbiaSegments';
 export {MASK_SCALE} from './src/components/visualizer/nebbia/nebbiaConstants';
 export {makeTex} from './src/components/visualizer/nebbia/nebbiaGlUtils';
`,resolveDir:process.cwd(),loader:'ts'},bundle:true,write:false,format:'esm',platform:'node',
 define:{'import.meta.env.BASE_URL':'"./"'}});
const {drawChar,NebbiaSegments,MASK_SCALE,makeTex}=await import('data:text/javascript;base64,'+
 Buffer.from(compiled.outputFiles[0].text).toString('base64'));

function draw(size,noDrops=true) {
 const ctx=new NebbiaSegments();let beads=0;
 const stroke={pts:[[.1,.5],[.9,.5]],cum:[0,.8],len:.8};
 const c={glyph:{strokes:[stroke],total:.8},appearDur:0,t:0,wt:0,wd:1,
   s:size,rot:0,x:100,y:100,beads:[[]],ends:[{h:.5,j:0}],drips:[null]};
 drawChar({ctx,motion:{put(){beads++;}},strokeWidth:.09,noDrops,writeSpeed:1,
   busSpeed:0,sweeps:null,wet:null,ice:null},c,2,1);
 return {width:ctx.data[4]/MASK_SCALE,count:ctx.count,beads};
}
test('small mobile glyph strokes retain open space inside the character',()=>{
 const result=draw(24);
 assert.ok(result.count>0);
 assert.ok(result.width<=24*.1,`24px glyph has ${result.width}px stroke`);
 assert.ok(result.width>=1);
 assert.ok(Math.abs(draw(160).width-14.4)<.001);
});
test('drop-free lyrics emit no decorative beads while preserving letter paths',()=>{
 assert.equal(draw(80,true).beads,0);
 assert.ok(draw(80,false).beads>0);
 assert.ok(draw(80,true).count>0);
});
test('an optional sampler has a transparent image before its first active frame',()=>{
 let allocation;
 const gl={createTexture:()=>({}),activeTexture(){},bindTexture(){},texParameteri(){},
   texImage2D(...args){allocation=args;},TEXTURE0:100,TEXTURE_2D:2,RGBA:4,UNSIGNED_BYTE:8};
 makeTex(gl,8);
 assert.equal(allocation[3],1);assert.equal(allocation[4],1);
 assert.deepEqual([...allocation[8]],[0,0,0,0]);
});
