import crypto from 'node:crypto';
import http from 'node:http';
const B='http://127.0.0.1:8787', IDP='http://127.0.0.1:9999', EMAIL='tester@local.test', MPH='testhash123';
const IDID='testidp-'+crypto.randomBytes(3).toString('hex');
const {publicKey,privateKey}=crypto.generateKeyPairSync('rsa',{modulusLength:2048});
const kid='mock-kid-1';
const jwk={...publicKey.export({format:'jwk'}),kid,use:'sig',alg:'RS256'};
const b64=o=>Buffer.from(JSON.stringify(o)).toString('base64url');
const codeNonce=new Map();
function signId(nonce){
  const p={iss:IDP,aud:'client-123',sub:'idp-sub-001',email:EMAIL,iat:Math.floor(Date.now()/1000),exp:Math.floor(Date.now()/1000)+300,nonce};
  const body=`${b64({alg:'RS256',typ:'JWT',kid})}.${b64(p)}`;
  return `${body}.${crypto.createSign('RSA-SHA256').update(body).sign(privateKey).toString('base64url')}`;
}
const idp=http.createServer((req,res)=>{
  const u=new URL(req.url,IDP);
  if(u.pathname==='/.well-known/openid-configuration'){return res.end(JSON.stringify({issuer:IDP,authorization_endpoint:IDP+'/authorize',token_endpoint:IDP+'/token',jwks_uri:IDP+'/jwks'}));}
  if(u.pathname==='/jwks'){return res.end(JSON.stringify({keys:[jwk]}));}
  if(u.pathname==='/authorize'){const code='idpc-'+crypto.randomBytes(6).toString('hex');codeNonce.set(code,u.searchParams.get('nonce'));res.writeHead(302,{Location:`${u.searchParams.get('redirect_uri')}?code=${code}&state=${u.searchParams.get('state')}`});return res.end();}
  if(u.pathname==='/token'){let b='';req.on('data',c=>b+=c);req.on('end',()=>res.end(JSON.stringify({access_token:'idp-at',token_type:'Bearer',id_token:signId(codeNonce.get(new URLSearchParams(b).get('code'))||'')})));return;}
  res.writeHead(404);res.end();
});
await new Promise(r=>idp.listen(9999,r));
const J=async r=>{const t=await r.text();try{return JSON.parse(t)}catch{return t}};
let step='';
try{
  step='register';
  await fetch(`${B}/identity/accounts/register`,{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({email:EMAIL,masterPasswordHash:MPH,userSymmetricKey:'k',key:'k',userAsymmetricKeys:{publicKey:'pub',encryptedPrivateKey:'priv'},keys:{publicKey:'pub',encryptedPrivateKey:'priv'},kdf:0,kdfIterations:600000,name:'Tester'})});
  step='login';
  const lj=await J(await fetch(`${B}/identity/connect/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'password',username:EMAIL,password:MPH,scope:'api offline_access',client_id:'web',deviceIdentifier:'dev-1',deviceName:'test',deviceType:'9'})}));
  const tok=lj.access_token||lj.AccessToken; if(!tok)throw new Error('no token: '+JSON.stringify(lj).slice(0,150));
  console.log('✓ login');
  step='create org';
  const oj=await J(await fetch(`${B}/api/organizations`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+tok},body:JSON.stringify({name:'TestOrg',key:'wrapped-org-key',keys:{publicKey:'orgpub',encryptedPrivateKey:'orgpriv'},collectionName:'Default'})}));
  const orgId=oj.id||oj.Id; if(!orgId)throw new Error('no org id'); console.log('✓ org '+orgId.slice(0,8));
  step='config sso';
  const sr=await fetch(`${B}/api/organizations/${orgId}/sso`,{method:'POST',headers:{'Content-Type':'application/json',Authorization:'Bearer '+tok},body:JSON.stringify({enabled:true,identifier:IDID,authority:IDP,clientId:'client-123',clientSecret:'secret-xyz'})});
  if(!sr.ok)throw new Error('sso config '+sr.status); console.log('✓ SSO configured ('+IDID+')');
  step='authorize';
  const az=await fetch(`${B}/sso/authorize?identifier=${IDID}&state=CLIENTSTATE&redirectUri=${encodeURIComponent('http://localhost:9998/cb')}`,{redirect:'manual'});
  const idpUrl=az.headers.get('location'); if(!idpUrl)throw new Error('authorize '+az.status); console.log('✓ authorize → IdP');
  step='idp';
  const cbUrl=(await fetch(idpUrl,{redirect:'manual'})).headers.get('location'); console.log('✓ IdP → callback');
  step='callback';
  const cb=await fetch(cbUrl,{redirect:'manual'}); const fin=cb.headers.get('location');
  if(!fin){console.log('callback',cb.status,(await cb.text()).slice(0,200));throw new Error('no callback redirect');}
  console.log('✓ callback verified id_token (JWKS RS256) + linked + redirected');
  const bw=new URL(fin).searchParams.get('code'); if(!bw)throw new Error('no bw code'); console.log('✓ minted Bitwarden SSO code');
  step='token grant';
  const tj=await J(await fetch(`${B}/identity/connect/token`,{method:'POST',headers:{'Content-Type':'application/x-www-form-urlencoded'},body:new URLSearchParams({grant_type:'authorization_code',code:bw,client_id:'web',deviceIdentifier:'dev-1',deviceName:'test',deviceType:'9'})}));
  const at=tj.access_token||tj.AccessToken; if(!at)throw new Error('no SSO token: '+JSON.stringify(tj).slice(0,200));
  console.log('✓ authorization_code grant → real access token ('+at.length+' chars)');
  console.log('\nFULL SSO OIDC LOGIN WORKED END-TO-END AGAINST THE LIVE WORKER');
  idp.close();process.exit(0);
}catch(e){console.log('✗ FAILED ['+step+']:',e.message);idp.close();process.exit(1);}
