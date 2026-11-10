import { build } from 'esbuild';
import { mkdir, writeFile, readFile, copyFile, readdir } from 'node:fs/promises';
import { gunzipSync } from 'node:zlib';
import path from 'node:path';
await mkdir('../../assets/player/folia', {recursive:true});
await writeFile('../../assets/player/folia/strokes.js',
  'window.DuckStrokes='+gunzipSync(await readFile('data/strokes.json.gz')).toString()+';\n');
await copyFile('LICENSE','../../assets/player/folia/LICENSE.txt');
for(const file of await readdir('licenses')) {
  await copyFile('licenses/'+file,'../../assets/player/folia/'+file);
}
const result = await build({entryPoints:['host.js'], outfile:'../../assets/player/folia/renderer.js',
  bundle:true, minify:true, format:'iife', target:'es2020', metafile:true,
  legalComments:'linked', loader:{'.png':'dataurl'},
  plugins:[{name:'native-audio-boundary',setup(build){
    build.onResolve({filter:/services\/analysis\/(drumHits|vocalEnvelope)$/},args=>({
      path:path.resolve('adapters',args.path.split('/').pop()+'.ts'),
    }));
  }}],
  define:{'import.meta.env.BASE_URL':'"./"','import.meta.env.DEV':'false','import.meta.env.PROD':'true','process.env.NODE_ENV':'"production"'},
});
await writeFile('build-inputs.json', JSON.stringify(Object.keys(result.metafile.inputs).filter(x=>x.startsWith('src/')),null,2)+'\n');
const packages = new Set(Object.keys(result.metafile.inputs).filter(x=>x.startsWith('node_modules/')).map(x=>{
  const parts=x.split('/');return parts[1].startsWith('@')?parts.slice(0,3).join('/'):parts.slice(0,2).join('/');
}));
let notices='Bundled JavaScript dependency licenses\n';
for(const dir of [...packages].sort()) {
 const pkg=JSON.parse(await readFile(dir+'/package.json','utf8'));
 const names=(await readdir(dir)).filter(n=>/^(license|licence|copying|notice)(\.|$)/i.test(n));
 if(!names.length && pkg.name!=='@pixi/colord') throw new Error('Missing license for '+dir);
 notices+='\n--- '+pkg.name+' '+pkg.version+' ('+pkg.license+') ---\n';
 if(pkg.name==='@pixi/colord') notices+=await readFile('licenses/colord-MIT.txt','utf8')+'\n';
 for(const name of names) notices+=await readFile(dir+'/'+name,'utf8')+'\n';
}
await writeFile('../../assets/player/folia/THIRD_PARTY_LICENSES.txt',notices);
