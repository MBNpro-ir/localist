const fs=require('node:fs'),path=require('node:path');
const {WebSocket}=require('../.runlogs/qa-node/node_modules/ws');
const out=process.env.LOCALIST_CAPTURE_QA_ROOT || path.resolve(__dirname,'../.runlogs/multicapture-qa');
const pause=ms=>new Promise(r=>setTimeout(r,ms));
class VM {
  async start(){const log=process.env.LOCALIST_CAPTURE_VM_URL?'':fs.readFileSync(path.join(out,'android-attach.log'),'utf8');this.url=process.env.LOCALIST_CAPTURE_VM_URL||log.match(/available at: (http:\/\/\S+)/)?.[1];if(!this.url)throw Error('The capture VM endpoint is not ready');
    this.socket=new WebSocket(this.url.replace('http:','ws:')+'ws',{followRedirects:true});this.sequence=0;this.pending=new Map();
    this.socket.on('message',m=>{const d=JSON.parse(m);if(d.id){const p=this.pending.get(d.id);if(p){this.pending.delete(d.id);clearTimeout(p.timer);d.error?p.reject(Error(JSON.stringify(d.error))):p.resolve(d.result);}}});
    this.socket.on('close',()=>{for(const p of this.pending.values()){clearTimeout(p.timer);p.reject(Error('Dart VM disconnected during the test'));}this.pending.clear();});
    await new Promise((resolve,reject)=>{this.socket.once('open',resolve);this.socket.once('error',reject);});this.isolate=(await this.call('getVM')).isolates[0].id;
    this.libraries=(await this.call('getIsolate',{isolateId:this.isolate})).libraries;
  }
  call(method,params={}){return new Promise((resolve,reject)=>{const id=++this.sequence;const timer=setTimeout(()=>{this.pending.delete(id);reject(Error('Dart VM call timed out: '+method));},30000);this.pending.set(id,{resolve,reject,timer});this.socket.send(JSON.stringify({jsonrpc:'2.0',id,method,params}));});}
  eval(target,expression){return this.call('evaluate',{isolateId:this.isolate,targetId:target,expression});}
  library(suffix){return this.libraries.find(l=>l.uri.endsWith(suffix)).id;}
  async wait(future){const end=Date.now()+30000;while(Date.now()<end){const o=await this.call('getObject',{isolateId:this.isolate,objectId:future.id});const f=Object.fromEntries(o.fields.map(f=>[f.decl.name.split('@')[0],f.value]));const state=Number(f._state.valueAsString);if(state&16){const error=await this.eval(f._resultOrListeners.id,'error.toString()');throw Error('Native async operation failed: '+(error.valueAsString||JSON.stringify(error)));}if(state&8)return f._resultOrListeners;if(state&4)future=f._resultOrListeners;await pause(80);}throw Error('Native operation timed out');}
  async json(target,expression){const value=await this.eval(target,`jsonEncode(${expression})`);const full=value.valueAsStringIsTruncated?await this.call('getObject',{isolateId:this.isolate,objectId:value.id,offset:0,count:100000}):value;return JSON.parse(full.valueAsString);}
}
module.exports={VM};
