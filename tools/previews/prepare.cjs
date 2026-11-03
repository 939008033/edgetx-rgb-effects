const fs=require('fs'),path=require('path'),assert=require('assert');
const dir=process.argv[2];
assert(dir,"Pass work directory");
const text=fs.readFileSync(path.join(dir,'capture.log'),'utf8').replace(/^\uFEFF/,'');
assert(text.includes('CAPTURE OK: 32 unchanged entry scripts'));
const frames=text.split(/\r?\n/).filter(s=>s.startsWith('FRAME ')).map(s=>JSON.parse(s.slice(6)));
assert.equal(frames.length,240);
const binary=Buffer.alloc(12+240*32*134);binary.writeInt32LE(240,0);binary.writeInt32LE(32,4);binary.writeInt32LE(20,8);
let offset=12;
for(const panels of frames){
 assert.equal(panels.length,32);
 for(const p of panels){
  assert.equal(p.length,40);
  for(let i=0;i<38;i++)for(const c of p[i]){assert(Number.isInteger(c)&&c>=0&&c<=255);binary[offset++]=c;}
  for(const v of [...p[38],p[39]]){assert(Number.isFinite(v));binary.writeFloatLE(v,offset);offset+=4;}
 }
}
assert.equal(offset,binary.length);fs.writeFileSync(path.join(dir,'frames.bin'),binary);
console.log('Prepared '+binary.length+' bytes from 7,680 real Lua frames.');
